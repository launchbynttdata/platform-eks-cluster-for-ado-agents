#!/bin/bash
set -euo pipefail

if [ -z "${AZP_AGENT_NAME:-}" ]; then
  export AZP_AGENT_NAME="${POD_NAME:-$(hostname)}"
fi

arch="$(uname -m)"
case "$arch" in
  x86_64) agent_pkg_arch="linux-x64" ;;
  aarch64) agent_pkg_arch="linux-arm64" ;;   # 64-bit ARM
  armv7l|armv6l) agent_pkg_arch="linux-arm" ;; # 32-bit ARM if you ever need it
  *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
esac

if [ -z "${AZP_URL:-}" ]; then
  if [ -z "${AZP_ORG:-}" ]; then
    echo 1>&2 "error: missing AZP_URL and AZP_ORG. Exiting."
    exit 1
  else
    AZP_URL="https://dev.azure.com/${AZP_ORG}"
  fi
fi

# Azure Workload Identity and SPN auth take priority over PAT. Both paths obtain
# an Azure DevOps-scoped token that the agent accepts through --auth PAT.
AZP_TOKEN_RESOURCE="${AZP_TOKEN_RESOURCE:-499b84ac-1321-427f-aa17-267ca6975798}"
if [ "${AZP_AUTH_MODE:-pat}" = "azure_workload" ]; then
  if [ -z "${AZURE_FEDERATED_TOKEN_FILE:-}" ] || [ -z "${AZURE_CLIENT_ID:-}" ] || [ -z "${AZURE_TENANT_ID:-}" ]; then
    echo 1>&2 "error: Azure Workload Identity auth requires AZURE_FEDERATED_TOKEN_FILE, AZURE_CLIENT_ID, and AZURE_TENANT_ID"
    exit 1
  fi

  echo "Using Azure Workload Identity credentials for Azure DevOps"
  az login \
    --allow-no-subscriptions \
    --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --tenant "$AZURE_TENANT_ID" \
    --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")"

  AZP_TOKEN=$(az account get-access-token --resource "$AZP_TOKEN_RESOURCE" --query accessToken --output tsv)
  echo "Token retrieved"
elif [ -n "${AZP_CLIENTID:-}" ] && [ -n "${AZP_CLIENTSECRET:-}" ] && [ -n "${AZP_TENANTID:-}" ]; then
  echo "Using service principal credentials for Azure DevOps (SPN priority over PAT)"
  az login --allow-no-subscriptions --service-principal --username "$AZP_CLIENTID" --password "$AZP_CLIENTSECRET" --tenant "$AZP_TENANTID"
  AZP_TOKEN=$(az account get-access-token --resource "$AZP_TOKEN_RESOURCE" --query accessToken --output tsv)
  echo "Token retrieved"
elif [ -n "${AZP_CLIENTID:-}" ] || [ -n "${AZP_CLIENTSECRET:-}" ] || [ -n "${AZP_TENANTID:-}" ]; then
  echo 1>&2 "error: SPN auth requires AZP_CLIENTID, AZP_CLIENTSECRET, and AZP_TENANTID"
  exit 1
fi

if [ -z "${AZP_TOKEN_FILE:-}" ]; then
  if [ -z "${AZP_TOKEN:-}" ]; then
    echo 1>&2 "error: missing AZP_TOKEN (set PAT/org secret) or complete SPN environment variables"
    exit 1
  fi

  AZP_TOKEN_FILE="/azp/.token"
  echo -n "${AZP_TOKEN}" > "${AZP_TOKEN_FILE}"
fi

unset AZP_CLIENTSECRET
unset AZP_TOKEN

if [ -n "${AZP_WORK:-}" ]; then
  mkdir -p "${AZP_WORK}"
fi

print_header() {
  lightcyan="\033[1;36m"
  nocolor="\033[0m"
  echo -e "\n${lightcyan}$1${nocolor}\n"
}

run_azure_agent_command() {
  set +u
  "$@"
  local status=$?
  set -u
  return "${status}"
}

source_azure_agent_env() {
  set +u
  # shellcheck source=/dev/null
  source ./env.sh
  local status=$?
  set -u
  return "${status}"
}

