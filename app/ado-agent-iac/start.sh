#!/bin/bash
set -euo pipefail

if [ -z "${AZP_AGENT_NAME:-}" ]; then
  export AZP_AGENT_NAME="${POD_NAME}"
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

if [ -n "${AZP_CLIENTID:-}" ]; then
  echo "Using service principal credentials to get token"
  az login --allow-no-subscriptions --service-principal --username "$AZP_CLIENTID" --password "$AZP_CLIENTSECRET" --tenant "$AZP_TENANTID"
  # adapted from https://learn.microsoft.com/en-us/azure/databricks/dev-tools/user-aad-token
  AZP_TOKEN=$(az account get-access-token --query accessToken --output tsv)
  echo "Token retrieved"
fi

if [ -z "${AZP_TOKEN_FILE:-}" ]; then
  if [ -z "${AZP_TOKEN:-}" ]; then
    echo 1>&2 "error: missing AZP_TOKEN environment variable"
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
  local timeout_seconds="${AZP_CLEANUP_TIMEOUT_SECONDS:-300}"
  local deadline=$((SECONDS + timeout_seconds))

  if [ -e ./config.sh ]; then
    print_header "Cleanup. Removing Azure Pipelines agent..."

    # If the agent has some running jobs, the configuration removal process will fail.
    # So, give it some time to finish the job.
    while [ "${SECONDS}" -lt "${deadline}" ]; do
      if run_azure_agent_command ./config.sh remove --unattended --auth "PAT" --token "$(cat "${AZP_TOKEN_FILE}")"; then
        echo "Azure Pipelines agent removed."
        return 0
      fi

      echo "Retrying in 30 seconds..."
      sleep 30
    done

    echo "error: timed out removing Azure Pipelines agent after ${timeout_seconds}s" >&2
    return 1
  fi
}

delete_own_pod() {
  if [ "${AZP_RECYCLE_POD_AFTER_RUN_ONCE:-false}" != "true" ]; then
    return 0
  fi

  if [ -z "${POD_NAME:-}" ] || [ -z "${POD_NAMESPACE:-}" ]; then
    echo "error: cannot recycle pod because POD_NAME or POD_NAMESPACE is missing" >&2
    return 1
  fi

  local token_file="/var/run/secrets/kubernetes.io/serviceaccount/token"
  local ca_file="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  if [ ! -r "${token_file}" ] || [ ! -r "${ca_file}" ]; then
    echo "error: cannot recycle pod because the Kubernetes service account token is not mounted" >&2
    return 1
  fi

  print_header "Recycling pod ${POD_NAMESPACE}/${POD_NAME}..."
  local token
  token="$(cat "${token_file}")"
  local api="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS:-443}/api/v1/namespaces/${POD_NAMESPACE}/pods/${POD_NAME}"
  local http_code
  http_code="$(curl -sS -o /tmp/delete-pod-response.json -w "%{http_code}" \
    --cacert "${ca_file}" \
    -H "Authorization: Bearer ${token}" \
    -X DELETE \
    "${api}")"

  case "${http_code}" in
    200|202)
      echo "Pod recycle requested."
      ;;
    *)
      echo "error: failed to recycle pod; Kubernetes API returned ${http_code}" >&2
      cat /tmp/delete-pod-response.json >&2 || true
      return 1
      ;;
  esac
}

# Let the agent ignore the token env variables
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

print_header "1. Determining matching Azure Pipelines agent..."

AZP_AGENT_PACKAGES=$(curl -LsS \
    -u "user:$(cat "${AZP_TOKEN_FILE}")" \
    -H "Accept:application/json" \
    "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${agent_pkg_arch}&top=1")

AZP_AGENT_PACKAGE_LATEST_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r ".value[0].downloadUrl")

if [ -z "${AZP_AGENT_PACKAGE_LATEST_URL}" ] || [ "${AZP_AGENT_PACKAGE_LATEST_URL}" == "null" ]; then
  echo 1>&2 "error: could not determine a matching Azure Pipelines agent"
  echo 1>&2 "check that account ${AZP_URL} is correct and the token is valid for that account"
  exit 1
fi

print_header "2. Downloading and extracting Azure Pipelines agent..."

curl -LsS "${AZP_AGENT_PACKAGE_LATEST_URL}" | tar -xz & wait $!

source_azure_agent_env

# shellcheck disable=SC2329
cleanup_and_exit() {
  local exit_code="$1"
  trap "" EXIT
  cleanup || true
  exit "${exit_code}"
}

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

# To be aware of TERM and INT signals call ./run.sh
# Running it with the --once flag at the end will shut down the agent after the build is executed
run_args=("$@")
if [ "${AZP_RUN_ONCE:-false}" = "true" ]; then
  run_args+=("--once")
fi

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
