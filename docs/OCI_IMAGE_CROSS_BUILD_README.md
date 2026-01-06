# Cross-building OCI images from an arm64 (Graviton) bastion

This document explains how to reliably build amd64, arm64, and multi-architecture OCI/Docker images from an arm64 (AWS Graviton) bastion and push them to ECR. It covers local buildx + QEMU emulation, best practices, caveats, and CI examples.

## Quick answer
- Yes — you can build amd64 images on an arm64 Graviton host using Docker Buildx + QEMU emulation.
- Recommended: produce multi-arch images (linux/amd64 + linux/arm64). That ensures the correct image is pulled by Fargate (or other runtimes).
- Caveat: emulation is slower and may fail if the Dockerfile executes platform-specific binaries during build. Prefer cross-compilation or a native x86 builder for those steps.

## Prerequisites (on the bastion)
- Docker (with buildx available). On Linux, install docker and ensure the daemon is running.
- curl, awscli (if pushing to ECR).
- On a remote Linux Graviton host, register QEMU binfmt handlers so emulation works.

### Register QEMU handlers (Linux Graviton example — run as root)

```bash
# Tonistiigi binfmt installer (recommended)
docker run --rm --privileged tonistiigi/binfmt:latest --install all

# Alternative multiarch qemu static
# docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

###  Why prefer tonistiigi/binfmt?

*Reason for recommendation:* tonistiigi/binfmt is maintained by Buildx ecosystem contributors, registers up-to-date binfmt handlers for common architectures with a single, idempotent command, and is designed to integrate cleanly with ephemeral container-based builders. It avoids needing to install or manage persistent static QEMU binaries on the host, reduces host pollution, and simplifies CI/workflow setup where ephemeral containers are preferred.

*About multiarch/qemu-user-static:* the multiarch image remains a valid fallback and can be useful when environments require static QEMU binaries on the host or have legacy workflows. It may however need additional reset steps or manual binary management in some setups.

### Create or bootstrap a buildx builder

```bash
docker buildx create --use --name multi && docker buildx inspect --bootstrap
```

Verify builder is ready:

```bash
docker buildx ls
```

## ECR: login and repo creation (example)
Login to ECR (example variables: ACCOUNT, REGION):

```bash
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REGION="us-west-2"
export ECR_REPO="ado-agent-cluster-ado-agents"
```

```bash
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
```

Create a repo if it doesn't exist:

```bash
aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION || \
  aws ecr create-repository --repository-name $ECR_REPO --region $REGION
```

## Build examples

1) Build amd64 image (emulated) and push directly to ECR (emulated builds are slower):

```bash
docker buildx build \
  --platform linux/amd64 \
  -t $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:amd64 \
  --push \
  .
```

2) Build arm64 image (native on Graviton):

```bash
docker buildx build \
  --platform linux/arm64 \
  -t $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:arm64 \
  --push \
  .
```

3) Build multi-arch manifest (amd64 + arm64) and push (recommended):

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:latest \
  --push \
  .
```

Notes:
- Use `--load` to load a single-platform image into the local Docker engine (only works for single-platform builds).
- Use `--push` to push multi-platform images directly to a registry (no local image created).

## Inspecting pushed multi-arch images
Use buildx imagetools:

```bash
docker buildx imagetools inspect $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/my-repo:latest
```

This shows the manifest list and included platforms.

## Dockerfile tips for reliability
- Avoid executing platform-specific, pre-built binaries during the image build. Emulated execution can fail or be extremely slow.
- If you need to run build-time tools, prefer:
  - Cross-compiling (build host compiles for target arch), or
  - Running that step in CI on an x86 runner, or
  - Using multi-stage builds where the build stage is platform-agnostic (e.g., build in Go using CGO_ENABLED=0 and GOARCH).
- Cache layers where possible; use buildx cache exporters to speed repeated builds.

### Example: multi-stage Go Dockerfile that can be cross-built

```dockerfile
FROM golang:1.20 AS builder
WORKDIR /src
COPY . .
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -o /app ./cmd/app

FROM scratch
COPY --from=builder /app /app
ENTRYPOINT ["/app"]
```

Then set TARGETARCH via build-arg or use platform override when building:

```bash
docker buildx build --platform linux/amd64 --build-arg TARGETARCH=amd64 ...
```

## CI example — GitHub Actions (multi-arch push)
Minimal GH Action using setup-qemu and setup-buildx. This pushes a multi-arch image to ECR via build-push-action.

```yaml
name: build-and-push
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v1
      - name: Build and push multi-arch image
        uses: docker/build-push-action@v5
        with:
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ env.AWS_ACCOUNT_ID }}.dkr.ecr.${{ env.AWS_REGION }}.amazonaws.com/my-repo:latest
```

## Azure DevOps / Other CI notes
- Most hosted runners support building multi-arch with buildx and QEMU; ensure you run QEMU registration or use actions that set it up.
- On self-hosted runners (including Graviton), register QEMU as shown above.

## Troubleshooting
- Builds hang or fail under QEMU: try running `docker buildx inspect --bootstrap` to ensure nodes are ready. Check daemon logs.
- Very slow builds: QEMU emulation is CPU bound. For heavy builds, use a native x86 builder (CI) or a remote x86 VM.
- Runtime issues on target: ensure base images and compiled binaries match the target architecture.
- If Dockerfile runs tests/binaries during build, replace those steps with cross-compilation or move them to CI.

## Recommendations
- Publish multi-arch images whenever possible.
- For heavy or flaky builds, offload amd64 builds to CI or an x86 builder.
- Test final images on target architecture (deploy to a small test pod on Fargate with same architecture).

## Quick checklist for bastion-based builds
- [ ] Register QEMU handlers on bastion
- [ ] Create buildx builder and bootstrap it
- [ ] Confirm ECR repo exists and login works
- [ ] Use `--platform` + `--push` for multi-arch pushes
- [ ] Verify with `docker buildx imagetools inspect`

---

References and useful links
- Docker Buildx: https://docs.docker.com/buildx/working-with-buildx/
- QEMU / binfmt: https://github.com/tonistiigi/binfmt
- Docker build-push-action: https://github.com/docker/build-push-action
- AWS ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html