cleanup() {
  if [ ! -e ./config.sh ]; then
    return 0
  fi

  print_header "Cleanup. Removing Azure Pipelines agent..."

  # If the agent has a running job, config removal can fail until the job ends.
  local cleanup_timeout_seconds="${AZP_CLEANUP_TIMEOUT_SECONDS:-300}"
  local cleanup_deadline=$((SECONDS + cleanup_timeout_seconds))

  while true; do
    if run_azure_agent_command ./config.sh remove --unattended --auth "PAT" --token "$(cat "${AZP_TOKEN_FILE}")"; then
      print_header "Cleanup complete. Azure Pipelines agent removed."
      return 0
    fi

    if [ "${SECONDS}" -ge "${cleanup_deadline}" ]; then
      echo 1>&2 "error: timed out removing Azure Pipelines agent after ${cleanup_timeout_seconds} seconds"
      return 1
    fi

    echo "Retrying in 30 seconds..."
    sleep 30
  done
}

delete_own_pod() {
  if [ "${AZP_RECYCLE_POD_AFTER_RUN_ONCE:-false}" != "true" ]; then
    return 0
  fi

  print_header "Recycling pod after one completed agent run..."

  if [ -z "${POD_NAME:-}" ] || [ -z "${POD_NAMESPACE:-}" ]; then
    echo 1>&2 "error: pod recycling requires POD_NAME and POD_NAMESPACE"
    return 1
  fi

  if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
    echo 1>&2 "error: pod recycling requires Kubernetes service environment variables"
    return 1
  fi

  local token_file="/var/run/secrets/kubernetes.io/serviceaccount/token"
  local ca_file="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  if [ ! -r "${token_file}" ] || [ ! -r "${ca_file}" ]; then
    echo 1>&2 "error: pod recycling requires a mounted Kubernetes service account token"
    return 1
  fi

  local token
  token="$(cat "${token_file}")"
  local api
  api="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS:-443}/api/v1/namespaces/${POD_NAMESPACE}/pods/${POD_NAME}"

  local response_file="/tmp/delete-pod-response.json"
  local http_code
  http_code="$(curl -sS -o "${response_file}" -w "%{http_code}" \
    --cacert "${ca_file}" \
    -H "Authorization: Bearer ${token}" \
    -X DELETE \
    "${api}")"

  case "${http_code}" in
    200|202)
      print_header "Pod recycle requested for ${POD_NAMESPACE}/${POD_NAME}."
      ;;
    *)
      echo 1>&2 "error: failed to request pod recycle for ${POD_NAMESPACE}/${POD_NAME}; Kubernetes API returned HTTP ${http_code}"
      if [ -s "${response_file}" ]; then
        cat "${response_file}" >&2
      fi
      return 1
      ;;
  esac
}

# shellcheck disable=SC2329
cleanup_and_exit() {
  local exit_code="$1"
  trap "" EXIT
  cleanup || true
  exit "${exit_code}"
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

source_azure_agent_env

trap 'cleanup_and_exit $?' EXIT
trap "cleanup_and_exit 130" INT
trap "cleanup_and_exit 143" TERM

print_header "3. Configuring Azure Pipelines agent..."

# Despite it saying "PAT", it can be the token through the service principal
run_azure_agent_command ./config.sh --unattended \
  --agent "${AZP_AGENT_NAME:-$(hostname)}" \
  --url "${AZP_URL}" \
  --auth "PAT" \
  --token "$(cat "${AZP_TOKEN_FILE}")" \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula

if [ "${AZP_PLACEHOLDER_AGENT:-false}" = "true" ]; then
  print_header "Azure Pipelines placeholder agent ${AZP_AGENT_NAME:-$(hostname)} registered. Exiting without unregistering so the offline template remains in the pool."
  trap "" EXIT
  exit 0
fi

print_header "4. Running Azure Pipelines agent..."

chmod +x ./run.sh

run_args=("$@")
if [ "${AZP_RUN_ONCE:-false}" = "true" ]; then
  run_args+=("--once")
fi

# To be aware of TERM and INT signals call ./run.sh directly and wait on it.
set +u
./run.sh "${run_args[@]}" &
agent_pid=$!
set -u
if wait "${agent_pid}"; then
  agent_exit=0
else
  agent_exit=$?
fi

if [ "${AZP_RUN_ONCE:-false}" = "true" ]; then
  print_header "Azure Pipelines agent exited after one run with status ${agent_exit}."
  trap "" EXIT
  cleanup
  delete_own_pod
fi

exit "${agent_exit}"
