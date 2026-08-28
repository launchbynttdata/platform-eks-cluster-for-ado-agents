#!/usr/bin/env bash
#
# functional-test-cluster.sh
#
# Local functional validation for a deployed EKS cluster managed by this repo.
# Reads cluster settings from infrastructure-layered/env.hcl, configures kubectl,
# and verifies internal platform components and their interactions.
#
# This script does NOT queue Azure DevOps agent jobs or trigger KEDA scale-out.
# It is intended for operator use after deploy.sh, not for GitHub Actions.
#
# Usage:
#   ./infrastructure-layered/scripts/functional-test-cluster.sh
#   ./infrastructure-layered/scripts/functional-test-cluster.sh --env-file /path/to/env.hcl
#   ./infrastructure-layered/scripts/functional-test-cluster.sh --skip-kubeconfig
#   ./infrastructure-layered/scripts/functional-test-cluster.sh --verbose
#
# Exit codes:
#   0 - all executed tests passed
#   1 - one or more tests failed
#   2 - configuration or prerequisite error

set -uo pipefail

if ! command -v kubectl >/dev/null 2>&1 && command -v mise >/dev/null 2>&1; then
  exec mise exec -- bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYERED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${LAYERED_DIR}/.." && pwd)"

# shellcheck source=lib/read-env-hcl.sh
source "${SCRIPT_DIR}/lib/read-env-hcl.sh"

ENV_FILE="${LAYERED_DIR}/env.hcl"
CONFIGURE_KUBECONFIG=true
VERBOSE=false
CONNECTIVITY_TIMEOUT_SECONDS=120

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
CURRENT_SECTION=""
SCALEDJOB_COUNT=0

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

log() {
  printf '%s\n' "$*"
}

log_verbose() {
  if [[ "${VERBOSE}" == "true" ]]; then
    printf '  %s\n' "$*"
  fi
}

section() {
  CURRENT_SECTION="$1"
  log ""
  log "== ${CURRENT_SECTION} =="
}

run_test() {
  local name="$1"
  shift

  if "$@"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    log "  PASS  ${name}"
    return 0
  fi

  FAIL_COUNT=$((FAIL_COUNT + 1))
  log "  FAIL  ${name}"
  return 1
}

skip_test() {
  local name="$1"
  local reason="$2"
  SKIP_COUNT=$((SKIP_COUNT + 1))
  log "  SKIP  ${name} (${reason})"
}

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1
}

kubectl_cmd() {
  kubectl "$@"
}

helm_cmd() {
  helm "$@"
}

aws_cmd() {
  aws "$@"
}

json_field() {
  local json="$1"
  local python_expr="$2"
  printf '%s' "${json}" | python3 -c "import json,sys; data=json.load(sys.stdin); print(${python_expr})" 2>/dev/null
}

# --- prerequisite checks ---

test_prerequisites() {
  section "Prerequisites"

  run_test "aws CLI available" require_command aws || return 1
  run_test "kubectl available" require_command kubectl || return 1
  run_test "helm CLI available" require_command helm || return 1

  run_test "AWS caller identity resolvable" aws_cmd sts get-caller-identity >/dev/null
}

configure_kubeconfig() {
  if [[ "${CONFIGURE_KUBECONFIG}" != "true" ]]; then
    skip_test "configure kubeconfig" "disabled via --skip-kubeconfig"
    return 0
  fi

  section "Cluster access"

  run_test "EKS cluster exists (${CLUSTER_NAME})" \
    aws_cmd eks describe-cluster --region "${AWS_REGION}" --name "${CLUSTER_NAME}" >/dev/null

  if aws_cmd eks update-kubeconfig \
    --region "${AWS_REGION}" \
    --name "${CLUSTER_NAME}" \
    --alias "${CLUSTER_NAME}" >/dev/null 2>&1; then
    PASS_COUNT=$((PASS_COUNT + 1))
    log "  PASS  kubeconfig updated for ${CLUSTER_NAME}"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "  FAIL  kubeconfig update for ${CLUSTER_NAME}"
    return 1
  fi

  run_test "kubectl can reach API server" kubectl_cmd cluster-info >/dev/null
  run_test "cluster nodes are Ready" _test_nodes_ready
}

