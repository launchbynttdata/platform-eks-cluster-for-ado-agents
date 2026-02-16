# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

ARG TARGETPLATFORM TARGETOS TARGETARCH TARGETVARIANT BUILDPLATFORM

ARG GO_VERSION=1.24.7
ARG PYTHON_VERSION=3.13.0
ARG TERRAFORM_VERSION=1.13.5
ARG TERRAGRUNT_VERSION=0.93.5
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

  # Install Python from official tarball (manual compilation)
RUN set -eux; \
  curl -fsSL -o /tmp/python.tgz "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"; \
  tar -C /tmp -xzf /tmp/python.tgz; \
  cd /tmp/Python-${PYTHON_VERSION}; \
  PYTHON_MAJOR_MINOR=$(echo ${PYTHON_VERSION} | cut -d. -f1,2); \
  ./configure --prefix=/usr/local/python${PYTHON_MAJOR_MINOR} --enable-optimizations --with-ensurepip=install; \
  make -j$(nproc); \
  make install; \
  rm -rf /tmp/python.tgz /tmp/Python-${PYTHON_VERSION}; \
  /usr/local/python${PYTHON_MAJOR_MINOR}/bin/python3 --version

WORKDIR /azp/

COPY --chmod=0755 ./start.sh ./

# Create agent user and set up home directory
RUN useradd -m -d /home/agent agent && \
    chown -R agent:agent /azp /home/agent

# Create Python symlinks as root before switching to agent user
RUN PYTHON_MAJOR_MINOR=$(echo ${PYTHON_VERSION} | cut -d. -f1,2) && \
    PYTHON_MAJOR=$(echo ${PYTHON_VERSION} | cut -d. -f1) && \
    ln -sf /usr/local/python${PYTHON_MAJOR_MINOR}/bin/python${PYTHON_MAJOR} /usr/local/bin/python${PYTHON_MAJOR} && \
    ln -sf /usr/local/python${PYTHON_MAJOR_MINOR}/bin/pip${PYTHON_MAJOR} /usr/local/bin/pip${PYTHON_MAJOR}

USER agent

# Ensure HOME is set for the agent user
ENV HOME=/home/agent
# Configure PATH for agent user
RUN PYTHON_MAJOR_MINOR=$(echo ${PYTHON_VERSION} | cut -d. -f1,2) && \
    echo "export PATH=\"/usr/local/go/bin:/usr/local/bin:/usr/local/python${PYTHON_MAJOR_MINOR}/bin:\${PATH}:/home/agent/bin\"" >> /home/agent/.profile && \
    echo "export PATH=\"/usr/local/go/bin:/usr/local/bin:/usr/local/python${PYTHON_MAJOR_MINOR}/bin:\${PATH}:/home/agent/bin\"" >> /home/agent/.bashrc
# Set PATH with symlinked python location
ENV PATH="/usr/local/go/bin:/usr/local/bin:${PATH}:/home/agent/bin"

# HEALTHCHECK --interval=10s --timeout=3s --start-period=180s --retries=3 \
#         CMD [ "bash", "-c", "ps -ef | grep -q 'Agent.Listener' || exit 1" ]

ENTRYPOINT [ "./start.sh" ]