#!/usr/bin/env bash

# =============================================================================
# EKS ADO Agents Infrastructure Deployment Script (Terragrunt)
# =============================================================================
#
# This script orchestrates the deployment of a three-layer infrastructure
# stack for Azure DevOps (ADO) agents running on Amazon EKS using Terragrunt.
#
# Layers:
# 1. Base Layer: Core EKS cluster, networking, IAM, KMS
# 2. Middleware Layer: KEDA, External Secrets Operator, buildkitd
# 3. Application Layer: ECR repositories, secrets, ADO agent deployments
#
# Features:
# - Terragrunt-based configuration management
# - Automated dependency resolution
# - Single source of truth (env.hcl)
# - Layer-by-layer deployment with health checks
# - Comprehensive error handling
# - Interactive mode for production deployments
# - Dry-run mode for validation
#
# Usage:
#   ./deploy.sh [OPTIONS] [COMMAND]
#
# Commands:
#   deploy        Deploy all layers (default)
#   plan          Show deployment plan for all layers
#   validate      Validate configurations without deploying
#   destroy       Destroy all layers in reverse order
#   status        Show status of all layers
#
# Options:
#   --layer LAYER          Deploy specific layer only (base|middleware|application|config)
#   --auto-approve         Skip interactive prompts (non-interactive mode)
#   --dry-run             Show what would be done without making changes
#   --region REGION       AWS region (overrides env.hcl)
#   --update-ado-secret   Prompt for and inject ADO credentials before application layer
#                         (prevents KEDA authentication errors on initial deployment)
#   --help                Show this help message
#   --verbose             Enable verbose output

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LAYERS_DIR="${SCRIPT_DIR}"
readonly SCRIPT_NAME="${0##*/}"

readonly BASE_LAYER_DIR="${LAYERS_DIR}/base"
readonly MIDDLEWARE_LAYER_DIR="${LAYERS_DIR}/middleware"
readonly APPLICATION_LAYER_DIR="${LAYERS_DIR}/application"

# Default configuration
DEFAULT_COMMAND="deploy"
AUTO_APPROVE=true  # Default to auto-approve for non-interactive deployments
DRY_RUN=false
VERBOSE=false
TARGET_LAYER=""
AWS_REGION_OVERRIDE=""
UPDATE_ADO_SECRET=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" >&2
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
    fi
}

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS] [COMMAND]

Commands:
  deploy        Deploy all layers in order (default)
  init          Initialize Terragrunt/Terraform (download modules)
  plan          Show deployment plan for all layers
  validate      Validate configurations
  destroy       Destroy all layers in reverse order
  status        Show status of all layers
  
Options:
  --layer LAYER          Deploy specific layer only (base|middleware|application|config)
  --auto-approve         Skip interactive prompts
  --dry-run             Show what would be done without making changes
  --region REGION       Override AWS region from env.hcl
  --update-ado-secret   Prompt for and inject ADO credentials before application layer
                        (prevents KEDA authentication errors on initial deployment)
  --help                Show this help message
  --verbose             Enable verbose output

Environment Variables:
  TF_STATE_BUCKET     S3 bucket for Terraform state (required)
  TF_STATE_REGION     Region for state bucket (optional, uses AWS_REGION)
  TF_VAR_ado_pat_value    ADO Personal Access Token (required for application layer)
  AWS_REGION          AWS region (optional, can be set in env.hcl)
  AWS_PROFILE         AWS profile to use (optional)

Examples:
  # Initialize all layers (download external modules)
  ./${SCRIPT_NAME} init

  # Initialize specific layer
  ./${SCRIPT_NAME} init --layer base

  # Deploy all layers (recommended for initial deployment)
  ./${SCRIPT_NAME} deploy --update-ado-secret

  # Deploy only base layer
  ./${SCRIPT_NAME} deploy --layer base

  # Show plan for all layers
  ./${SCRIPT_NAME} plan

  # Deploy application layer with credentials (prevents KEDA errors)
  ./${SCRIPT_NAME} deploy --layer application --update-ado-secret

  # Deploy config layer (post-deployment)
  ./${SCRIPT_NAME} deploy --layer config

  # Update ADO credentials after initial deployment
  ./${SCRIPT_NAME} deploy --layer config --update-ado-secret

  # Destroy all layers
  ./${SCRIPT_NAME} destroy

  # Deploy with auto-approve (CI/CD)
  ./${SCRIPT_NAME} deploy --auto-approve --update-ado-secret

