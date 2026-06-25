FROM ubuntu:24.04
# Also can be "linux-arm", "linux-arm64".
ARG TARGETPLATFORM TARGETOS TARGETARCH TARGETVARIANT BUILDPLATFORM
ENV DEBIAN_FRONTEND=noninteractive

ARG BUILDCTL_VERSION=0.24.0
ARG DOTNET_CHANNEL=9.0
# NVM: pinned Git commit (tag v0.40.4); update NVM_COMMIT_SHA when changing releases.
ARG NVM_COMMIT_SHA=62387b8f92aa012d48202747fd75c40850e5e261
ARG NODE_MAJOR_VERSION=24
ARG MISE_VERSION=v2026.5.13

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      amazon-ecr-credential-helper \
      build-essential \
      ca-certificates \
      curl \
      dirmngr \
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
      python3-venv \
      tar \
      tk-dev \
      unzip \
      wget \
      xz-utils \
      zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Install .NET SDK without add-apt-repository/PPA. The PPA path pulls in
# Python package post-install scripts, which are flaky under amd64 emulation on Apple Silicon.
RUN set -eux; \
  case "$TARGETARCH" in \
    arm64) DOTNET_ARCH=arm64 ;; \
    amd64) DOTNET_ARCH=x64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh; \
  chmod +x dotnet-install.sh; \
  ./dotnet-install.sh --channel "$DOTNET_CHANNEL" --architecture "$DOTNET_ARCH" --install-dir /usr/share/dotnet; \
  ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet; \
  rm dotnet-install.sh; \
  dotnet --version

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

# NVM + Node.js: shallow clone nvm at a fixed commit (no remote install.sh | bash).
ENV NVM_DIR=/usr/local/nvm
RUN /bin/bash -c 'set -euo pipefail; \
  NVM_DIR=/usr/local/nvm; \
  COMMIT_SHA="'"${NVM_COMMIT_SHA}"'"; \
  NODE_VER="'"${NODE_MAJOR_VERSION}"'"; \
  mkdir -p "${NVM_DIR}"; \
  git init -q "${NVM_DIR}"; \
  git -C "${NVM_DIR}" remote add origin https://github.com/nvm-sh/nvm.git; \
  GIT_TERMINAL_PROMPT=0 git -C "${NVM_DIR}" fetch --depth 1 origin "${COMMIT_SHA}"; \
  git -C "${NVM_DIR}" checkout -q FETCH_HEAD; \
  . "${NVM_DIR}/nvm.sh"; \
  nvm install "${NODE_VER}"; \
  nvm alias default "${NODE_VER}"; \
  nvm use default; \
  NODE_HOME="$(dirname "$(dirname "$(command -v node)")")"; \
  ln -sfn "${NODE_HOME}" /usr/local/node-active; \
  rm -rf "${NVM_DIR}/.git"; \
  /usr/local/node-active/bin/node --version; \
  /usr/local/node-active/bin/npm --version'

# agent user: keep Node on PATH for login shells (profile.d) and minimal PATH (symlinks).
RUN printf '%s\n' \
    'export NVM_DIR=/usr/local/nvm' \
    'case ":${PATH}:" in *:/usr/local/node-active/bin:*) ;; *) export PATH="/usr/local/node-active/bin:${PATH}" ;; esac' \
    > /etc/profile.d/node-nvm.sh && chmod 644 /etc/profile.d/node-nvm.sh && \
  ln -sfn /usr/local/node-active/bin/node /usr/local/bin/node && \
  ln -sfn /usr/local/node-active/bin/npm /usr/local/bin/npm && \
  ln -sfn /usr/local/node-active/bin/npx /usr/local/bin/npx && \
  if [ -x /usr/local/node-active/bin/corepack ]; then ln -sfn /usr/local/node-active/bin/corepack /usr/local/bin/corepack; fi

ENV PATH="/usr/local/node-active/bin:${PATH}"

# mise: pinned install; bash activation via /etc/profile.d/mise.sh (see agent .bashrc).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
RUN curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" MISE_INSTALL_PATH="${MISE_INSTALL_PATH}" sh && \
    "${MISE_INSTALL_PATH}" --version

RUN printf '%s\n' \
    '# mise: shims + env hooks for login/interactive bash' \
    'if command -v mise >/dev/null 2>&1; then' \
    '  eval "$(mise activate bash)"' \
    'fi' \
    > /etc/profile.d/mise.sh && chmod 644 /etc/profile.d/mise.sh

WORKDIR /azp/

COPY --chmod=755 ./start.sh ./

# Create agent user and set up home directory
RUN useradd -m -d /home/agent agent && \
    mkdir -p /azp/agent && \
    chown -R agent:agent /azp /home/agent && \
    printf '\n# Node (nvm-managed; PATH + NVM_DIR)\n. /etc/profile.d/node-nvm.sh\n\n# mise (PATH + shims via activate)\n. /etc/profile.d/mise.sh\n' >> /home/agent/.bashrc && \
    chown agent:agent /home/agent/.bashrc

USER agent
# Another option is to run the agent as root.
# ENV AGENT_ALLOW_RUNASROOT="true"

HEALTHCHECK --interval=10s --timeout=3s --start-period=180s --retries=3 \
        CMD [ "bash", "-c", "ps -ef | grep -q 'Agent.Listener' || exit 1" ]

ENTRYPOINT [ "./start.sh" ]
