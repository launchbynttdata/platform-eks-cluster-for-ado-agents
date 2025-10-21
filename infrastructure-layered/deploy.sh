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
#   ./deploy-tg.sh [OPTIONS] [COMMAND]
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
#   --update-ado-secret   Update ADO PAT in AWS Secrets Manager (config layer only)
#   --help                Show this help message
#   --verbose             Enable verbose output

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LAYERS_DIR="${SCRIPT_DIR}"

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
Usage: ${0##*/} [OPTIONS] [COMMAND]

Commands:
  deploy        Deploy all layers in order (default)
  plan          Show deployment plan for all layers
  validate      Validate configurations
  destroy       Destroy all layers in reverse order
  status        Show status of all layers
  
Options:
  --layer LAYER          Deploy specific layer only (base|middleware|application|config)
  --auto-approve         Skip interactive prompts
  --dry-run             Show what would be done without making changes
  --region REGION       Override AWS region from env.hcl
  --update-ado-secret   Update ADO PAT in AWS Secrets Manager (config layer only)
  --help                Show this help message
  --verbose             Enable verbose output

Environment Variables:
  TF_STATE_BUCKET     S3 bucket for Terraform state (required)
  TF_STATE_REGION     Region for state bucket (optional, uses AWS_REGION)
  TF_VAR_ado_pat_value    ADO Personal Access Token (required for application layer)
  AWS_REGION          AWS region (optional, can be set in env.hcl)
  AWS_PROFILE         AWS profile to use (optional)

Examples:
  # Deploy all layers
  ./deploy-tg.sh deploy

  # Deploy only base layer
  ./deploy-tg.sh deploy --layer base

  # Show plan for all layers
  ./deploy-tg.sh plan

  # Deploy specific layer
  ./deploy-tg.sh deploy --layer base

  # Deploy config layer (post-deployment)
  ./deploy-tg.sh deploy --layer config

  # Update ADO PAT in AWS Secrets Manager
  ./deploy-tg.sh deploy --layer config --update-ado-secret

  # Destroy all layers
  ./deploy-tg.sh destroy

  # Deploy with auto-approve (CI/CD)
  ./deploy-tg.sh deploy --auto-approve

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
    for tool in aws terragrunt terraform helm kubectl; do
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
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_error "Run 'aws configure' to set up credentials"
        exit 1
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity --output json)
    log_debug "AWS Identity: $(echo "${caller_identity}" | jq -r '.Arn')"
    
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
    
    if ! terragrunt validate --terragrunt-non-interactive; then
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
    
    local plan_args=()
    if [[ "${VERBOSE}" == "true" ]]; then
        plan_args+=("--terragrunt-log-level" "debug")
    fi
    
    if ! terragrunt plan --terragrunt-non-interactive "${plan_args[@]}"; then
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
    
    local apply_args=()
    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        apply_args+=("--terragrunt-non-interactive")
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
        destroy_args+=("--terragrunt-non-interactive")
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
    if terragrunt state list --terragrunt-non-interactive &>/dev/null; then
        local resource_count
        resource_count=$(terragrunt state list --terragrunt-non-interactive 2>/dev/null | wc -l)
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
    log_info "=== Azure DevOps Configuration ==="
    echo
    
    read -rp "Enter ADO Organization URL (e.g., https://dev.azure.com/yourorg): " ADO_ORG_URL
    read -rsp "Enter ADO Personal Access Token: " ADO_PAT
    echo
    
    if [[ -z "${ADO_ORG_URL}" || -z "${ADO_PAT}" ]]; then
        log_error "ADO Organization URL and PAT are required"
        return 1
    fi
    
    export ADO_ORG_URL
    export ADO_PAT
    return 0
}