EOF
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        log_info "Auto-approved: ${message}"
        return 0
    fi
    
    local prompt="${message} (y/N): "
    if [[ "${default}" == "y" ]]; then
        prompt="${message} (Y/n): "
    fi
    
    while true; do
        echo -ne "${YELLOW}${prompt}${NC}"
        read -r response
        
        case "${response}" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            "") 
                if [[ "${default}" == "y" ]]; then
                    return 0
                else
                    return 1
                fi
                ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# =============================================================================
# Prerequisites Checking
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    for tool in aws terragrunt terraform helm kubectl jq; do
        if ! command -v "${tool}" &> /dev/null; then
            missing_tools+=("${tool}")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        log_info "Install Terragrunt: https://terragrunt.gruntwork.io/docs/getting-started/install/"
        exit 1
    fi
    
    # Check Terragrunt version
    local tg_version
    tg_version=$(terragrunt --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d 'v')
    log_debug "Terragrunt version: ${tg_version}"
    
    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
    log_debug "Terraform version: ${tf_version}"
    
    # Skip live AWS identity checks in dry-run mode to allow offline validation.
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry-run mode detected: skipping AWS credentials validation"
    else
        if ! aws sts get-caller-identity &> /dev/null; then
            log_error "AWS credentials not configured or invalid"
            log_error "Run 'aws configure' to set up credentials"
            exit 1
        fi

        local caller_identity
        caller_identity=$(aws sts get-caller-identity --output json)
        log_debug "AWS Identity: $(echo "${caller_identity}" | jq -r '.Arn')"
    fi
    
    # Check for TF_STATE_BUCKET environment variable
    if [[ -z "${TF_STATE_BUCKET:-}" ]]; then
        log_error "TF_STATE_BUCKET environment variable is not set"
        log_error "Export TF_STATE_BUCKET with your S3 bucket name:"
        log_error "  export TF_STATE_BUCKET='my-terraform-state-bucket'"
        exit 1
    fi
    
    # Check if env.hcl exists
    if [[ ! -f "${LAYERS_DIR}/env.hcl" ]]; then
        log_error "Configuration file not found: ${LAYERS_DIR}/env.hcl"
        log_error "Please copy env.sample.hcl to env.hcl and configure:"
        log_error "  cp ${LAYERS_DIR}/env.sample.hcl ${LAYERS_DIR}/env.hcl"
        log_error "  vim ${LAYERS_DIR}/env.hcl"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
    log_info "Using S3 state bucket: ${TF_STATE_BUCKET}"
}

# =============================================================================
# Layer Management Functions
# =============================================================================

get_layer_dir() {
    local layer="$1"
    
    case "${layer}" in
        base)        echo "${BASE_LAYER_DIR}" ;;
        middleware)  echo "${MIDDLEWARE_LAYER_DIR}" ;;
        application) echo "${APPLICATION_LAYER_DIR}" ;;
        config)      echo "${BASE_LAYER_DIR}" ;;  # Config uses base dir for outputs
        *)
            log_error "Unknown layer: ${layer}. Valid layers: base, middleware, application, config"
            return 1
            ;;
    esac
}

validate_target_layer() {
    if [[ -z "${TARGET_LAYER}" ]]; then
        return 0
    fi

    case "${TARGET_LAYER}" in
        base|middleware|application|config) return 0 ;;
        *)
            log_error "Invalid --layer value: ${TARGET_LAYER}"
            log_error "Valid values: base, middleware, application, config"
            return 1
            ;;
    esac
}

get_terragrunt_output_raw() {
    local layer="$1"
    local output_name="$2"
    local layer_dir
    layer_dir=$(get_layer_dir "${layer}")

    (cd "${layer_dir}" && terragrunt output -raw "${output_name}" 2>/dev/null)
}

get_terragrunt_output_json() {
    local layer="$1"
    local output_name="$2"
    local layer_dir
    layer_dir=$(get_layer_dir "${layer}")

    (cd "${layer_dir}" && terragrunt output -json "${output_name}" 2>/dev/null)
}

