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
#   --layer LAYER          Deploy specific layer only (base|middleware|application|config|all)
#   --auto-approve         Non-interactive mode (no prompts; fail fast on missing input)
#   --dry-run             Show what would be done without making changes
#   --region REGION       AWS region (overrides env.hcl)
#   --update-ado-secret   Inject ADO credentials (requires ADO_PAT and ADO_ORG_URL with --auto-approve)
#   --with-config-layer   Run config layer after Terraform layers (required with --auto-approve)
#   --skip-config-layer   Skip config layer after Terraform layers
#   --skip-ado-secret     Skip ADO secret update in config layer (ClusterSecretStore only)
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
AUTO_APPROVE=false
DRY_RUN=false
VERBOSE=false
TARGET_LAYER=""
AWS_REGION_OVERRIDE=""
UPDATE_ADO_SECRET=false
CONFIG_LAYER_WITH=false
CONFIG_LAYER_SKIP=false

# Colors for output (disabled when stderr is not a TTY or NO_COLOR is set)
RED=''
GREEN=''
YELLOW=''
BLUE=''
PURPLE=''
CYAN=''
NC=''

init_log_colors() {
    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 2 ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        PURPLE=''
        CYAN=''
        NC=''
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        CYAN='\033[0;36m'
        NC='\033[0m'
    fi
}

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
  --layer LAYER          Deploy specific layer only (base|middleware|application|config|all)
  --auto-approve         Non-interactive mode (no prompts; fail fast on missing input)
  --dry-run             Show what would be done without making changes
  --region REGION       Override AWS region from env.hcl
  --update-ado-secret   Inject ADO credentials (requires ADO_PAT and ADO_ORG_URL with --auto-approve)
  --with-config-layer   Run config layer after Terraform layers
  --skip-config-layer   Skip config layer after Terraform layers
  --skip-ado-secret     Skip ADO secret update in config layer
  --help                Show this help message
  --verbose             Enable verbose output

Environment Variables:
  TF_STATE_BUCKET         S3 bucket for Terraform state (required)
  TF_STATE_REGION         Region for state bucket (optional, uses AWS_REGION)
  TF_VAR_ado_pat_value    ADO Personal Access Token (optional; use ADO_PAT with --update-ado-secret)
  ADO_PAT                 Azure DevOps PAT (required with --update-ado-secret and --auto-approve)
  ADO_ORG_URL             Azure DevOps org URL (required with --update-ado-secret and --auto-approve)
  AWS_REGION              AWS region (optional, can be set in env.hcl)
  AWS_PROFILE             AWS profile to use (optional)
  NO_COLOR                Disable ANSI color in log output

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
  ./${SCRIPT_NAME} deploy --auto-approve --with-config-layer --update-ado-secret

EOF
}

is_non_empty() {
    local value="${1:-}"
    [[ -n "${value// }" ]]
}

is_stdin_interactive() {
    [[ -t 0 ]]
}

