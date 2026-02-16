FROM ubuntu:24.04
# Also can be "linux-arm", "linux-arm64".
ARG TARGETPLATFORM TARGETOS TARGETARCH TARGETVARIANT BUILDPLATFORM
ENV DEBIAN_FRONTEND=noninteractive

ARG BUILDCTL_VERSION=0.24.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      software-properties-common && \
    add-apt-repository ppa:dotnet/backports && \
    apt-get update && apt-get upgrade -y && \ 
    apt-get install -y --no-install-recommends \
      amazon-ecr-credential-helper \
      build-essential \
      ca-certificates \
      curl \
      dirmngr \
      dotnet-sdk-9.0 \
      gawk \
      git \
      gnupg \
      jq \
      libbz2-dev \
      libffi-dev \
      libicu74 \
      liblzma-dev \
      libncursesw5-dev \
      libreadline-dev \
      libsqlite3-dev \
      libssl-dev \
      libxml2-dev \
      libxmlsec1-dev \
      llvm \
      postgresql-client \
      python3 \
      python3-dev \
      python3-pip \
      tar \
      tk-dev \
      unzip \
      wget \
      xz-utils \
      zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Install AWS CLI (map Docker arch -> AWS package arch)
RUN set -eux; \
  case "$TARGETARCH" in \
    arm64) AWS_ARCH=aarch64 ;; \
    amd64) AWS_ARCH=x86_64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-${TARGETOS}-${AWS_ARCH}.zip" -o awscliv2.zip && \
  unzip awscliv2.zip && \
  ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
  rm -rf awscliv2.zip ./aws

# buildctl client
RUN set -eux; \
  curl -fsSL -o buildctl.tar.gz "https://github.com/moby/buildkit/releases/download/v${BUILDCTL_VERSION}/buildkit-v${BUILDCTL_VERSION}.linux-${TARGETARCH}.tar.gz" && \
  tar --strip-components=1 -C /usr/local/bin -xzf buildctl.tar.gz && \
  rm buildctl.tar.gz && \
  buildctl --version

# Install endorctl
RUN set -eux; \
  curl -fsSL -o /usr/local/bin/endorctl "https://api.endorlabs.com/download/latest/endorctl_${TARGETOS}_${TARGETARCH}"; \
  chmod +x /usr/local/bin/endorctl; \
  endorctl --version

WORKDIR /azp/

COPY --chmod=755 ./start.sh ./

# Create agent user and set up home directory
RUN useradd -m -d /home/agent agent && \
    mkdir -p /azp/agent && \
    chown -R agent:agent /azp /home/agent

USER agent
# Another option is to run the agent as root.
# ENV AGENT_ALLOW_RUNASROOT="true"

HEALTHCHECK --interval=10s --timeout=3s --start-period=180s --retries=3 \
        CMD [ "bash", "-c", "ps -ef | grep -q 'Agent.Listener' || exit 1" ]

ENTRYPOINT [ "./start.sh" ]