_test_nodes_ready() {
  local not_ready=""
  not_ready="$(kubectl_cmd get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}' | tr '\n' ' ')"
  [[ -z "${not_ready}" ]]
}

# --- networking / CNI ---

test_networking() {
  section "Networking (${POD_NETWORKING_MODE})"

  if [[ "${POD_NETWORKING_MODE}" == "cilium-overlay" ]]; then
    run_test "Cilium Helm release present" helm_cmd status cilium -n kube-system >/dev/null
    run_test "Cilium operator deployment ready" _test_cilium_operator_ready
    run_test "Cilium agent daemonset ready" _test_cilium_agent_ready
    run_test "aws-node daemonset absent or not scheduled on nodes" _test_aws_node_not_scheduled
  else
    run_test "aws-node daemonset ready" _test_daemonset_ready kube-system aws-node
    skip_test "Cilium overlay checks" "pod_networking_mode=${POD_NETWORKING_MODE}"
  fi

  run_test "CoreDNS deployment ready" _test_deployment_ready kube-system coredns
  run_test "in-cluster DNS resolves kubernetes.default" _test_cluster_dns
}

_test_deployment_ready() {
  local namespace="$1"
  local name="$2"
  local ready desired

  if ! kubectl_cmd get deployment -n "${namespace}" "${name}" >/dev/null 2>&1; then
    log_verbose "deployment ${namespace}/${name} not found"
    return 1
  fi

  read -r ready desired < <(
    kubectl_cmd get deployment -n "${namespace}" "${name}" \
      -o jsonpath='{.status.readyReplicas} {.spec.replicas}' 2>/dev/null
  )

  [[ -n "${ready}" && -n "${desired}" && "${ready}" == "${desired}" && "${desired}" != "0" ]]
}

_test_daemonset_ready() {
  local namespace="$1"
  local name="$2"
  local ready desired

  if ! kubectl_cmd get daemonset -n "${namespace}" "${name}" >/dev/null 2>&1; then
    log_verbose "daemonset ${namespace}/${name} not found"
    return 1
  fi

  read -r ready desired < <(
    kubectl_cmd get daemonset -n "${namespace}" "${name}" \
      -o jsonpath='{.status.numberReady} {.status.desiredNumberScheduled}' 2>/dev/null
  )

  [[ -n "${ready}" && -n "${desired}" && "${ready}" == "${desired}" && "${desired}" != "0" ]]
}

_test_cilium_operator_ready() {
  local ready desired name=""
  name="$(kubectl_cmd get deployment -n kube-system \
    -l app.kubernetes.io/name=cilium-operator \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${name}" ]]; then
    name="$(kubectl_cmd get deployment -n kube-system \
      -l name=cilium-operator \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  [[ -n "${name}" ]] || return 1
  _test_deployment_ready kube-system "${name}"
}

_test_cilium_agent_ready() {
  local ready desired name=""
  name="$(kubectl_cmd get daemonset -n kube-system \
    -l k8s-app=cilium \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${name}" ]]; then
    name="cilium"
  fi
  _test_daemonset_ready kube-system "${name}"
}

_test_aws_node_not_scheduled() {
  if ! kubectl_cmd get daemonset -n kube-system aws-node >/dev/null 2>&1; then
    return 0
  fi

  local scheduled
  scheduled="$(kubectl_cmd get daemonset -n kube-system aws-node \
    -o jsonpath='{.status.currentNumberScheduled}' 2>/dev/null || echo "0")"
  [[ "${scheduled}" == "0" ]]
}

_test_cluster_dns() {
  local pod_name="functional-test-dns-$$"
  kubectl_cmd run "${pod_name}" \
    --restart=Never \
    --image=public.ecr.aws/docker/library/busybox:1.36 \
    --rm -i --quiet \
    --command -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1
}

# --- metrics server ---