is_strict_mode() {
    [[ "${AUTO_APPROVE}" == "true" ]]
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

require_ado_credentials() {
    local pat="${ADO_PAT:-${TF_VAR_ado_pat_value:-}}"
    local org_url="${ADO_ORG_URL:-}"

    if is_non_empty "${pat}" && is_non_empty "${org_url}"; then
        export ADO_PAT="${pat}"
        export ADO_ORG_URL="${org_url}"
        export TF_VAR_ado_pat_value="${pat}"
        return 0
    fi

    if is_non_empty "${pat}" && ! is_non_empty "${org_url}"; then
        log_error "ADO_ORG_URL is required when using --update-ado-secret with --auto-approve"
        return 1
    fi

    if ! is_non_empty "${pat}" && is_non_empty "${org_url}"; then
        log_error "ADO_PAT is required when using --update-ado-secret with --auto-approve"
        return 1
    fi

    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        log_error "--auto-approve with --update-ado-secret requires non-empty ADO_PAT and ADO_ORG_URL"
        log_error "Set pipeline secret variables before invoking deploy.sh"
        return 1
    fi

    prompt_for_ado_credentials
}

validate_update_ado_secret_prerequisites() {
    if [[ "${UPDATE_ADO_SECRET}" != "true" ]]; then
        return 0
    fi

    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        require_ado_credentials
        return $?
    fi

    return 0
}

resolve_aws_region() {
    if [[ -n "${AWS_REGION_OVERRIDE}" ]]; then
        echo "${AWS_REGION_OVERRIDE}"
        return 0
    fi

    if [[ -n "${AWS_REGION:-}" ]]; then
        echo "${AWS_REGION}"
        return 0
    fi

    if [[ -n "${TF_STATE_REGION:-}" ]]; then
        echo "${TF_STATE_REGION}"
        return 0
    fi

    local from_output
    from_output=$(get_terragrunt_output_raw "base" "aws_region" || true)
    if [[ -n "${from_output}" ]]; then
        echo "${from_output}"
        return 0
    fi

    local from_cli
    from_cli=$(aws configure get region 2>/dev/null || true)
    if [[ -n "${from_cli}" ]]; then
        echo "${from_cli}"
        return 0
    fi

    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        log_error "Could not resolve AWS region. Set --region, AWS_REGION, or TF_STATE_REGION"
        return 1
    fi

    echo "us-west-2"
}

show_recovery_guidance() {
    local failed_layer="$1"
    shift
    local successful_layers=("$@")

    echo
    echo "================================"
    echo "RECOVERY GUIDANCE"
    echo "================================"
    echo
    echo "Current State:"
    if [[ ${#successful_layers[@]} -gt 0 ]]; then
        echo "  Successfully deployed: ${successful_layers[*]}"
    else
        echo "  No layers successfully deployed"
    fi
    echo "  Failed at: ${failed_layer}"
    echo
    echo "To recover:"
    echo "  1. Review the error messages above"
    echo "  2. Fix the issue in the ${failed_layer} layer"
    echo "  3. Re-run deployment for just the failed layer:"
    echo "     ./${SCRIPT_NAME} deploy --layer ${failed_layer}"
    echo

    case "${failed_layer}" in
        base)
            echo "Common base layer issues:"
            echo "  - Invalid AWS credentials or insufficient permissions"
            echo "  - VPC or subnet configuration issues"
            echo "  - S3 bucket does not exist or is not accessible"
            ;;
        middleware)
            echo "Common middleware layer issues:"
            echo "  - Base layer not fully deployed"
            echo "  - Kubernetes authentication issues"
            echo "  - Helm chart repository not accessible"
            ;;
        application)
            echo "Common application layer issues:"
            echo "  - Base or middleware layers not fully deployed"
            echo "  - ADO PAT secret value not set"
            echo "  - ECR repository name conflicts"
            ;;
        config)
            echo "Common config layer issues:"
            echo "  - kubectl not configured for the cluster"
            echo "  - External Secrets Operator CRDs not installed"
            echo "  - ADO_PAT or ADO_ORG_URL missing in non-interactive mode"
            ;;
    esac
    echo
    echo "To check layer status:"
    echo "  ./${SCRIPT_NAME} status"
    echo
}

report_deployment_failure() {
    local failed_layer="$1"
    shift
    local successful_layers=("$@")
    local succeeded_csv="none"

    if [[ ${#successful_layers[@]} -gt 0 ]]; then
        succeeded_csv=$(IFS=,; echo "${successful_layers[*]}")
    fi

    log_error "=== DEPLOYMENT_FAILED layer=${failed_layer} succeeded=${succeeded_csv} ==="
    show_recovery_guidance "${failed_layer}" "${successful_layers[@]}"
}

should_deploy_config_layer() {
    if [[ "${CONFIG_LAYER_WITH}" == "true" ]]; then
        return 0
    fi

    if [[ "${CONFIG_LAYER_SKIP}" == "true" ]]; then
        return 1
    fi

    if [[ "${AUTO_APPROVE}" == "true" ]]; then
        log_info "Skipping config layer (use --with-config-layer to enable in non-interactive mode)"
        return 1
    fi

    confirm_action "Deploy config layer (ClusterSecretStore + kubectl setup)?" "y"
}

# =============================================================================
# Prerequisites Checking
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check Terragrunt version (skipped in dry-run for offline validation)
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry-run mode detected: skipping tool and AWS credential checks"
    else
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

        local tg_version
        tg_version=$(terragrunt --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d 'v')
        log_debug "Terragrunt version: ${tg_version}"

        local tf_version
        tf_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
        log_debug "Terraform version: ${tf_version}"

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
        all)
            TARGET_LAYER=""
            return 0
            ;;
        base|middleware|application|config) return 0 ;;
        *)
            log_error "Invalid --layer value: ${TARGET_LAYER}"
            log_error "Valid values: base, middleware, application, config, all"
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
        apply_args+=("--non-interactive" "-auto-approve")
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
        destroy_args+=("--non-interactive" "-auto-approve")
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
        echo "  [OK] Terragrunt cache exists"
    else
        echo "  [MISSING] Terragrunt cache not found (not initialized)"
    fi

    # Check for state file
    if terragrunt state list --non-interactive &>/dev/null; then
        local resource_count
        resource_count=$(terragrunt state list --non-interactive 2>/dev/null | wc -l)
        echo "  [OK] State file exists (${resource_count} resources)"
    else
        echo "  [MISSING] No state file found (not deployed)"
    fi
}

