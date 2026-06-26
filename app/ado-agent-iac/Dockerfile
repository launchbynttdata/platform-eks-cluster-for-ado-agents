# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

ARG TARGETPLATFORM TARGETOS TARGETARCH TARGETVARIANT BUILDPLATFORM

ARG GO_VERSION=1.24.7
ARG TERRAFORM_VERSION=1.13.5
ARG TERRAGRUNT_VERSION=0.93.5
ARG MISE_VERSION=v2026.5.13
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
      zip \
      postgresql-client \
      libicu74 \
      libssl-dev \
      zlib1g-dev \
      libbz2-dev \
      libreadline-dev \
      libsqlite3-dev \
      llvm \
      libncursesw5-dev \
      xz-utils \
      tk-dev \
      libxml2-dev \
      libxmlsec1-dev \
      libffi-dev \
      liblzma-dev && \
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

# Install Terraform binary (map Docker arch -> Terraform package arch)
RUN set -eux; \
  case "$TARGETARCH" in \
    arm64) TF_ARCH=arm64 ;; \
    amd64) TF_ARCH=amd64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TF_ARCH}.zip" -o /tmp/terraform.zip; \
  unzip /tmp/terraform.zip -d /usr/local/bin; \
  chmod +x /usr/local/bin/terraform; \
  rm -f /tmp/terraform.zip; \
  terraform version

# Install Terragrunt binary (map Docker arch -> Terragrunt package arch)
RUN set -eux; \
  case "$TARGETARCH" in \
    arm64) TG_ARCH=arm64 ;; \
    amd64) TG_ARCH=amd64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_${TG_ARCH}" -o /usr/local/bin/terragrunt; \
  chmod +x /usr/local/bin/terragrunt; \
  terragrunt --version

WORKDIR /azp/

COPY --chmod=0755 ./start.sh ./

# Create agent user and set up home directory
RUN useradd -m -d /home/agent agent && \
    mkdir -p /home/agent/.local/share/mise/shims /home/agent/.config/mise /home/agent/.cache/mise && \
    chown -R agent:agent /azp /home/agent

# Azure CLI (service principal login in start.sh). https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends gnupg; \
  install -d /usr/share/keyrings; \
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg; \
  chmod go+r /usr/share/keyrings/microsoft-prod.gpg; \
  . /etc/os-release; \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/repos/azure-cli/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/azure-cli.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends azure-cli; \
  rm -rf /var/lib/apt/lists/*; \
  az version

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
RUN curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" MISE_INSTALL_PATH="${MISE_INSTALL_PATH}" sh && \
    "${MISE_INSTALL_PATH}" --version

USER agent

# Ensure HOME is set for the agent user
ENV HOME=/home/agent
ENV MISE_DATA_DIR=/home/agent/.local/share/mise
ENV MISE_CONFIG_DIR=/home/agent/.config/mise
ENV MISE_CACHE_DIR=/home/agent/.cache/mise
# Configure PATH for agent user
RUN echo "export PATH=\"/home/agent/.local/share/mise/shims:/usr/local/go/bin:/usr/local/bin:\${PATH}:/home/agent/bin\"" >> /home/agent/.profile && \
    echo "export PATH=\"/home/agent/.local/share/mise/shims:/usr/local/go/bin:/usr/local/bin:\${PATH}:/home/agent/bin\"" >> /home/agent/.bashrc
# Set PATH with mise shims
ENV PATH="/home/agent/.local/share/mise/shims:/usr/local/go/bin:/usr/local/bin:${PATH}:/home/agent/bin"

RUN mise --version

# HEALTHCHECK --interval=10s --timeout=3s --start-period=180s --retries=3 \
#         CMD [ "bash", "-c", "ps -ef | grep -q 'Agent.Listener' || exit 1" ]

ENTRYPOINT [ "./start.sh" ]