test_metrics_server() {
  section "Metrics server"

  if [[ "${INSTALL_METRICS_SERVER}" != "true" ]]; then
    skip_test "metrics-server deployment" "install_metrics_server=false"
    return 0
  fi

  run_test "metrics-server deployment ready" \
    _test_deployment_ready "${METRICS_SERVER_NAMESPACE}" metrics-server
  run_test "metrics.k8s.io APIService available" \
    _test_apiservice_available v1beta1.metrics.k8s.io
  run_test "kubectl top nodes works" kubectl_cmd top nodes >/dev/null

  if [[ "${POD_NETWORKING_MODE}" == "cilium-overlay" ]]; then
    run_test "metrics-server uses hostNetwork in cilium-overlay" \
      _test_metrics_server_host_network
  fi
}

# --- KEDA ---

test_keda() {
  section "KEDA"

  if [[ "${INSTALL_KEDA}" != "true" ]]; then
    skip_test "KEDA checks" "install_keda=false"
    return 0
  fi

  run_test "KEDA namespace exists" kubectl_cmd get namespace "${KEDA_NAMESPACE}" >/dev/null
  run_test "KEDA operator deployment ready" \
    _test_deployment_ready "${KEDA_NAMESPACE}" keda-operator
  run_test "KEDA metrics-apiserver deployment ready" \
    _test_deployment_ready "${KEDA_NAMESPACE}" keda-operator-metrics-apiserver
  run_test "KEDA admission webhooks deployment ready" \
    _test_deployment_ready "${KEDA_NAMESPACE}" keda-admission-webhooks
  run_test "ScaledJob CRD present" kubectl_cmd get crd scaledjobs.keda.sh >/dev/null
  run_test "TriggerAuthentication CRD present" kubectl_cmd get crd triggerauthentications.keda.sh >/dev/null
  run_test "external.metrics.k8s.io APIService available" \
    _test_apiservice_available v1beta1.external.metrics.k8s.io

  if [[ "${POD_NETWORKING_MODE}" == "cilium-overlay" ]]; then
    run_test "KEDA metrics-apiserver uses hostNetwork in cilium-overlay" \
      _test_keda_metrics_host_network
  fi
}

_test_apiservice_available() {
  local name="$1"
  local available=""

  available="$(kubectl_cmd get apiservice "${name}" \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
  [[ "${available}" == "True" ]]
}

_test_keda_metrics_host_network() {
  local host_network=""
  host_network="$(kubectl_cmd get deployment -n "${KEDA_NAMESPACE}" keda-operator-metrics-apiserver \
    -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null || true)"
  [[ "${host_network}" == "true" ]]
}

_test_metrics_server_host_network() {
  local host_network=""
  host_network="$(kubectl_cmd get deployment -n "${METRICS_SERVER_NAMESPACE}" metrics-server \
    -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null || true)"
  [[ "${host_network}" == "true" ]]
}

# --- External Secrets Operator ---

test_eso() {
  section "External Secrets Operator"

  if [[ "${INSTALL_ESO}" != "true" ]]; then
    skip_test "ESO checks" "install_eso=false"
    return 0
  fi

  run_test "ESO namespace exists" kubectl_cmd get namespace "${ESO_NAMESPACE}" >/dev/null
  run_test "ESO controller deployment ready" \
    _test_eso_controller_ready
  run_test "ClusterSecretStore Ready" _test_cluster_secret_store_ready
  run_test "ExternalSecret CRD present" kubectl_cmd get crd externalsecrets.external-secrets.io >/dev/null

  if [[ "${ESO_WEBHOOK_ENABLED}" == "true" ]]; then
    run_test "ESO webhook deployment ready" _test_deployment_ready "${ESO_NAMESPACE}" external-secrets-webhook
  else
    skip_test "ESO webhook deployment" "eso_webhook_enabled=false"
  fi
}

_test_eso_controller_ready() {
  if _test_deployment_ready "${ESO_NAMESPACE}" external-secrets; then
    return 0
  fi
  _test_deployment_ready "${ESO_NAMESPACE}" external-secrets-controller
}

_test_cluster_secret_store_ready() {
  local ready=""
  ready="$(kubectl_cmd get clustersecretstore "${CLUSTER_SECRET_STORE_NAME}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [[ "${ready}" == "True" ]]
}