init_layer() {
    local layer="$1"
    local layer_dir="$2"
    local force="${3:-false}"
    
    log_info "Initializing ${layer} layer..."
    
    cd "${layer_dir}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize ${layer} layer"
        return 0
    fi
    
    # Check if initialization is needed
    local needs_init=false
    
    if [[ "${force}" == "true" ]]; then
        log_debug "Force initialization requested"
        needs_init=true
    elif [[ ! -d "${layer_dir}/.terragrunt-cache" ]]; then
        log_debug "Terragrunt cache not found - initialization needed"
        needs_init=true
    elif [[ ! -d "${layer_dir}/.terraform" ]]; then
        log_debug "Terraform directory not found - initialization needed"
        needs_init=true
    else
        # Check if .terraform/modules exists and has content (for external modules)
        if [[ -d "${layer_dir}/.terraform/modules" ]]; then
            local module_count
            module_count=$(find "${layer_dir}/.terraform/modules" -type f -name "*.tf" 2>/dev/null | wc -l | tr -d ' ')
            if [[ "${module_count}" -eq 0 ]]; then
                log_debug "Terraform modules directory is empty - initialization needed"
                needs_init=true
            fi
        fi
        
        # Check if .terragrunt-cache contains proper Terraform modules
        if [[ -d "${layer_dir}/.terragrunt-cache" ]]; then
            # Look for module manifests in terragrunt cache
            local cache_modules
            cache_modules=$(find "${layer_dir}/.terragrunt-cache" -type f -name "modules.json" 2>/dev/null | wc -l | tr -d ' ')
            if [[ "${cache_modules}" -eq 0 ]]; then
                log_debug "Terragrunt cache exists but no module manifests found - initialization needed"
                needs_init=true
            fi
        fi
    fi
    
    if [[ "${needs_init}" == "false" ]]; then
        log_info "Layer ${layer} already initialized, skipping init"
        return 0
    fi
    
    log_info "Running terragrunt init for ${layer} layer..."
    
    local init_args=("--non-interactive")
    if [[ "${VERBOSE}" == "true" ]]; then
        init_args+=("--terragrunt-log-level" "debug")
    fi
    
    # Run terragrunt init with upgrade to ensure latest module versions
    if ! terragrunt init -upgrade "${init_args[@]}"; then
        log_error "Initialization failed for ${layer} layer"
        return 1
    fi
    
    log_success "Initialization completed for ${layer} layer"
    return 0
}

validate_layer() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Validating ${layer} layer..."
    
    if [[ ! -d "${layer_dir}" ]]; then
        log_error "Layer directory not found: ${layer_dir}"
        return 1
    fi
    
    if [[ ! -f "${layer_dir}/terragrunt.hcl" ]]; then
        log_error "terragrunt.hcl not found in ${layer} layer"
        return 1
    fi
    
    cd "${layer_dir}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would validate ${layer} layer"
        return 0
    fi
    
    if ! terragrunt validate --non-interactive; then
        log_error "Validation failed for ${layer} layer"
        return 1
    fi
    
    log_success "Validation passed for ${layer} layer"
    return 0
}

plan_layer() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Planning ${layer} layer..."
    
    cd "${layer_dir}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would plan ${layer} layer"
        return 0
    fi
    
    # Ensure layer is initialized before planning
    if ! init_layer "${layer}" "${layer_dir}"; then
        log_error "Failed to initialize ${layer} layer before planning"
        return 1
    fi
    
    local plan_args=()
    if [[ "${VERBOSE}" == "true" ]]; then
        plan_args+=("--terragrunt-log-level" "debug")
    fi
    
    if ! terragrunt plan --non-interactive "${plan_args[@]}"; then
        log_error "Plan failed for ${layer} layer"
        return 1
    fi
    
    log_success "Plan completed for ${layer} layer"
    return 0
}

apply_layer() {
    local layer="$1"
    local layer_dir="$2"
    
    log "Applying ${layer} layer..."
    
    cd "${layer_dir}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would apply ${layer} layer"
        return 0
    fi
    
    # Ensure layer is initialized before applying
    if ! init_layer "${layer}" "${layer_dir}"; then
        log_error "Failed to initialize ${layer} layer before applying"
        return 1
    fi
    
    local apply_args=()
    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        apply_args+=("--non-interactive")
    fi
    if [[ "${VERBOSE}" == "true" ]]; then
        apply_args+=("--terragrunt-log-level" "debug")
    fi
    
    if ! terragrunt apply "${apply_args[@]}"; then
        log_error "Apply failed for ${layer} layer"
        return 1
    fi
    
    log_success "Apply completed for ${layer} layer"
    return 0
}

destroy_layer() {
    local layer="$1"
    local layer_dir="$2"
    
    log "Destroying ${layer} layer..."
    
    cd "${layer_dir}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would destroy ${layer} layer"
        return 0
    fi
    
    local destroy_args=()
    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        destroy_args+=("--non-interactive")
    fi
    if [[ "${VERBOSE}" == "true" ]]; then
        destroy_args+=("--terragrunt-log-level" "debug")
    fi
    
    if ! terragrunt destroy "${destroy_args[@]}"; then
        log_error "Destroy failed for ${layer} layer"
        return 1
    fi
    
    log_success "Destroy completed for ${layer} layer"
    return 0
}

