#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") -r <repo-name> -t <tag> [-g <region>] [--context <docker-build-context>]

  -r, --repo       ECR repository name (e.g., my-app)
  -t, --tag        Image tag (e.g., v1.2.3 or git-sha)
  -g, --region     AWS region (default: \$AWS_REGION or us-west-2)
      --context    Docker build context (default: .)

Environment:
  AWS credentials must be configured (env vars or default profile).

Example:
  $(basename "$0") -r my-app -t v1.2.3 -g us-east-1
EOF
}

# --- args ---
REPO=""
TAG=""
REGION="${AWS_REGION:-us-west-2}"
CTX="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--repo) REPO="$2"; shift 2 ;;
    -t|--tag) TAG="$2"; shift 2 ;;
    -g|--region) REGION="$2"; shift 2 ;;
    --context) CTX="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -z "$REPO" || -z "$TAG" ]] && { usage; exit 1; }

# --- prerequisites ---
command -v aws >/dev/null || { echo "aws CLI not found"; exit 1; }
command -v docker >/dev/null || { echo "docker not found"; exit 1; }

# Ensure buildx is available
if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx not available. Install Docker Buildx first."; exit 1
fi

# Optionally create/use a named builder (safe if it already exists)
if ! docker buildx inspect ecrbuilder >/dev/null 2>&1; then
  docker buildx create --name ecrbuilder --use >/dev/null
else
  docker buildx use ecrbuilder >/dev/null
fi

# --- derive account and ECR URI ---
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${ECR_URI}/${REPO}:${TAG}"

# --- ensure repo exists ---
if ! aws ecr describe-repositories --region "$REGION" --repository-names "$REPO" >/dev/null 2>&1; then
  aws ecr create-repository --region "$REGION" --repository-name "$REPO" >/dev/null
fi

# --- login to ECR ---
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_URI"

# --- build (for linux/amd64) and push ---
docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE" \
  --push \
  "$CTX"

echo "Pushed: $IMAGE"