# --- BuildKit ---

test_buildkit() {
  section "BuildKit"

  if [[ "${ENABLE_BUILDKIT}" != "true" ]]; then
    skip_test "BuildKit checks" "enable_buildkitd=false"
    return 0
  fi

  run_test "BuildKit namespace exists" kubectl_cmd get namespace "${BUILDKIT_NAMESPACE}" >/dev/null
  run_test "buildkitd deployment ready" _test_buildkitd_ready
  run_test "buildkitd service exists in ${BUILDKIT_NAMESPACE}" \
    kubectl_cmd get service -n "${BUILDKIT_NAMESPACE}" buildkitd >/dev/null
  run_test "buildkit ExternalName alias exists in ${ADO_AGENTS_NAMESPACE}" \
    _test_buildkit_service_alias
  run_test "buildkit TCP reachable from ${ADO_AGENTS_NAMESPACE}" \
    _test_buildkit_connectivity
}

_test_buildkitd_ready() {
  if _test_deployment_ready "${BUILDKIT_NAMESPACE}" buildkitd; then
    return 0
  fi
  _test_deployment_ready "${BUILDKIT_NAMESPACE}" buildkitd-amd64
}

_test_buildkit_service_alias() {
  local service_type external_name expected=""
  service_type="$(kubectl_cmd get service -n "${ADO_AGENTS_NAMESPACE}" buildkit \
    -o jsonpath='{.spec.type}' 2>/dev/null || true)"
  external_name="$(kubectl_cmd get service -n "${ADO_AGENTS_NAMESPACE}" buildkit \
    -o jsonpath='{.spec.externalName}' 2>/dev/null || true)"
  expected="buildkitd.${BUILDKIT_NAMESPACE}.svc.cluster.local"
  [[ "${service_type}" == "ExternalName" && "${external_name}" == "${expected}" ]]
}

_test_buildkit_connectivity() {
  local pod_name="functional-test-buildkit-$$"
  kubectl_cmd run "${pod_name}" \
    -n "${ADO_AGENTS_NAMESPACE}" \
    --restart=Never \
    --image=public.ecr.aws/docker/library/busybox:1.36 \
    --rm -i --quiet \
    --command -- sh -c "nc -z -w 5 buildkit.${ADO_AGENTS_NAMESPACE}.svc.cluster.local 1234" \
    >/dev/null 2>&1
}

# --- ADO application layer (no job queuing) ---