# =============================================================================
# High-Level Operations
# =============================================================================

deploy_all_layers() {
    log "Starting deployment of all layers..."

    if [[ "${UPDATE_ADO_SECRET}" == "true" ]]; then
        log_info "ADO secret update requested - validating credentials..."
        if ! require_ado_credentials; then
            log_error "Failed to get ADO credentials"
            return 1
        fi
        log_success "ADO credentials ready for application layer deploy"
    fi

    local layers=("base" "middleware" "application")
    local successful_layers=()

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
            report_deployment_failure "${layer}" "${successful_layers[@]}"
            return 1
        fi

        successful_layers+=("${layer}")

        # Special handling for base layer - configure kubectl
        if [[ "${layer}" == "base" && "${DRY_RUN}" != "true" ]]; then
            configure_kubectl "${layer_dir}" "false"
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
        if ! is_stdin_interactive; then
            log_error "Destroy requires --auto-approve when stdin is not a TTY"
            return 1
        fi
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
    local strict="${2:-false}"

    if [[ "${strict}" == "true" ]] || is_strict_mode; then
        strict="true"
    fi

    log_info "Configuring kubectl access..."

    cd "${base_dir}"

    local cluster_name
    cluster_name=$(terragrunt output -raw cluster_name 2>/dev/null || echo "")

    if [[ -z "${cluster_name}" ]]; then
        if [[ "${strict}" == "true" ]]; then
            log_error "Could not retrieve cluster name from outputs"
            return 1
        fi
        log_warning "Could not retrieve cluster name from outputs"
        return 0
    fi

    local region
    if ! region=$(resolve_aws_region); then
        return 1
    fi

    if aws eks update-kubeconfig --region "${region}" --name "${cluster_name}" --alias "${cluster_name}" 2>/dev/null; then
        log_success "kubectl configured for cluster: ${cluster_name}"
        return 0
    fi

    if [[ "${strict}" == "true" ]]; then
        log_error "Failed to configure kubectl for cluster: ${cluster_name}"
        return 1
    fi

    log_warning "Failed to configure kubectl automatically"
    log_info "Configure manually with: aws eks update-kubeconfig --region ${region} --name ${cluster_name}"
    return 0
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
    
    if ! is_non_empty "${ADO_ORG_URL}" || ! is_non_empty "${ADO_PAT}"; then
        log_error "Organization URL and PAT token are required"
        log_error "Set via environment variables: ADO_PAT and ADO_ORG_URL"
        return 1
    fi
    
    export ADO_ORG_URL
    export ADO_PAT
    export TF_VAR_ado_pat_value="${ADO_PAT}"
    log_success "Credentials received"
    return 0
}

prepare_ado_pat_for_terraform() {
    if [[ -n "${ADO_PAT:-}" ]]; then
        export TF_VAR_ado_pat_value="${ADO_PAT}"
    fi
}

