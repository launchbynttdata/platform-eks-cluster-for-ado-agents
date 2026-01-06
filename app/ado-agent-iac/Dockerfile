# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

ARG TARGETPLATFORM TARGETOS TARGETARCH TARGETVARIANT BUILDPLATFORM

ARG ASDF_VERSION=0.18.0
ARG GO_VERSION=1.24.7
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      dirmngr \
      gawk \
      gnupg \
      git \
      jq \
      tar \
      wget \
      unzip \
      libicu74 && \
    rm -rf /var/lib/apt/lists/*

# Install Go (map Docker arch -> Go tarball arch)
RUN set -eux; \
  case "$TARGETARCH" in \
    arm64) GO_ARCH=arm64 ;; \
    amd64) GO_ARCH=amd64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"; \
  rm -rf /usr/local/go; tar -C /usr/local -xzf /tmp/go.tgz; rm -f /tmp/go.tgz; \
  /usr/local/go/bin/go version

RUN set -eux; \
  case "$TARGETARCH" in \
    amd64) ASDF_ARCH=amd64 ;; \
    arm64) ASDF_ARCH=arm64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL -o /tmp/asdf.tgz \
    "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-${ASDF_ARCH}.tar.gz"; \
  tar -C /usr/local/bin -xzf /tmp/asdf.tgz; \
  rm -f /tmp/asdf.tgz; \
  /usr/local/bin/asdf --version

# Install AWS CLI (map Docker arch -> AWS package arch)
RUN set -eux; \
  case "$TARGETARCH" in \
    arm64) AWS_ARCH=aarch64 ;; \
    amd64) AWS_ARCH=x86_64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-${TARGETOS}-${AWS_ARCH}.zip" -o awscliv2.zip; \
  unzip awscliv2.zip && \
  ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
  rm -rf awscliv2.zip ./aws

WORKDIR /azp/

COPY --chmod=0755 ./start.sh ./

# Create agent user and set up home directory
RUN useradd -m -d /home/agent agent && \
    chown -R agent:agent /azp /home/agent

USER agent

# Ensure HOME is set for the agent user and asdf data dir is prepared
ENV HOME=/home/agent
ENV PATH="/usr/local/go/bin:/usr/local/bin:${PATH}:/home/agent/.asdf/shims:/home/agent/.asdf/bin:/home/agent/bin"
ENV ASDF_DATA_DIR="$HOME/.asdf"

# Copy tool-versions into the agent home so the agent user can access it during build
COPY --chown=agent:agent .tool-versions /home/agent/.tool-versions

RUN mkdir -p "$ASDF_DATA_DIR" && chown -R agent:agent "$ASDF_DATA_DIR"

# HEALTHCHECK --interval=10s --timeout=3s --start-period=180s --retries=3 \
#         CMD [ "bash", "-c", "ps -ef | grep -q 'Agent.Listener' || exit 1" ]

ENTRYPOINT [ "./start.sh" ]