test_ado_application() {
  section "ADO application layer"

  run_test "ado-agents namespace exists" kubectl_cmd get namespace "${ADO_AGENTS_NAMESPACE}" >/dev/null
  run_test "Helm release ado-agents is deployed" _test_helm_release_deployed

  if [[ "${MANAGES_ADO_PAT_SECRET}" == "true" ]]; then
    run_test "bootstrap ADO PAT secret exists" \
      kubectl_cmd get secret -n "${ADO_AGENTS_NAMESPACE}" "${ADO_SECRET_NAME}" >/dev/null
    run_test "ESO-managed ADO PAT secret synced" _test_ado_pat_eso_secret_synced
  else
    skip_test "bootstrap ADO PAT secret exists" "ado_agent_auth_mode=${ADO_AGENT_AUTH_MODE}"
    skip_test "ESO-managed ADO PAT secret synced" "ado_agent_auth_mode=${ADO_AGENT_AUTH_MODE}"
    if [[ "${ADO_AGENT_AUTH_MODE}" == "spn" ]]; then
      run_test "ESO-managed ADO SPN secret synced" _test_ado_spn_eso_secret_synced
    fi
  fi

  local scaledjob_count=""
  scaledjob_count="$(kubectl_cmd get scaledjobs -n "${ADO_AGENTS_NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  SCALEDJOB_COUNT="${scaledjob_count}"

  if [[ "${scaledjob_count}" -eq 0 ]]; then
    skip_test "ScaledJobs configured for enabled pools" "none found; verify agent_pools are enabled in env.hcl"
    skip_test "TriggerAuthentications present for ScaledJobs" "no ScaledJobs found"
  else
    run_test "ScaledJobs configured for enabled pools" _test_positive_integer "${scaledjob_count}"
    run_test "TriggerAuthentications present for ScaledJobs" _test_trigger_authentications_present
  fi

  run_test "no failed Jobs in ${ADO_AGENTS_NAMESPACE}" _test_no_failed_jobs
  run_test "ado agent service accounts use IRSA annotation" _test_ado_irsa_annotations

  if [[ "${ADO_AGENT_AUTH_MODE}" == "spn" ]]; then
    run_test "ado-keda-proxy deployment ready" \
      _test_deployment_ready "${ADO_AGENTS_NAMESPACE}" ado-keda-proxy
  else
    skip_test "ado-keda-proxy deployment" "ado_agent_auth_mode=${ADO_AGENT_AUTH_MODE}"
  fi
}

_test_positive_integer() {
  [[ "${1:-0}" -gt 0 ]]
}

_test_helm_release_deployed() {
  local helm_json status=""
  helm_json="$(helm_cmd status ado-agents -n "${ADO_AGENTS_NAMESPACE}" -o json 2>/dev/null || true)"
  status="$(json_field "${helm_json}" "data['info']['status']")"
  [[ "${status}" == "deployed" ]]
}

_test_ado_pat_eso_secret_synced() {
  local externalsecret_name="${ADO_SECRET_NAME}-secret"
  local synced=""

  if ! kubectl_cmd get externalsecret -n "${ADO_AGENTS_NAMESPACE}" "${externalsecret_name}" >/dev/null 2>&1; then
    log_verbose "ExternalSecret ${externalsecret_name} not found"
    return 1
  fi

  synced="$(kubectl_cmd get externalsecret -n "${ADO_AGENTS_NAMESPACE}" "${externalsecret_name}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [[ "${synced}" == "True" ]]
}

_test_ado_spn_eso_secret_synced() {
  local externalsecret_name="${ADO_AGENT_SPN_SECRET_NAME}-secret"
  local synced=""

  if ! kubectl_cmd get externalsecret -n "${ADO_AGENTS_NAMESPACE}" "${externalsecret_name}" >/dev/null 2>&1; then
    log_verbose "ExternalSecret ${externalsecret_name} not found"
    return 1
  fi

  synced="$(kubectl_cmd get externalsecret -n "${ADO_AGENTS_NAMESPACE}" "${externalsecret_name}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [[ "${synced}" != "True" ]] && return 1

  kubectl_cmd get secret -n "${ADO_AGENTS_NAMESPACE}" "${ADO_AGENT_SPN_SECRET_NAME}" >/dev/null
}

_test_trigger_authentications_present() {
  local ta_count=""
  ta_count="$(kubectl_cmd get triggerauthentication -n "${ADO_AGENTS_NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${ta_count}" -gt 0 ]]
}

_test_no_failed_jobs() {
  local failed=""
  failed="$(kubectl_cmd get jobs -n "${ADO_AGENTS_NAMESPACE}" -o json 2>/dev/null \
    | python3 -c 'import json, sys
items = json.load(sys.stdin).get("items", [])
failed = [job["metadata"]["name"] for job in items if (job.get("status") or {}).get("failed", 0) > 0]
print(" ".join(failed))')"
  [[ -z "${failed}" ]]
}

_test_ado_irsa_annotations() {
  local annotated_count=""
  annotated_count="$(kubectl_cmd get serviceaccount -n "${ADO_AGENTS_NAMESPACE}" -o json 2>/dev/null \
    | python3 -c 'import json, sys
items = json.load(sys.stdin).get("items", [])
print(sum(1 for item in items if item.get("metadata", {}).get("annotations", {}).get("eks.amazonaws.com/role-arn")))' )"
  [[ "${annotated_count}" -gt 0 ]]
}

# --- optional platform add-ons ---

test_cluster_autoscaler() {
  section "Cluster autoscaler"

  if [[ "${ENABLE_CLUSTER_AUTOSCALER}" != "true" ]]; then
    skip_test "cluster-autoscaler deployment" "enable_cluster_autoscaler=false"
    return 0
  fi

  run_test "cluster-autoscaler deployment ready" \
    _test_deployment_ready "${CLUSTER_AUTOSCALER_NAMESPACE}" cluster-autoscaler
}

test_node_auto_heal() {
  section "Node auto-heal"

  if [[ "${ENABLE_NODE_AUTO_HEAL}" != "true" ]]; then
    skip_test "node-auto-heal deployment" "enable_node_auto_heal=false"
    return 0
  fi

  run_test "aws-node-termination-handler deployment ready" \
    _test_deployment_ready "${NODE_AUTO_HEAL_NAMESPACE}" aws-node-termination-handler
}

# --- cross-component interaction smoke ---

test_cross_component() {
  section "Cross-component interactions"

  if [[ "${INSTALL_KEDA}" == "true" && "${INSTALL_ESO}" == "true" ]]; then
    if [[ "${SCALEDJOB_COUNT}" -gt 0 ]]; then
      run_test "ScaledJobs reference TriggerAuthentication in ${ADO_AGENTS_NAMESPACE}" \
        _test_scaledjobs_reference_triggerauth
    else
      skip_test "ScaledJob TriggerAuthentication wiring" "no ScaledJobs found"
    fi
  else
    skip_test "ScaledJob TriggerAuthentication wiring" "KEDA or ESO disabled in env.hcl"
  fi

  if [[ "${ENABLE_BUILDKIT}" == "true" ]]; then
    run_test "BuildKit alias resolves to backend service" \
      _test_buildkit_alias_resolves
  else
    skip_test "BuildKit service alias wiring" "enable_buildkitd=false"
  fi
}

_test_scaledjobs_reference_triggerauth() {
  local invalid=""
  invalid="$(kubectl_cmd get scaledjobs -n "${ADO_AGENTS_NAMESPACE}" -o json 2>/dev/null \
    | python3 -c 'import json, subprocess, sys
items = json.load(sys.stdin).get("items", [])
missing = []
for item in items:
    refs = (item.get("spec") or {}).get("triggers") or []
    for trigger in refs:
        name = ((trigger.get("authenticationRef") or {}).get("name") or "").strip()
        if not name:
            continue
        proc = subprocess.run(
            ["kubectl", "get", "triggerauthentication", "-n", sys.argv[1], name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if proc.returncode != 0:
            missing.append(name)
print(" ".join(sorted(set(missing))))' "${ADO_AGENTS_NAMESPACE}")"
  [[ -z "${invalid}" ]]
}

_test_buildkit_alias_resolves() {
  local pod_name="functional-test-buildkit-alias-$$"
  kubectl_cmd run "${pod_name}" \
    -n "${ADO_AGENTS_NAMESPACE}" \
    --restart=Never \
    --image=public.ecr.aws/docker/library/busybox:1.36 \
    --rm -i --quiet \
    --command -- sh -c "nslookup buildkit.${ADO_AGENTS_NAMESPACE}.svc.cluster.local >/dev/null" \
    >/dev/null 2>&1
}

# --- main ---

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-file)
        ENV_FILE="$2"
        shift 2
        ;;
      --skip-kubeconfig)
        CONFIGURE_KUBECONFIG=false
        shift
        ;;
      --verbose|-v)
        VERBOSE=true
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if ! load_env_hcl_config "${ENV_FILE}"; then
    exit 2
  fi

  log "Functional cluster tests"
  log "  env file:      ${ENV_FILE}"
  log "  cluster:       ${CLUSTER_NAME}"
  log "  region:        ${AWS_REGION}"
  log "  CNI mode:      ${POD_NETWORKING_MODE}"
  log "  ado namespace: ${ADO_AGENTS_NAMESPACE}"

  test_prerequisites || exit 2
  configure_kubeconfig

  test_networking
  test_metrics_server
  test_keda
  test_eso
  test_buildkit
  test_ado_application
  test_cluster_autoscaler
  test_node_auto_heal
  test_cross_component

  log ""
  log "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped"

  if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    log ""
    log "One or more checks failed. Re-run with --verbose for kubectl/helm details."
    exit 1
  fi

  log ""
  log "All executed checks passed."
  exit 0
}

main "$@"