# Forces External Secrets Operator to sync and restarts KEDA so ScaledJobs
# resolve the updated ADO PAT from Kubernetes secrets.
refresh_ado_secret_in_cluster() {
    local cluster_name="$1"
    local region="$2"
    local secret_name="$3"
    local strict="false"

    if is_strict_mode && [[ "${UPDATE_ADO_SECRET}" == "true" ]]; then
        strict="true"
    fi

    log_info "Refreshing Kubernetes resources to pick up new ADO secret..."

    # Ensure kubectl is configured
    if ! configure_kubectl "${BASE_LAYER_DIR}" "${strict}"; then
        if [[ "${strict}" == "true" ]]; then
            log_error "Could not configure kubectl; cluster refresh failed"
            return 1
        fi
        log_warning "Could not configure kubectl; skipping cluster refresh"
        log_info "Manually refresh with: kubectl annotate externalsecret -n ado-agents ${secret_name}-secret force-sync=\$(date +%s) --overwrite"
        log_info "Then restart KEDA: kubectl rollout restart deployment -n keda-system keda-operator"
        return 0
    fi

    # Check kubectl access
    if ! kubectl get nodes &>/dev/null; then
        if [[ "${strict}" == "true" ]]; then
            log_error "Cannot access Kubernetes cluster; cluster refresh failed"
            return 1
        fi
        log_warning "Cannot access Kubernetes cluster; skipping cluster refresh"
        return 0
    fi

    local ado_namespace keda_namespace
    ado_namespace=$(cd "${MIDDLEWARE_LAYER_DIR}" && terragrunt output -raw ado_agents_namespace 2>/dev/null || echo "ado-agents")
    keda_namespace=$(cd "${MIDDLEWARE_LAYER_DIR}" && terragrunt output -raw keda_namespace 2>/dev/null || echo "keda-system")

    local external_secret_name="${secret_name}-secret"

    # Force External Secrets Operator to immediately sync the secret
    if kubectl get externalsecret "${external_secret_name}" -n "${ado_namespace}" &>/dev/null; then
        log_info "Forcing ExternalSecret ${external_secret_name} to sync..."
        if kubectl annotate externalsecret "${external_secret_name}" -n "${ado_namespace}" \
            force-sync="$(date +%s)" --overwrite 2>/dev/null; then
            log_success "ExternalSecret refresh triggered"
            log_info "Waiting 5s for ESO to sync..."
            sleep 5
        else
            if [[ "${strict}" == "true" ]]; then
                log_error "Failed to annotate ExternalSecret ${external_secret_name}"
                return 1
            fi
            log_warning "Failed to annotate ExternalSecret (ESO may use different annotation)"
        fi
    else
        if [[ "${strict}" == "true" ]]; then
            log_error "ExternalSecret ${external_secret_name} not found in ${ado_namespace}"
            return 1
        fi
        log_warning "ExternalSecret ${external_secret_name} not found in ${ado_namespace}; application layer may not be deployed yet"
    fi

    # Restart KEDA operator so it re-resolves secrets for ScaledJobs
    if kubectl get deployment keda-operator -n "${keda_namespace}" &>/dev/null; then
        log_info "Restarting KEDA operator to refresh secret resolution..."
        if kubectl rollout restart deployment keda-operator -n "${keda_namespace}"; then
            log_success "KEDA operator restart initiated"
        else
            if [[ "${strict}" == "true" ]]; then
                log_error "Failed to restart KEDA operator"
                return 1
            fi
            log_warning "Failed to restart KEDA operator"
        fi
    else
        if [[ "${strict}" == "true" ]]; then
            log_error "KEDA operator not found in ${keda_namespace}"
            return 1
        fi
        log_warning "KEDA operator not found in ${keda_namespace}; ScaledJobs will reconcile on next sync interval"
    fi

    # ScaledJob workers are created per queued job and read the current secret at pod start.
    if kubectl get scaledjob -n "${ado_namespace}" -l app.kubernetes.io/name=ado-agent-cluster &>/dev/null; then
        log_info "ADO ScaledJob workers will use the refreshed secret on the next queued job."
    fi

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
            '{"personalAccessToken": $pat, "organization": $org, "adourl": $url}')
        
        if aws secretsmanager put-secret-value \
            --secret-id "${secret_name}" \
            --secret-string "${secret_json}" \
            --region "${region}" >/dev/null; then
            log_success "ADO PAT updated in AWS Secrets Manager: ${secret_name}"
            # Refresh Kubernetes resources so KEDA ScaledJobs pick up the new value
            refresh_ado_secret_in_cluster "${cluster_name}" "${region}" "${secret_name}"
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
apiVersion: external-secrets.io/v1
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

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy config layer"
        if [[ "${update_ado_secret}" == "true" ]]; then
            log_info "[DRY-RUN] Would update ADO secret in AWS Secrets Manager"
        fi
        return 0
    fi

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
    if ! configure_kubectl "${base_dir}" "true"; then
        log_error "Failed to configure kubectl for config layer"
        return 1
    fi

    local region
    if ! region=$(resolve_aws_region); then
        return 1
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

        if ! require_ado_credentials; then
            log_error "Failed to get ADO credentials"
            return 1
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