show_layer_status() {
    local layer="$1"
    local layer_dir="$2"
    
    cd "${layer_dir}"
    
    log_info "Status for ${layer} layer:"
    
    if [[ -d "${layer_dir}/.terragrunt-cache" ]]; then
        echo "  ✅ Terragrunt cache exists"
    else
        echo "  ❌ Terragrunt cache not found (not initialized)"
    fi
    
    # Check for state file
    if terragrunt state list --non-interactive &>/dev/null; then
        local resource_count
        resource_count=$(terragrunt state list --non-interactive 2>/dev/null | wc -l)
        echo "  ✅ State file exists (${resource_count} resources)"
    else
        echo "  ❌ No state file found (not deployed)"
    fi
}

# =============================================================================
# High-Level Operations
# =============================================================================

deploy_all_layers() {
    log "Starting deployment of all layers..."
    
    # If updating ADO secret, prompt for credentials BEFORE application layer
    if [[ "${UPDATE_ADO_SECRET}" == "true" ]]; then
        log_info "ADO secret update requested - collecting credentials before deployment..."
        
        # Check if ADO_PAT is set (safe for unbound variables)
        if [[ -z "${ADO_PAT:-}" ]]; then
            log_info "ADO_PAT not set - prompting for credentials..."
            if ! prompt_for_ado_credentials; then
                log_error "Failed to get ADO credentials"
                return 1
            fi
        else
            log_info "Using existing ADO_PAT from environment"
        fi
        
        log_success "ADO credentials collected and will be injected after application layer deploys"
    fi
    
    local layers=("base" "middleware" "application")
    
    for layer in "${layers[@]}"; do
        local layer_dir
        layer_dir=$(get_layer_dir "${layer}")
        
        if [[ "${DRY_RUN}" != "true" && "${AUTO_APPROVE}" != "true" ]]; then
            echo
            if ! confirm_action "Deploy ${layer} layer?"; then
                log_info "Skipping ${layer} layer"
                continue
            fi
        fi
        
        if ! apply_layer "${layer}" "${layer_dir}"; then
            log_error "Deployment failed at ${layer} layer"
            return 1
        fi
        
        # Special handling for base layer - configure kubectl
        if [[ "${layer}" == "base" && "${DRY_RUN}" != "true" ]]; then
            configure_kubectl "${layer_dir}"
        fi
    done
    
    log_success "All layers deployed successfully!"
    return 0
}

init_all_layers() {
    log "Initializing all layers..."
    
    local layers=("base" "middleware" "application")
    
    for layer in "${layers[@]}"; do
        local layer_dir
        layer_dir=$(get_layer_dir "${layer}")
        
        if ! init_layer "${layer}" "${layer_dir}" "true"; then
            log_error "Initialization failed for ${layer} layer"
            return 1
        fi
        echo
    done
    
    log_success "All layers initialized successfully"
    return 0
}

plan_all_layers() {
    log "Planning all layers..."
    
    local layers=("base" "middleware" "application")
    
    for layer in "${layers[@]}"; do
        local layer_dir
        layer_dir=$(get_layer_dir "${layer}")
        
        if ! plan_layer "${layer}" "${layer_dir}"; then
            log_error "Plan failed for ${layer} layer"
            return 1
        fi
        echo
    done
    
    log_success "Plan completed for all layers"
    return 0
}

validate_all_layers() {
    log "Validating all layers..."
    
    local layers=("base" "middleware" "application")
    
    for layer in "${layers[@]}"; do
        local layer_dir
        layer_dir=$(get_layer_dir "${layer}")
        
        if ! validate_layer "${layer}" "${layer_dir}"; then
            log_error "Validation failed for ${layer} layer"
            return 1
        fi
    done
    
    log_success "All layers validated successfully"
    return 0
}

destroy_all_layers() {
    log_warning "This will destroy ALL infrastructure layers!"
    
    if [[ "${AUTO_APPROVE}" != "true" ]]; then
        echo
        if ! confirm_action "Are you absolutely sure you want to destroy everything?"; then
            log_info "Destroy cancelled"
            return 0
        fi
    fi
    
    # Destroy in reverse order
    local layers=("application" "middleware" "base")
    
    for layer in "${layers[@]}"; do
        local layer_dir
        layer_dir=$(get_layer_dir "${layer}")
        
        if ! destroy_layer "${layer}" "${layer_dir}"; then
            log_error "Destroy failed at ${layer} layer"
            return 1
        fi
    done
    
    log_success "All layers destroyed"
    return 0
}

