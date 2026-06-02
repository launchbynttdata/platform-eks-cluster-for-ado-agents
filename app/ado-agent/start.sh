#!/bin/bash
set -e

if [ -z "${AZP_AGENT_NAME}" ]; then
  export AZP_AGENT_NAME="${POD_NAME}"
fi

arch="$(uname -m)"
case "$arch" in
  x86_64) agent_pkg_arch="linux-x64" ;;
  aarch64) agent_pkg_arch="linux-arm64" ;;   # 64-bit ARM
  armv7l|armv6l) agent_pkg_arch="linux-arm" ;; # 32-bit ARM if you ever need it
  *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
esac

if [ -z "${AZP_URL}" ]; then
  if [ -z "${AZP_ORG}" ]; then
    echo 1>&2 "error: missing AZP_URL and AZP_ORG. Exiting."
    exit 1
  else
    AZP_URL="https://dev.azure.com/${AZP_ORG}"
  fi
fi

if [ "${AZP_AUTH_MODE:-pat}" = "azure_workload" ]; then
  if [ -z "${AZURE_FEDERATED_TOKEN_FILE}" ] || [ -z "${AZURE_CLIENT_ID}" ] || [ -z "${AZURE_TENANT_ID}" ]; then
    echo 1>&2 "error: missing Azure Workload Identity environment variables"
    exit 1
  fi

  echo "Using Azure Workload Identity credentials to get Azure DevOps token"
  az login \
    --allow-no-subscriptions \
    --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --tenant "$AZURE_TENANT_ID" \
    --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")"

  AZP_TOKEN_RESOURCE="${AZP_TOKEN_RESOURCE:-499b84ac-1321-427f-aa17-267ca6975798}"
  AZP_TOKEN=$(az account get-access-token --resource "$AZP_TOKEN_RESOURCE" --query accessToken --output tsv)
  echo "Token retrieved"
fi

if [ -z "${AZP_TOKEN_FILE}" ]; then
  if [ -z "${AZP_TOKEN}" ]; then
    echo 1>&2 "error: missing AZP_TOKEN environment variable"
    exit 1
  fi

  AZP_TOKEN_FILE="/azp/.token"
  echo -n "${AZP_TOKEN}" > "${AZP_TOKEN_FILE}"
fi

unset AZP_CLIENTSECRET
unset AZP_TOKEN

if [ -n "${AZP_WORK}" ]; then
  mkdir -p "${AZP_WORK}"
fi

cleanup() {
  trap "" EXIT

  if [ -e ./config.sh ]; then
    print_header "Cleanup. Removing Azure Pipelines agent..."

    # If the agent has some running jobs, the configuration removal process will fail.
    # So, give it some time to finish the job.
    while true; do
      ./config.sh remove --unattended --auth "PAT" --token "$(cat "${AZP_TOKEN_FILE}")" && break

      echo "Retrying in 30 seconds..."
      sleep 30
    done
  fi
}

print_header() {
  lightcyan="\033[1;36m"
  nocolor="\033[0m"
  echo -e "\n${lightcyan}$1${nocolor}\n"
}

# Let the agent ignore the token env variables
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

print_header "1. Determining matching Azure Pipelines agent..."

AZP_AGENT_PACKAGES=$(curl -LsS \
    -u "user:$(cat "${AZP_TOKEN_FILE}")" \
    -H "Accept:application/json" \
    "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${agent_pkg_arch}&top=1")

AZP_AGENT_PACKAGE_LATEST_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r ".value[0].downloadUrl")

if [ -z "${AZP_AGENT_PACKAGE_LATEST_URL}" ] || [ "${AZP_AGENT_PACKAGE_LATEST_URL}" = "null" ]; then
  echo 1>&2 "error: could not determine a matching Azure Pipelines agent"
  echo 1>&2 "check that account ${AZP_URL} is correct and the token is valid for that account"
  exit 1
fi

print_header "2. Downloading and extracting Azure Pipelines agent..."

curl -LsS "${AZP_AGENT_PACKAGE_LATEST_URL}" | tar -xz & wait $!

# shellcheck source=/dev/null
source ./env.sh

trap "cleanup; exit 0" EXIT
trap "cleanup; exit 130" INT
trap "cleanup; exit 143" TERM

print_header "3. Configuring Azure Pipelines agent..."

# Despite it saying "PAT", it can be the token through the service principal
./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "${AZP_URL}" \
  --auth "PAT" \
  --token "$(cat "${AZP_TOKEN_FILE}")" \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula & wait $!

print_header "4. Running Azure Pipelines agent..."

chmod +x ./run.sh

# To be aware of TERM and INT signals call ./run.sh
# Running it with the --once flag at the end will shut down the agent after the build is executed
./run.sh "$@" & wait $!