trap 'log_error "Command failed at line ${LINENO}: ${BASH_COMMAND}"; exit 1' ERR

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
            --with-config-layer)
                CONFIG_LAYER_WITH=true
                CONFIG_LAYER_SKIP=false
                shift
                ;;
            --skip-config-layer)
                CONFIG_LAYER_SKIP=true
                CONFIG_LAYER_WITH=false
                shift
                ;;
            --skip-ado-secret)
                UPDATE_ADO_SECRET=false
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

    if [[ "${CONFIG_LAYER_WITH}" == "true" && "${CONFIG_LAYER_SKIP}" == "true" ]]; then
        log_error "Cannot use --with-config-layer and --skip-config-layer together"
        exit 1
    fi

    init_log_colors

    if ! validate_update_ado_secret_prerequisites; then
        exit 1
    fi

    # Display configuration
    log_info "Configuration:"
    log_debug "  Command: ${command}"
    log_debug "  Target Layer: ${TARGET_LAYER:-all}"
    log_debug "  Auto Approve: ${AUTO_APPROVE}"
    log_debug "  Dry Run: ${DRY_RUN}"
    log_debug "  Verbose: ${VERBOSE}"
    log_debug "  Update ADO Secret: ${UPDATE_ADO_SECRET}"
    log_debug "  Config Layer With: ${CONFIG_LAYER_WITH}"
    log_debug "  Config Layer Skip: ${CONFIG_LAYER_SKIP}"
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
                    if ! deploy_config_layer "${BASE_LAYER_DIR}" "${UPDATE_ADO_SECRET}"; then
                        report_deployment_failure "config"
                        exit 1
                    fi
                else
                    # If deploying application layer with ADO secret update, validate credentials first
                    if [[ "${TARGET_LAYER}" == "application" && "${UPDATE_ADO_SECRET}" == "true" ]]; then
                        log_info "ADO secret update requested for application layer - validating credentials..."
                        if ! require_ado_credentials; then
                            log_error "Failed to get ADO credentials"
                            exit 1
                        fi
                        log_success "ADO credentials ready for application layer deploy"
                    fi

                    local layer_dir
                    layer_dir=$(get_layer_dir "${TARGET_LAYER}")
                    if ! apply_layer "${TARGET_LAYER}" "${layer_dir}"; then
                        report_deployment_failure "${TARGET_LAYER}"
                        exit 1
                    fi

                    # If application layer with ADO secret update, inject the secret immediately
                    if [[ "${TARGET_LAYER}" == "application" && "${UPDATE_ADO_SECRET}" == "true" ]]; then
                        log_info "Injecting ADO secret after application layer deployment..."

                        # Get cluster info from base layer
                        cd "${BASE_LAYER_DIR}"
                        local cluster_name region
                        cluster_name=$(terragrunt output -raw cluster_name 2>/dev/null || echo "")
                        if ! region=$(resolve_aws_region); then
                            exit 1
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
                    fi
                fi
            else
                if ! deploy_all_layers; then
                    exit 1
                fi
                if should_deploy_config_layer; then
                    if ! deploy_config_layer "${BASE_LAYER_DIR}" "${UPDATE_ADO_SECRET}"; then
                        report_deployment_failure "config"
                        exit 1
                    fi
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