show_all_status() {
    log_info "Infrastructure Status:"
    echo
    
    local layers=("base" "middleware" "application")
    
    for layer in "${layers[@]}"; do
        local layer_dir
        layer_dir=$(get_layer_dir "${layer}")
        show_layer_status "${layer}" "${layer_dir}"
        echo
    done
}

configure_kubectl() {
    local base_dir="$1"
    
    log_info "Configuring kubectl access..."
    
    cd "${base_dir}"
    
    local cluster_name
    cluster_name=$(terragrunt output -raw cluster_name 2>/dev/null || echo "")
    
    if [[ -z "${cluster_name}" ]]; then
        log_warning "Could not retrieve cluster name from outputs"
        return 0
    fi
    
    local region="${AWS_REGION_OVERRIDE:-}"
    if [[ -z "${region}" ]]; then
        region=$(aws configure get region 2>/dev/null || echo "us-west-2")
    fi
    
    if aws eks update-kubeconfig --region "${region}" --name "${cluster_name}" --alias "${cluster_name}" 2>/dev/null; then
        log_success "kubectl configured for cluster: ${cluster_name}"
    else
        log_warning "Failed to configure kubectl automatically"
        log_info "Configure manually with: aws eks update-kubeconfig --region ${region} --name ${cluster_name}"
    fi
}

# =============================================================================
# Config Layer Functions (Post-Deployment)
# =============================================================================

prompt_for_ado_credentials() {
    log ""
    log "Azure DevOps Credentials Required"
    log "=================================="
    log ""
    log "To update the ADO PAT secret, provide credentials via environment variables or prompts."
    log "The secret will be synced to Kubernetes via External Secrets Operator."
    log ""
    
    # Check for ADO_PAT environment variable first, then prompt
    if [[ -z "${ADO_PAT:-}" ]]; then
        log_info "ADO_PAT environment variable not set"
        read -rsp "Enter Azure DevOps PAT Token: " ADO_PAT
        echo ""
    else
        log_info "Using ADO_PAT from environment variable"
    fi
    
    # Check for ADO_ORG_URL environment variable first, then prompt
    if [[ -z "${ADO_ORG_URL:-}" ]]; then
        log_info "ADO_ORG_URL environment variable not set"
        read -rp "Enter Azure DevOps Organization URL (e.g., https://dev.azure.com/myorg): " ADO_ORG_URL
    else
        log_info "Using ADO_ORG_URL from environment variable"
    fi
    
    if [[ -z "${ADO_ORG_URL}" || -z "${ADO_PAT}" ]]; then
        log_error "Organization URL and PAT token are required"
        log_error "Set via environment variables: ADO_PAT and ADO_ORG_URL"
        return 1
    fi
    
    export ADO_ORG_URL
    export ADO_PAT
    log_success "Credentials received"
    return 0
}

inject_ado_secret() {
    local cluster_name="$1"
    local region="$2"
    
    log_info "Updating ADO PAT in AWS Secrets Manager..."
    
    if [[ -z "${ADO_PAT:-}" ]]; then
        log_error "ADO_PAT not set. Run with credential prompting first."
        return 1
    fi
    
    if [[ -z "${ADO_ORG_URL:-}" ]]; then
        log_error "ADO_ORG_URL not set. Run with credential prompting first."
        return 1
    fi
    
    # Get the secret name from application layer Terragrunt output
    log_debug "Retrieving secret name from application layer outputs..."
    local secret_name
    secret_name=$(cd "${APPLICATION_LAYER_DIR}" && terragrunt output -json ado_pat_secret 2>/dev/null | jq -r '.name' 2>/dev/null || echo "")
    
    # Fallback to default if output not available
    if [[ -z "${secret_name}" ]]; then
        log_warning "Could not retrieve secret name from Terraform output, using default"
        secret_name="ado-agent-pat"
    fi
    
    log_debug "Using secret name: ${secret_name}"
    
    # Extract organization name from URL (remove https://dev.azure.com/ prefix and trailing slash)
    local org_name
    org_name=$(echo "${ADO_ORG_URL}" | sed 's|https://dev.azure.com/||' | sed 's|/$||')
    
    # Check if secret exists
    if aws secretsmanager describe-secret --secret-id "${secret_name}" --region "${region}" &>/dev/null; then
        log_info "Updating existing secret: ${secret_name}"
        log_info "  Organization: ${org_name}"
        log_info "  URL: ${ADO_ORG_URL}"
        
        # Create JSON structure matching Terraform expectations without shell interpolation risks.
        local secret_json
        secret_json=$(jq -nc \
            --arg pat "${ADO_PAT}" \
            --arg org "${org_name}" \
            --arg url "${ADO_ORG_URL}" \
            '{personalAccessToken: $pat, organization: $org, adourl: $url}')
        
        if aws secretsmanager put-secret-value \
            --secret-id "${secret_name}" \
            --secret-string "${secret_json}" \
            --region "${region}" >/dev/null; then
            log_success "ADO PAT updated in AWS Secrets Manager: ${secret_name}"
            return 0
        else
            log_error "Failed to update ADO PAT in AWS Secrets Manager"
            return 1
        fi
    else
        log_error "Secret ${secret_name} does not exist. It should be created by the application layer."
        log_info "Deploy the application layer first, then run with --update-ado-secret flag."
        return 1
    fi
}

