#!/usr/bin/env bash
# Read scalar locals from infrastructure-layered/env.hcl for local operational scripts.
# This is intentionally lightweight (no HCL parser dependency) and mirrors deploy.sh
# conventions for simple string/boolean keys at the top level of the locals block.

if [[ -n "${READ_ENV_HCL_LIB_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
READ_ENV_HCL_LIB_LOADED=1

hcl_local_string() {
  local key="$1"
  local file="$2"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${file}" | tail -n 1
}

hcl_local_bool() {
  local key="$1"
  local file="$2"
  local value=""
  value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\([A-Za-z0-9_]*\).*/\1/p" "${file}" | tail -n 1)"
  [[ "${value}" == "true" ]]
}

load_env_hcl_config() {
  local env_file="$1"

  if [[ ! -r "${env_file}" ]]; then
    echo "env.hcl not readable: ${env_file}" >&2
    return 1
  fi

  ENV_HCL_FILE="${env_file}"

  CLUSTER_NAME="$(hcl_local_string cluster_name "${env_file}")"
  AWS_REGION="$(hcl_local_string aws_region "${env_file}")"
  POD_NETWORKING_MODE="$(hcl_local_string pod_networking_mode "${env_file}")"
  [[ -z "${POD_NETWORKING_MODE}" ]] && POD_NETWORKING_MODE="vpc-cni"

  ADO_AGENTS_NAMESPACE="$(hcl_local_string ado_agents_namespace "${env_file}")"
  [[ -z "${ADO_AGENTS_NAMESPACE}" ]] && ADO_AGENTS_NAMESPACE="ado-agents"

  KEDA_NAMESPACE="$(hcl_local_string keda_namespace "${env_file}")"
  [[ -z "${KEDA_NAMESPACE}" ]] && KEDA_NAMESPACE="keda-system"

  ESO_NAMESPACE="$(hcl_local_string eso_namespace "${env_file}")"
  [[ -z "${ESO_NAMESPACE}" ]] && ESO_NAMESPACE="external-secrets-system"

  CLUSTER_SECRET_STORE_NAME="$(hcl_local_string cluster_secret_store_name "${env_file}")"
  [[ -z "${CLUSTER_SECRET_STORE_NAME}" ]] && CLUSTER_SECRET_STORE_NAME="aws-secrets-manager"

  BUILDKIT_NAMESPACE="$(hcl_local_string buildkitd_namespace "${env_file}")"
  [[ -z "${BUILDKIT_NAMESPACE}" ]] && BUILDKIT_NAMESPACE="buildkit-system"

  METRICS_SERVER_NAMESPACE="$(hcl_local_string metrics_server_namespace "${env_file}")"
  [[ -z "${METRICS_SERVER_NAMESPACE}" ]] && METRICS_SERVER_NAMESPACE="kube-system"

  CLUSTER_AUTOSCALER_NAMESPACE="$(hcl_local_string cluster_autoscaler_namespace "${env_file}")"
  [[ -z "${CLUSTER_AUTOSCALER_NAMESPACE}" ]] && CLUSTER_AUTOSCALER_NAMESPACE="kube-system"

  NODE_AUTO_HEAL_NAMESPACE="$(hcl_local_string node_auto_heal_namespace "${env_file}")"
  [[ -z "${NODE_AUTO_HEAL_NAMESPACE}" ]] && NODE_AUTO_HEAL_NAMESPACE="kube-system"

  ADO_AGENT_AUTH_MODE="$(hcl_local_string ado_agent_auth_mode "${env_file}")"
  [[ -z "${ADO_AGENT_AUTH_MODE}" ]] && ADO_AGENT_AUTH_MODE="pat"

  ADO_PAT_SECRET_NAME="$(hcl_local_string ado_pat_secret_name "${env_file}")"
  [[ -z "${ADO_PAT_SECRET_NAME}" ]] && ADO_PAT_SECRET_NAME="ado-agent-pat"

  ADO_AGENT_SPN_SECRET_NAME="$(sed -n '/ado_agent_spn_secret[[:space:]]*=[[:space:]]*{/,/^[[:space:]]*}/p' "${env_file}" \
    | sed -n 's/^[[:space:]]*k8s_secret_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | tail -n 1)"
  [[ -z "${ADO_AGENT_SPN_SECRET_NAME}" ]] && ADO_AGENT_SPN_SECRET_NAME="ado-agent-spn"

  MANAGES_ADO_PAT_SECRET=false
  if [[ "${ADO_AGENT_AUTH_MODE}" != "spn" ]]; then
    MANAGES_ADO_PAT_SECRET=true
  fi

  ADO_SECRET_NAME="$(hcl_local_string ado_secret_name "${env_file}")"
  [[ -z "${ADO_SECRET_NAME}" ]] && ADO_SECRET_NAME="${ADO_PAT_SECRET_NAME}"

  INSTALL_KEDA=false
  hcl_local_bool install_keda "${env_file}" && INSTALL_KEDA=true

  INSTALL_ESO=false
  hcl_local_bool install_eso "${env_file}" && INSTALL_ESO=true

  ENABLE_BUILDKIT=false
  hcl_local_bool enable_buildkitd "${env_file}" && ENABLE_BUILDKIT=true

  INSTALL_METRICS_SERVER=false
  hcl_local_bool install_metrics_server "${env_file}" && INSTALL_METRICS_SERVER=true

  ENABLE_CLUSTER_AUTOSCALER=false
  hcl_local_bool enable_cluster_autoscaler "${env_file}" && ENABLE_CLUSTER_AUTOSCALER=true

  ENABLE_NODE_AUTO_HEAL=false
  hcl_local_bool enable_node_auto_heal "${env_file}" && ENABLE_NODE_AUTO_HEAL=true

  ESO_WEBHOOK_ENABLED=false
  hcl_local_bool eso_webhook_enabled "${env_file}" && ESO_WEBHOOK_ENABLED=true

  if [[ -z "${CLUSTER_NAME}" || -z "${AWS_REGION}" ]]; then
    echo "env.hcl must define cluster_name and aws_region" >&2
    return 1
  fi

  return 0
}
