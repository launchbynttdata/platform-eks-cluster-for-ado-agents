#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") -r <repo-name> -t <tag> [-g <region>] [options]

  -r, --repo        ECR repository name (e.g., ado-agent)
  -t, --tag         Image tag (e.g., v1.2.3 or git-sha)
  -g, --region      AWS region (default: \$AWS_REGION or us-west-2)
      --context     Docker build context (default: .)
  -f, --file        Dockerfile path (default: <context>/Dockerfile)
  -p, --platforms   Target platforms (default: linux/amd64,linux/arm64)
      --builder     Docker Buildx builder name (default: ecrbuilder)
      --load        Load the image into local Docker instead of pushing.
                    Only valid with one platform.
      --no-cache    Build without cache.

Environment:
  AWS credentials must be configured (env vars or default profile).
  Docker Buildx must be available. Docker Desktop on Apple Silicon supports
  cross-building linux/amd64 and linux/arm64 images with Buildx.

Structure tests:
  When <context>/container-structure-test.yaml exists, the script builds once,
  runs container-structure-test, then pushes (or loads) that image. Multi-arch
  pushes build and test the first --platforms value, push it, then build any
  remaining platforms and assemble the manifest with buildx imagetools.

Examples:
  # Push one manifest tag that works on Linux x86_64 and arm64 cluster nodes.
  $(basename "$0") -r ado-agent -t v1.2.3 --context app/ado-agent

  # Push only the Linux x86_64 image.
  $(basename "$0") -r ado-agent -t v1.2.3 --context app/ado-agent --platforms linux/amd64

  # Build one Linux arm64 image locally for a quick smoke test on Apple Silicon.
  $(basename "$0") -r ado-agent -t local-test --context app/ado-agent --platforms linux/arm64 --load
EOF
}

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z "$value" || "$value" == -* ]]; then
    echo "Missing value for ${option}" >&2
    usage
    exit 1
  fi
}

first_platform() {
  local platforms="$1"
  echo "${platforms%%,*}"
}

platform_tag_suffix() {
  local platform="${1//[[:space:]]/}"

  case "$platform" in
    linux/amd64) echo "amd64" ;;
    linux/arm64) echo "arm64" ;;
    *)
      echo "$platform" | tr '/:' '--'
      ;;
  esac
}

remaining_platforms() {
  local platforms="$1"
  local skip="${2//[[:space:]]/}"
  local -a remaining=()
  local p

  IFS=',' read -ra platform_list <<< "$platforms"
  for p in "${platform_list[@]}"; do
    p="${p//[[:space:]]/}"
    if [[ -n "$p" && "$p" != "$skip" ]]; then
      remaining+=("$p")
    fi
  done

  if [[ ${#remaining[@]} -eq 0 ]]; then
    echo ""
  else
    local IFS=,
    echo "${remaining[*]}"
  fi
}

# --- args ---
REPO=""
TAG=""
REGION="${AWS_REGION:-us-west-2}"
CTX="."
DOCKERFILE=""
PLATFORMS="${DOCKER_PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${DOCKER_BUILDX_BUILDER:-ecrbuilder}"
LOAD=false
NO_CACHE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r | --repo)
      require_value "$1" "${2:-}"
      REPO="$2"
      shift 2
      ;;
    -t | --tag)
      require_value "$1" "${2:-}"
      TAG="$2"
      shift 2
      ;;
    -g | --region)
      require_value "$1" "${2:-}"
      REGION="$2"
      shift 2
      ;;
    --context)
      require_value "$1" "${2:-}"
      CTX="$2"
      shift 2
      ;;
    -f | --file)
      require_value "$1" "${2:-}"
      DOCKERFILE="$2"
      shift 2
      ;;
    -p | --platform | --platforms)
      require_value "$1" "${2:-}"
      PLATFORMS="$2"
      shift 2
      ;;
    --builder)
      require_value "$1" "${2:-}"
      BUILDER="$2"
      shift 2
      ;;
    --load)
      LOAD=true
      shift
      ;;
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -z "$REPO" || -z "$TAG" ]] && { usage; exit 1; }
[[ -z "$DOCKERFILE" ]] && DOCKERFILE="${CTX%/}/Dockerfile"

if [[ ! -d "$CTX" ]]; then
  echo "Docker build context not found: $CTX" >&2
  exit 1
fi

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "Dockerfile not found: $DOCKERFILE" >&2
  exit 1
fi

if [[ "$LOAD" == true && "$PLATFORMS" == *,* ]]; then
  echo "--load only supports a single platform. Use --platforms linux/amd64 or --platforms linux/arm64." >&2
  exit 1
fi

STRUCTURE_TEST_CONFIG="${CTX%/}/container-structure-test.yaml"
RUN_STRUCTURE_TESTS=false
if [[ -f "$STRUCTURE_TEST_CONFIG" ]]; then
  RUN_STRUCTURE_TESTS=true
fi

# --- prerequisites ---
command -v aws >/dev/null || { echo "aws CLI not found"; exit 1; }
command -v docker >/dev/null || { echo "docker not found"; exit 1; }

if [[ "$RUN_STRUCTURE_TESTS" == true ]]; then
  command -v container-structure-test >/dev/null || {
    echo "container-structure-test not found (install via mise: container-structure-test)" >&2
    exit 1
  }
fi

# Ensure buildx is available
if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx not available. Install Docker Buildx first."
  exit 1
fi

# Create/use a named container builder so multi-architecture exports work on Apple Silicon.
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null
else
  docker buildx use "$BUILDER" >/dev/null