create_cluster_secret_store() {
    local cluster_name="$1"
    local region="$2"
    local eso_role_arn="$3"
    local secret_store_name="${4:-aws-secrets-manager}"
    local eso_sa_name="${5:-external-secrets}"
    local eso_namespace="${6:-external-secrets-system}"
    
    log_info "Creating ClusterSecretStore for External Secrets Operator..."
    log_debug "Cluster: ${cluster_name}"
    log_debug "Region: ${region}"
    log_debug "ESO role ARN: ${eso_role_arn}"
    log_debug "ClusterSecretStore: ${secret_store_name}"
    log_debug "ESO service account: ${eso_namespace}/${eso_sa_name}"
    
    # Validate kubectl access
    if ! kubectl get nodes &>/dev/null; then
        log_error "Cannot access Kubernetes cluster. Configure kubectl first."
        return 1
    fi
    
    # Check if External Secrets Operator is installed
    if ! kubectl get crd clustersecretstores.external-secrets.io &>/dev/null; then
        log_error "External Secrets Operator CRD not found. Deploy middleware layer first."
        return 1
    fi
    
    log_info "Applying ClusterSecretStore manifest..."
    
    if ! kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: ${secret_store_name}
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${region}
      auth:
        jwt:
          serviceAccountRef:
            name: ${eso_sa_name}
            namespace: ${eso_namespace}
EOF
    then
        log_error "Failed to create ClusterSecretStore"
        return 1
    fi
    
    log_success "ClusterSecretStore manifest applied"
    
    # Wait for ClusterSecretStore to become ready
    log_info "Waiting for ClusterSecretStore to become ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local status
        status=$(kubectl get clustersecretstore "${secret_store_name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [[ "${status}" == "True" ]]; then
            log_success "ClusterSecretStore is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [[ ${attempt} -lt ${max_attempts} ]]; then
            echo -n "."
            sleep 2
        fi
    done
    
    echo
    log_warning "ClusterSecretStore status check timed out after ${max_attempts} attempts"
    log_info "Check status with: kubectl get clustersecretstore ${secret_store_name} -o yaml"
    return 1
}

deploy_config_layer() {
    local base_dir="$1"
    local update_ado_secret="${2:-false}"
    
    log ""
    log "=========================================="
    log "Config Layer Deployment (Post-Deployment Configuration)"
    log "=========================================="
    log ""
    
    # Verify required Terraform outputs before making cluster-side changes.
    log_info "Verifying prerequisite layer outputs..."

    local cluster_name
    cluster_name=$(get_terragrunt_output_raw "base" "cluster_name" || true)
    if [[ -z "${cluster_name}" ]]; then
        log_error "Base layer output missing: cluster_name"
        log_error "Deploy base layer first: ./${SCRIPT_NAME} deploy --layer base"
        return 1
    fi

    local eso_role_arn
    eso_role_arn=$(get_terragrunt_output_raw "middleware" "eso_role_arn" || true)
    if [[ -z "${eso_role_arn}" ]]; then
        log_error "Middleware layer output missing: eso_role_arn"
        log_error "Deploy middleware layer first: ./${SCRIPT_NAME} deploy --layer middleware"
        return 1
    fi

    local cluster_secret_store_name
    cluster_secret_store_name=$(get_terragrunt_output_raw "middleware" "cluster_secret_store_name" || true)
    if [[ -z "${cluster_secret_store_name}" ]]; then
        log_error "Middleware layer output missing: cluster_secret_store_name"
        log_error "Deploy middleware layer first: ./${SCRIPT_NAME} deploy --layer middleware"
        return 1
    fi

    local eso_namespace
    eso_namespace=$(get_terragrunt_output_raw "middleware" "eso_namespace" || true)
    if [[ -z "${eso_namespace}" ]]; then
        log_error "Middleware layer output missing: eso_namespace"
        log_error "Deploy middleware layer first: ./${SCRIPT_NAME} deploy --layer middleware"
        return 1
    fi

    local eso_service_account_name
    eso_service_account_name=$(get_terragrunt_output_raw "middleware" "eso_service_account_name" || true)
    if [[ -z "${eso_service_account_name}" ]]; then
        log_error "Middleware layer output missing: eso_service_account_name"
        log_error "Deploy middleware layer first: ./${SCRIPT_NAME} deploy --layer middleware"
        return 1
    fi

    if [[ "${update_ado_secret}" == "true" ]]; then
        local application_secret_json
        application_secret_json=$(get_terragrunt_output_json "application" "ado_pat_secret" || true)
        local application_secret_name
        application_secret_name=$(echo "${application_secret_json}" | jq -r '.name // empty' 2>/dev/null || true)

        if [[ -z "${application_secret_name}" ]]; then
            log_error "Application layer output missing: ado_pat_secret.name"
            log_error "Deploy application layer first: ./${SCRIPT_NAME} deploy --layer application"
            return 1
        fi
    fi

    log_success "Prerequisite outputs verified"
    
    # Configure kubectl
    configure_kubectl "${base_dir}"
    
    local region="${AWS_REGION_OVERRIDE:-}"
    if [[ -z "${region}" ]]; then
        region=$(aws configure get region 2>/dev/null || echo "us-west-2")
    fi

    # Create ClusterSecretStore
    if ! create_cluster_secret_store \
        "${cluster_name}" \
        "${region}" \
        "${eso_role_arn}" \
        "${cluster_secret_store_name}" \
        "${eso_service_account_name}" \
        "${eso_namespace}"
    then
        log_error "Failed to create ClusterSecretStore"
        return 1
    fi
    
    # Update ADO secret if requested
    if [[ "${update_ado_secret}" == "true" ]]; then
        log_info "ADO secret update requested..."
        
        # Check if ADO_PAT is set (safe for unbound variables)
        if [[ -z "${ADO_PAT:-}" ]]; then
            log_info "ADO_PAT not set - prompting for credentials..."
            if ! prompt_for_ado_credentials; then
                log_error "Failed to get ADO credentials"
                return 1
            fi
        else
            log_info "Using existing ADO_PAT from environment"
        fi
        
        if ! inject_ado_secret "${cluster_name}" "${region}"; then
            log_error "Failed to inject ADO secret"
            return 1
        fi
    else
        log_info "Skipping ADO secret update (use --update-ado-secret to enable)"
    fi
    
    log_success "Config layer deployment completed successfully"
    
    # Display useful information
    echo
    log_info "=== Post-Deployment Information ==="
    log_info "Cluster: ${cluster_name}"
    log_info "Region: ${region}"
    log_info ""
    log_info "Verify ClusterSecretStore:"
    log_info "  kubectl get clustersecretstore ${cluster_secret_store_name}"
    log_info ""
    log_info "Check External Secrets:"
    log_info "  kubectl get externalsecrets -A"
    log_info ""
    log_info "To update ADO PAT later:"
    log_info "  ./${SCRIPT_NAME} deploy --layer config --update-ado-secret"
    echo
    
    return 0
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local command="${DEFAULT_COMMAND}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            deploy|init|plan|validate|destroy|status)
                command="$1"
                shift
                ;;
            --layer)
                if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
                    log_error "Option --layer requires a value (base|middleware|application|config)"
                    show_usage
                    exit 1
                fi
                TARGET_LAYER="$2"
                shift 2
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --region)
                if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
                    log_error "Option --region requires a value (e.g., us-west-2)"
                    show_usage
                    exit 1
                fi
                AWS_REGION_OVERRIDE="$2"
                shift 2
                ;;
            --update-ado-secret)
                UPDATE_ADO_SECRET=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if ! validate_target_layer; then
        show_usage
        exit 1
    fi
    
    # Display configuration
    log_info "Configuration:"
    log_debug "  Command: ${command}"
    log_debug "  Target Layer: ${TARGET_LAYER:-all}"
    log_debug "  Auto Approve: ${AUTO_APPROVE}"
    log_debug "  Dry Run: ${DRY_RUN}"
    log_debug "  Verbose: ${VERBOSE}"
    echo
    
    # Check prerequisites
    check_prerequisites
    echo
    
    # Execute command
    case "${command}" in
        deploy)
            if [[ -n "${TARGET_LAYER}" ]]; then
                # Special handling for config layer
                if [[ "${TARGET_LAYER}" == "config" ]]; then
                    deploy_config_layer "${BASE_LAYER_DIR}" "${UPDATE_ADO_SECRET}"
                else
                    # If deploying application layer with ADO secret update, prompt first
                    if [[ "${TARGET_LAYER}" == "application" && "${UPDATE_ADO_SECRET}" == "true" ]]; then
                        log_info "ADO secret update requested for application layer - collecting credentials first..."
                        
                        # Check if ADO_PAT is set (safe for unbound variables)
                        if [[ -z "${ADO_PAT:-}" ]]; then
                            log_info "ADO_PAT not set - prompting for credentials..."
                            if ! prompt_for_ado_credentials; then
                                log_error "Failed to get ADO credentials"
                                exit 1
                            fi
                        else
                            log_info "Using existing ADO_PAT from environment"
                        fi
                        
                        log_success "ADO credentials collected and will be injected after deployment"
                    fi
                    
                    local layer_dir
                    layer_dir=$(get_layer_dir "${TARGET_LAYER}")
                    apply_layer "${TARGET_LAYER}" "${layer_dir}"
                    
                    # If application layer with ADO secret update, inject the secret immediately
                    if [[ "${TARGET_LAYER}" == "application" && "${UPDATE_ADO_SECRET}" == "true" ]]; then
                        log_info "Injecting ADO secret after application layer deployment..."
                        
                        # Get cluster info from base layer
                        cd "${BASE_LAYER_DIR}"
                        local cluster_name region
                        cluster_name=$(terragrunt output -raw cluster_name 2>/dev/null || echo "")
                        region="${AWS_REGION_OVERRIDE:-}"
                        if [[ -z "${region}" ]]; then
                            region=$(aws configure get region 2>/dev/null || echo "us-west-2")
                        fi
                        
                        if [[ -z "${cluster_name}" ]]; then
                            log_error "Could not retrieve cluster name from base layer"
                            exit 1
                        fi
                        
                        if ! inject_ado_secret "${cluster_name}" "${region}"; then
                            log_error "Failed to inject ADO secret"
                            exit 1
                        fi
                        
                        log_success "ADO secret injected successfully"
                        log_info "You may need to restart KEDA operator: kubectl rollout restart deployment -n keda-system keda-operator"
                    fi
                fi
            else
                deploy_all_layers
                # Optionally deploy config layer after all Terraform layers
                if confirm_action "Deploy config layer (ClusterSecretStore + kubectl setup)?" "y"; then
                    deploy_config_layer "${BASE_LAYER_DIR}" "${UPDATE_ADO_SECRET}"
                fi
            fi
            ;;
        plan)
            if [[ -n "${TARGET_LAYER}" ]]; then
                if [[ "${TARGET_LAYER}" == "config" ]]; then
                    log_info "Config layer is kubectl-based and does not support plan operation"
                    exit 0
                fi
                local layer_dir
                layer_dir=$(get_layer_dir "${TARGET_LAYER}")
                plan_layer "${TARGET_LAYER}" "${layer_dir}"
            else
                plan_all_layers
            fi
            ;;
        validate)
            if [[ -n "${TARGET_LAYER}" ]]; then
                local layer_dir
                layer_dir=$(get_layer_dir "${TARGET_LAYER}")
                validate_layer "${TARGET_LAYER}" "${layer_dir}"
            else
                validate_all_layers
            fi
            ;;
        destroy)
            if [[ -n "${TARGET_LAYER}" ]]; then
                local layer_dir
                layer_dir=$(get_layer_dir "${TARGET_LAYER}")
                destroy_layer "${TARGET_LAYER}" "${layer_dir}"
            else
                destroy_all_layers
            fi
            ;;
        init)
            if [[ -n "${TARGET_LAYER}" ]]; then
                if [[ "${TARGET_LAYER}" == "config" ]]; then
                    log_info "Config layer is kubectl-based and does not require initialization"
                    exit 0
                fi
                local layer_dir
                layer_dir=$(get_layer_dir "${TARGET_LAYER}")
                init_layer "${TARGET_LAYER}" "${layer_dir}" "true"
            else
                init_all_layers
            fi
            ;;
        status)
            show_all_status
            ;;
        *)
            log_error "Unknown command: ${command}"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
