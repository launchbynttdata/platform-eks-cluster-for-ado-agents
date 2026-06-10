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

# --- prerequisites ---
command -v aws >/dev/null || { echo "aws CLI not found"; exit 1; }
command -v docker >/dev/null || { echo "docker not found"; exit 1; }

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

build_args=(
  buildx build
  --builder "$BUILDER"
  --platform "$PLATFORMS"
  --file "$DOCKERFILE"
  -t "$IMAGE"
)

if [[ "$NO_CACHE" == true ]]; then
  build_args+=(--no-cache)
fi

if [[ "$LOAD" == true ]]; then
  build_args+=(--load)
else
  build_args+=(--push)
fi

build_args+=("$CTX")

echo "Building image: $IMAGE"
echo "Context: $CTX"
echo "Dockerfile: $DOCKERFILE"
echo "Platforms: $PLATFORMS"

docker "${build_args[@]}"

if [[ "$LOAD" == true ]]; then
  echo "Loaded locally: $IMAGE ($PLATFORMS)"
else
  echo "Pushed: $IMAGE ($PLATFORMS)"
fi