fi
docker buildx inspect "$BUILDER" --bootstrap >/dev/null

# --- derive account and ECR URI ---
ACCOUNT_ID="$(aws sts get-caller-identity --region "$REGION" --query Account --output text)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${ECR_URI}/${REPO}:${TAG}"

# --- ensure repo exists ---
if ! aws ecr describe-repositories --region "$REGION" --repository-names "$REPO" >/dev/null 2>&1; then
  aws ecr create-repository --region "$REGION" --repository-name "$REPO" >/dev/null
fi

# --- login to ECR ---
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_URI"

run_buildx() {
  local platform="$1"
  local output_mode="$2"
  local image_tag="$3"

  local args=(
    buildx build
    --builder "$BUILDER"
    --platform "$platform"
    --file "$DOCKERFILE"
    -t "$image_tag"
  )

  if [[ "$NO_CACHE" == true ]]; then
    args+=(--no-cache)
  fi

  args+=("$output_mode" "$CTX")
  docker "${args[@]}"
}

# Single-platform build loaded into the local Docker daemon. container-structure-test
# reads images from the default daemon, not the buildx docker-container builder cache.
run_local_build() {
  local platform="$1"
  local image_tag="$2"

  local args=(
    build
    --platform "$platform"
    --file "$DOCKERFILE"
    -t "$image_tag"
  )

  if [[ "$NO_CACHE" == true ]]; then
    args+=(--no-cache)
  fi

  args+=("$CTX")
  docker "${args[@]}"
  ensure_local_image "$image_tag"
}

ensure_local_image() {
  local image_tag="$1"

  if ! docker image inspect "$image_tag" >/dev/null 2>&1; then
    echo "Image not found in local Docker daemon after build: $image_tag" >&2
    echo "container-structure-test requires the image in the default docker engine image store." >&2
    exit 1
  fi
}

run_structure_tests() {
  local test_image="$1"
  local test_platform="$2"

  ensure_local_image "$test_image"

  echo "Running container structure tests"
  echo "Config: $STRUCTURE_TEST_CONFIG"
  echo "Image: $test_image"
  echo "Platform: $test_platform"
  container-structure-test test \
    --image "$test_image" \
    --config "$STRUCTURE_TEST_CONFIG" \
    --platform "$test_platform"
}

TEST_PLATFORM="$(first_platform "$PLATFORMS")"

if [[ "$RUN_STRUCTURE_TESTS" == true ]]; then
  if [[ "$PLATFORMS" == *,* ]]; then
    BUILD_IMAGE="${IMAGE}-$(platform_tag_suffix "$TEST_PLATFORM")"
    BUILD_PLATFORM="$TEST_PLATFORM"
  else
    BUILD_IMAGE="$IMAGE"
    BUILD_PLATFORM="$PLATFORMS"
  fi

  echo "Building image: $BUILD_IMAGE"
  echo "Context: $CTX"
  echo "Dockerfile: $DOCKERFILE"
  echo "Platforms: $BUILD_PLATFORM"
  run_local_build "$BUILD_PLATFORM" "$BUILD_IMAGE"
  run_structure_tests "$BUILD_IMAGE" "$BUILD_PLATFORM"

  if [[ "$LOAD" == true ]]; then
    if [[ "$BUILD_IMAGE" != "$IMAGE" ]]; then
      docker tag "$BUILD_IMAGE" "$IMAGE"
    fi
    echo "Loaded locally: $IMAGE ($BUILD_PLATFORM)"
  elif [[ "$PLATFORMS" == *,* ]]; then
    echo "Pushing structure-tested image: $BUILD_IMAGE"
    docker push "$BUILD_IMAGE"
  else
    echo "Pushing image: $IMAGE"
    docker push "$IMAGE"
    echo "Pushed: $IMAGE ($PLATFORMS)"
  fi

  if [[ "$LOAD" == false && "$PLATFORMS" == *,* ]]; then
    platforms_to_build="$(remaining_platforms "$PLATFORMS" "$TEST_PLATFORM")"
    if [[ -n "$platforms_to_build" ]]; then
      refs=("$BUILD_IMAGE")
      IFS=',' read -ra other_platforms <<< "$platforms_to_build"
      for platform in "${other_platforms[@]}"; do
        platform="${platform//[[:space:]]/}"
        arch_image="${IMAGE}-$(platform_tag_suffix "$platform")"
        echo "Building and pushing platform: $platform ($arch_image)"
        run_buildx "$platform" --push "$arch_image"
        refs+=("$arch_image")
      done
      echo "Creating multi-arch manifest: $IMAGE"
      docker buildx imagetools create -t "$IMAGE" "${refs[@]}"
    else
      echo "Creating manifest: $IMAGE"
      docker buildx imagetools create -t "$IMAGE" "$BUILD_IMAGE"
    fi
    echo "Pushed: $IMAGE ($PLATFORMS)"
  fi
else
  echo "Building image: $IMAGE"
  echo "Context: $CTX"
  echo "Dockerfile: $DOCKERFILE"
  echo "Platforms: $PLATFORMS"

  if [[ "$LOAD" == true ]]; then
    run_buildx "$PLATFORMS" --load "$IMAGE"
    echo "Loaded locally: $IMAGE ($PLATFORMS)"
  else
    run_buildx "$PLATFORMS" --push "$IMAGE"
    echo "Pushed: $IMAGE ($PLATFORMS)"
  fi
fi