inject_ado_secret() {
    local cluster_name="$1"
    local region="$2"
    
    log_info "Updating ADO PAT in AWS Secrets Manager..."
    
    if [[ -z "${ADO_PAT}" ]]; then
        log_error "ADO_PAT not set. Run with credential prompting first."
        return 1
    fi
    
    local secret_name="${cluster_name}-ado-pat"
    
    # Check if secret exists
    if aws secretsmanager describe-secret --secret-id "${secret_name}" --region "${region}" &>/dev/null; then
        log_info "Updating existing secret: ${secret_name}"
        if aws secretsmanager put-secret-value \
            --secret-id "${secret_name}" \
            --secret-string "${ADO_PAT}" \
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
    local eso_sa_name="external-secrets-sa"
    
    log_info "Creating ClusterSecretStore for External Secrets Operator..."
    
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
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${region}
      auth:
        jwt:
          serviceAccountRef:
            name: ${eso_sa_name}
            namespace: external-secrets
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
        status=$(kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
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
    log_info "Check status with: kubectl get clustersecretstore aws-secrets-manager -o yaml"
    return 1
}

deploy_config_layer() {
    local base_dir="$1"
    local update_ado_secret="${2:-false}"
    
    log_section "Config Layer Deployment (Post-Deployment Configuration)"
    
    # Verify all Terraform layers are deployed
    log_info "Verifying prerequisite layers..."
    
    local layers=("base" "middleware" "application")
    for layer in "${layers[@]}"; do
        local layer_dir
        layer_dir=$(get_layer_dir "${layer}")
        
        cd "${layer_dir}"
        if ! terragrunt output cluster_name &>/dev/null 2>&1 && \
           ! terragrunt output eso_role_arn &>/dev/null 2>&1; then
            if [[ "${layer}" == "base" ]]; then
                log_error "Base layer not deployed. Deploy base layer first."
                return 1
            fi
        fi
    done
    
    log_success "All prerequisite layers are deployed"
    
    # Configure kubectl
    configure_kubectl "${base_dir}"
    
    # Get cluster information from base layer
    cd "$(get_layer_dir "base")"
    
    local cluster_name
    cluster_name=$(terragrunt output -raw cluster_name 2>/dev/null || echo "")
    
    if [[ -z "${cluster_name}" ]]; then
        log_error "Could not retrieve cluster name from base layer outputs"
        return 1
    fi
    
    local region="${AWS_REGION_OVERRIDE:-}"
    if [[ -z "${region}" ]]; then
        region=$(aws configure get region 2>/dev/null || echo "us-west-2")
    fi
    
    # Get ESO IAM role ARN from middleware layer
    cd "$(get_layer_dir "middleware")"
    
    local eso_role_arn
    eso_role_arn=$(terragrunt output -raw eso_role_arn 2>/dev/null || echo "")
    
    if [[ -z "${eso_role_arn}" ]]; then
        log_warning "Could not retrieve ESO IAM role ARN from middleware layer"
        log_info "ClusterSecretStore will be created but may need manual configuration"
    fi
    
    # Create ClusterSecretStore
    if ! create_cluster_secret_store "${cluster_name}" "${region}" "${eso_role_arn}"; then
        log_error "Failed to create ClusterSecretStore"
        return 1
    fi
    
    # Update ADO secret if requested
    if [[ "${update_ado_secret}" == "true" ]]; then
        log_info "ADO secret update requested..."
        
        if [[ -z "${ADO_PAT}" ]]; then
            if ! prompt_for_ado_credentials; then
                log_error "Failed to get ADO credentials"
                return 1
            fi
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
    log_info "  kubectl get clustersecretstore aws-secrets-manager"
    log_info ""
    log_info "Check External Secrets:"
    log_info "  kubectl get externalsecrets -A"
    log_info ""
    log_info "To update ADO PAT later:"
    log_info "  ./deploy-tg.sh deploy --layer config --update-ado-secret"
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
            deploy|plan|validate|destroy|status)
                command="$1"
                shift
                ;;
            --layer)
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
                    local layer_dir
                    layer_dir=$(get_layer_dir "${TARGET_LAYER}")
                    apply_layer "${TARGET_LAYER}" "${layer_dir}"
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
