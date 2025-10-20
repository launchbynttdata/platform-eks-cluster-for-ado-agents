#!/usr/bin/env bash

# =============================================================================
# EKS ADO Agents Infrastructure Orchestration Script
# =============================================================================
#
# This script orchestrates the deployment of a three-layer infrastructure
# stack for Azure DevOps (ADO) agents running on Amazon EKS:
#
# 1. Base Layer: Core EKS cluster, networking, IAM, KMS
# 2. Middleware Layer: KEDA, External Secrets Operator, buildkitd
# 3. Application Layer: ECR repositories, secrets, ADO agent deployments
#
# Features:
# - Automated dependency validation
# - Layer-by-layer deployment with health checks
# - Comprehensive error handling and rollback capabilities
# - Interactive mode for production deployments
# - Dry-run mode for validation
# - State validation and drift detection
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
#   --layer LAYER        Deploy specific layer only (base|middleware|application|config)
#   --auto-approve       Skip interactive prompts
#   --dry-run           Show what would be done without making changes
#   --backend-config     Path to backend configuration file
#   --var-file          Path to terraform variables file
#   --region REGION     AWS region (default: us-east-1)
#   --help              Show this help message
#   --verbose           Enable verbose output
#   --force             Skip dependency checks (dangerous)

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LAYERS_DIR="$PROJECT_ROOT/infrastructure-layered"

readonly BASE_LAYER_DIR="$LAYERS_DIR/base"
readonly MIDDLEWARE_LAYER_DIR="$LAYERS_DIR/middleware"
readonly APPLICATION_LAYER_DIR="$LAYERS_DIR/application"
readonly CONFIG_LAYER_DIR="$LAYERS_DIR"  # Config layer doesn't have a subdirectory
readonly HELM_CHART_DIR="$LAYERS_DIR/helm/ado-agent-cluster"

# Default configuration
DEFAULT_REGION="us-east-1"
DEFAULT_COMMAND="deploy"
AUTO_APPROVE=false
DRY_RUN=false
VERBOSE=false
FORCE=false
UPDATE_ADO_SECRET=false
TARGET_LAYER=""
BACKEND_CONFIG_FILE=""
VAR_FILE=""
# Preserve AWS_REGION from environment (e.g., direnv) if set, otherwise use default
AWS_REGION="${AWS_REGION:-$DEFAULT_REGION}"

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
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
    fi
}

show_usage() {
    cat << EOF
EKS ADO Agents Infrastructure Orchestration Script

USAGE:
    $0 [OPTIONS] [COMMAND]

COMMANDS:
    deploy        Deploy all layers in order (default)
    plan          Show deployment plan for all layers  
    validate      Validate all configurations without deploying
    destroy       Destroy all layers in reverse order
    status        Show current status of all layers

OPTIONS:
    --layer LAYER        Target specific layer only (base|middleware|application|config)
    --auto-approve       Skip interactive confirmation prompts
    --dry-run           Show actions without executing them
    --backend-config     Path to backend configuration file
    --var-file FILE     Path to terraform variables file
    --region REGION     AWS region (default: us-east-1)
    --verbose           Enable verbose debug output
    --force             Skip safety checks and dependencies (dangerous)
    
    Config Layer Options (for use with --layer config):
    --update-ado-secret Update ADO PAT secret with new credentials (default: skip)
    
    --help              Show this help message

EXAMPLES:
    # Set required environment variable
    export TF_STATE_BUCKET='my-terraform-state-bucket'
    
    # Deploy entire stack interactively (includes config layer)
    $0 deploy

    # Deploy only base layer with auto-approval
    $0 --layer base --auto-approve deploy
    
    # Deploy only config layer (post-deployment configuration)
    # By default, does NOT update the ADO secret
    $0 --layer config deploy
    
    # Deploy config layer and update ADO PAT secret
    # Credentials from environment variables (ADO_PAT, ADO_ORG_URL) or prompts
    export ADO_PAT="your-pat-token"
    export ADO_ORG_URL="https://dev.azure.com/your-org"
    $0 --layer config --update-ado-secret deploy

    # Show deployment plan for all layers
    $0 plan

    # Validate configuration without deploying
    $0 validate

    # Deploy with custom variables file
    $0 --var-file production.tfvars deploy

    # Check status of all layers
    $0 status

    # Destroy in dry-run mode
    $0 --dry-run destroy

ENVIRONMENT VARIABLES:
    TF_STATE_BUCKET      (Required) S3 bucket name for Terraform remote state storage
    TF_STATE_REGION      (Optional) AWS region for the S3 state bucket (defaults to AWS_REGION)
    AWS_REGION           (Optional) AWS region for resources (defaults to AWS CLI default region)

LAYER DEPENDENCIES:
    base → middleware → application → config

    Each infrastructure layer depends on outputs from the previous layer via remote state.
    The config layer performs post-deployment configuration (ClusterSecretStore, ADO PAT injection).
    Layers must be deployed in order and destroyed in reverse order.

PREREQUISITES:
    • AWS CLI configured with appropriate permissions
    • Terraform >= 1.5 installed
    • Helm >= 3.10 installed  
    • kubectl configured (for post-deployment validation)
    • S3 bucket for remote state storage (set in TF_STATE_BUCKET)
    • sed utility installed (for bucket name substitution)

EOF
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        log_info "Auto-approved: $message"
        return 0
    fi
    
    local prompt="$message (y/N): "
    if [[ "$default" == "y" ]]; then
        prompt="$message (Y/n): "
    fi
    
    while true; do
        echo -ne "${YELLOW}$prompt${NC}"
        read -r response
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            "") 
                if [[ "$default" == "y" ]]; then
                    return 0
                else
                    return 1
                fi
                ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    for tool in aws terraform helm kubectl sed; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        exit 1
    fi
    
    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version')
    local required_version="1.5.0"
    
    if ! version_compare "$tf_version" "$required_version"; then
        log_error "Terraform version $tf_version is less than required $required_version"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_error "Run 'aws configure' to set up credentials"
        exit 1
    fi
    
    # Check AWS region (prioritize environment variable, then AWS CLI config, then default)
    if [[ -n "${AWS_REGION:-}" ]]; then
        log_info "Using AWS region from environment: $AWS_REGION"
    else
        local current_region
        current_region=$(aws configure get region 2>/dev/null || echo "")
        if [[ -n "$current_region" ]]; then
            AWS_REGION="$current_region"
            log_info "Using AWS region from AWS CLI config: $AWS_REGION"
        else
            AWS_REGION="$DEFAULT_REGION"
            log_warning "No AWS region configured, using default: $AWS_REGION"
        fi
    fi
    
    # Check for TF_STATE_BUCKET environment variable
    if [[ -z "${TF_STATE_BUCKET:-}" ]]; then
        log_error "TF_STATE_BUCKET environment variable is not set"
        log_error "Export TF_STATE_BUCKET with your S3 bucket name:"
        log_error "  export TF_STATE_BUCKET='my-terraform-state-bucket'"
        exit 1
    fi
    
    # Set TF_STATE_REGION if not already set (use detected AWS_REGION)
    if [[ -z "${TF_STATE_REGION:-}" ]]; then
        TF_STATE_REGION="$AWS_REGION"
        log_debug "Using AWS region for state bucket: $TF_STATE_REGION"
    fi
    
    log_success "Prerequisites check passed"
    log_info "Using S3 state bucket: $TF_STATE_BUCKET (region: $TF_STATE_REGION)"
}

version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Simple version comparison (works for semantic versioning)
    if [[ "$(printf '%s\n' "$version2" "$version1" | sort -V | head -n1)" == "$version2" ]]; then
        return 0  # version1 >= version2
    else
        return 1  # version1 < version2
    fi
}

validate_layer_directory() {
    local layer="$1"
    local layer_dir="$2"
    
    # Config layer doesn't have a traditional directory structure
    if [[ "$layer" == "config" ]]; then
        return 0
    fi
    
    log_debug "Validating layer directory: $layer_dir"
    
    if [[ ! -d "$layer_dir" ]]; then
        log_error "Layer directory not found: $layer_dir"
        return 1
    fi
    
    # Check for required Terraform files
    local required_files=("main.tf" "variables.tf" "outputs.tf")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$layer_dir/$file" ]]; then
            log_error "Required file not found in $layer: $file"
            return 1
        fi
    done
    
    # Check for sample tfvars file
    if [[ ! -f "$layer_dir/terraform.tfvars.sample" ]]; then
        log_warning "Sample tfvars file not found in $layer: terraform.tfvars.sample"
    fi
    
    return 0
}

substitute_bucket_placeholder() {
    local layer_dir="$1"
    local main_tf="$layer_dir/main.tf"
    
    log_debug "Substituting S3 bucket placeholder in $main_tf"
    
    if [[ ! -f "$main_tf" ]]; then
        log_error "main.tf not found: $main_tf"
        return 1
    fi
    
    # Check if placeholder exists
    if ! grep -q "TF_STATE_BUCKET_PLACEHOLDER" "$main_tf"; then
        log_debug "No placeholder found in $main_tf, assuming already substituted"
        return 0
    fi
    
    # Substitute placeholders with actual values
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would substitute TF_STATE_BUCKET_PLACEHOLDER with $TF_STATE_BUCKET"
        log_info "[DRY-RUN] Would substitute TF_STATE_REGION_PLACEHOLDER with $TF_STATE_REGION"
        return 0
    fi
    
    # Use sed to replace the placeholders
    # macOS and Linux have different sed syntax, so we'll use a compatible approach
    if sed --version &>/dev/null 2>&1; then
        # GNU sed (Linux)
        sed -i "s/TF_STATE_BUCKET_PLACEHOLDER/$TF_STATE_BUCKET/g" "$main_tf"
        sed -i "s/TF_STATE_REGION_PLACEHOLDER/$TF_STATE_REGION/g" "$main_tf"
    else
        # BSD sed (macOS)
        sed -i '' "s/TF_STATE_BUCKET_PLACEHOLDER/$TF_STATE_BUCKET/g" "$main_tf"
        sed -i '' "s/TF_STATE_REGION_PLACEHOLDER/$TF_STATE_REGION/g" "$main_tf"
    fi
    
    log_debug "Substituted bucket placeholder with: $TF_STATE_BUCKET"
    log_debug "Substituted region placeholder with: $TF_STATE_REGION"
    return 0
}

restore_bucket_placeholder() {
    local layer_dir="$1"
    local main_tf="$layer_dir/main.tf"
    
    log_debug "Restoring S3 bucket and region placeholders in $main_tf"
    
    if [[ ! -f "$main_tf" ]]; then
        return 0
    fi
    
    # Check if bucket name exists (not placeholder)
    if ! grep -q "bucket = \"$TF_STATE_BUCKET\"" "$main_tf"; then
        log_debug "Bucket already using placeholder in $main_tf"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore TF_STATE_BUCKET_PLACEHOLDER and TF_STATE_REGION_PLACEHOLDER"
        return 0
    fi
    
    # Restore the placeholders
    if sed --version &>/dev/null 2>&1; then
        # GNU sed (Linux)
        sed -i "s/bucket = \"$TF_STATE_BUCKET\"/bucket = \"TF_STATE_BUCKET_PLACEHOLDER\"/g" "$main_tf"
        sed -i "s/region = \"$TF_STATE_REGION\"/region = \"TF_STATE_REGION_PLACEHOLDER\"/g" "$main_tf"
    else
        # BSD sed (macOS)
        sed -i '' "s/bucket = \"$TF_STATE_BUCKET\"/bucket = \"TF_STATE_BUCKET_PLACEHOLDER\"/g" "$main_tf"
        sed -i '' "s/region = \"$TF_STATE_REGION\"/region = \"TF_STATE_REGION_PLACEHOLDER\"/g" "$main_tf"
    fi
    
    log_debug "Restored bucket and region placeholders"
    return 0
}

get_terraform_var_args() {
    local layer="${1:-}"  # Optional layer name parameter
    local var_args=()
    
    if [[ -n "$VAR_FILE" ]]; then
        if [[ -f "$VAR_FILE" ]]; then
            var_args+=("-var-file=$VAR_FILE")
        else
            log_error "Variables file not found: $VAR_FILE"
            return 1
        fi
    fi
    
    # Add region variable
    var_args+=("-var=aws_region=$AWS_REGION")
    
    # Add remote state bucket variable for layers that need it (middleware and application)
    # Base layer doesn't need this variable as it has no dependencies
    if [[ -n "${TF_STATE_BUCKET:-}" ]] && [[ "$layer" != "base" ]]; then
        var_args+=("-var=remote_state_bucket=$TF_STATE_BUCKET")
    fi
    
    printf '%s\n' "${var_args[@]}"
}

configure_kubectl_alias() {
    local cluster_name="$1"
    local region="${2:-$AWS_REGION}"
    local context_alias="${3:-$cluster_name}"
    
    log_info "Configuring kubectl access for cluster: $cluster_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure kubectl with alias: $context_alias"
        return 0
    fi
    
    # Update kubeconfig with the cluster configuration
    if ! aws eks update-kubeconfig \
        --region "$region" \
        --name "$cluster_name" \
        --alias "$context_alias" 2>/dev/null; then
        log_warning "Failed to configure kubectl for cluster $cluster_name"
        return 1
    fi
    
    log_success "Successfully configured kubectl with context alias: $context_alias"
    
    # Test cluster connectivity
    if kubectl cluster-info --context "$context_alias" &>/dev/null; then
        log_success "Cluster connectivity verified"
        log_info "You can now access the cluster using: kubectl --context $context_alias"
        log_info "Or set as default: kubectl config use-context $context_alias"
    else
        log_warning "Cluster is not immediately accessible (may still be initializing)"
    fi
    
    return 0
}

# =============================================================================
# Layer Management Helpers
# =============================================================================

get_layer_directory() {
    local layer="$1"
    
    case "$layer" in
        base) echo "$BASE_LAYER_DIR" ;;
        middleware) echo "$MIDDLEWARE_LAYER_DIR" ;;
        application) echo "$APPLICATION_LAYER_DIR" ;;
        config) echo "$CONFIG_LAYER_DIR" ;;
        *)
            log_error "Unknown layer: $layer"
            return 1
            ;;
    esac
}

validate_layer_name() {
    local layer="$1"
    
    case "$layer" in
        base|middleware|application|config)
            return 0
            ;;
        *)
            log_error "Invalid layer: $layer"
            log_error "Valid layers: base, middleware, application, config"
            return 1
            ;;
    esac
}

get_layers_and_dirs() {
    local target_layer="$1"
    local reverse="${2:-false}"
    
    local layers=()
    local layer_dirs=()
    
    if [[ -n "$target_layer" ]]; then
        # Single layer mode
        if ! validate_layer_name "$target_layer"; then
            return 1
        fi
        layers=("$target_layer")
        layer_dirs=("$(get_layer_directory "$target_layer")")
    else
        # All layers mode
        if [[ "$reverse" == "true" ]]; then
            # Reverse order for destroy operations
            layers=("config" "application" "middleware" "base")
        else
            # Normal order for deploy/plan/validate
            layers=("base" "middleware" "application" "config")
        fi
        
        for layer in "${layers[@]}"; do
            layer_dirs+=("$(get_layer_directory "$layer")")
        done
    fi
    
    # Export arrays for caller to use
    # Return as newline-separated values: layer|dir
    for i in "${!layers[@]}"; do
        echo "${layers[$i]}|${layer_dirs[$i]}"
    done
}

show_layer_list() {
    local title="$1"
    local symbol="$2"
    shift 2
    local layers=("$@")
    
    if [[ ${#layers[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "$title:"
    for layer in "${layers[@]}"; do
        echo "  $symbol $layer"
    done
    echo
}

calculate_skipped_layers() {
    local -n processed_layers_ref=$1
    
    local all_layers=("base" "middleware" "application" "config")
    local skipped_layers=()
    
    for check_layer in "${all_layers[@]}"; do
        local found=false
        for processed_layer in "${processed_layers_ref[@]}"; do
            if [[ "$check_layer" == "$processed_layer" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            skipped_layers+=("$check_layer")
        fi
    done
    
    if [[ ${#skipped_layers[@]} -gt 0 ]]; then
        echo "Other layers (not processed - layer mode):"
        for layer in "${skipped_layers[@]}"; do
            echo "  ⊘ $layer (skipped)"
        done
        echo
    fi
}

# =============================================================================
# Terraform Operations
# =============================================================================

terraform_init() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Initializing Terraform for $layer layer..."
    
    # Substitute bucket placeholder before init
    if ! substitute_bucket_placeholder "$layer_dir"; then
        log_error "Failed to substitute bucket placeholder"
        return 1
    fi
    
    cd "$layer_dir"
    
    local init_cmd="terraform init -reconfigure"
    
    log_debug "Running: $init_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $init_cmd"
        restore_bucket_placeholder "$layer_dir"
        return 0
    fi
    
    if ! eval "$init_cmd"; then
        log_error "Terraform init failed for $layer layer"
        restore_bucket_placeholder "$layer_dir"
        return 1
    fi
    
    log_success "Terraform initialized for $layer layer"
    
    # Restore placeholder to keep files clean in version control
    restore_bucket_placeholder "$layer_dir"
}

terraform_validate() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Validating Terraform configuration for $layer layer..."
    
    # Substitute bucket placeholder before validate
    if ! substitute_bucket_placeholder "$layer_dir"; then
        log_error "Failed to substitute bucket placeholder"
        return 1
    fi
    
    cd "$layer_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate Terraform configuration"
        restore_bucket_placeholder "$layer_dir"
        return 0
    fi
    
    if ! terraform validate; then
        log_error "Terraform validation failed for $layer layer"
        restore_bucket_placeholder "$layer_dir"
        return 1
    fi
    
    log_success "Terraform validation passed for $layer layer"
    
    # Restore placeholder
    restore_bucket_placeholder "$layer_dir"
}

terraform_plan() {
    local layer="$1"
    local layer_dir="$2"
    local plan_file="${3:-}"  # Optional plan file path
    
    log_info "Planning Terraform changes for $layer layer..."
    
    # Substitute bucket placeholder before plan
    if ! substitute_bucket_placeholder "$layer_dir"; then
        log_error "Failed to substitute bucket placeholder"
        return 1
    fi
    
    local var_args
    if ! var_args=$(get_terraform_var_args "$layer"); then
        restore_bucket_placeholder "$layer_dir"
        return 1
    fi
    
    cd "$layer_dir"
    
    local plan_cmd="terraform plan -detailed-exitcode"
    
    # Add plan output file if specified
    if [[ -n "$plan_file" ]]; then
        plan_cmd="$plan_cmd -out=$plan_file"
    fi
    
    # Add variable arguments
    while IFS= read -r arg; do
        if [[ -n "$arg" ]]; then
            plan_cmd="$plan_cmd $arg"
        fi
    done <<< "$var_args"
    
    log_debug "Running: $plan_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $plan_cmd"
        restore_bucket_placeholder "$layer_dir"
        return 0
    fi
    
    # Run terraform plan and capture exit code
    local plan_exitcode=0
    eval "$plan_cmd" || plan_exitcode=$?
    
    # Restore placeholder
    restore_bucket_placeholder "$layer_dir"
    
    case $plan_exitcode in
        0)
            log_success "No changes required for $layer layer"
            # Clean up plan file if no changes
            if [[ -n "$plan_file" && -f "$plan_file" ]]; then
                rm -f "$plan_file"
            fi
            return 0
            ;;
        1)
            log_error "Terraform plan failed for $layer layer"
            # Clean up plan file on error
            if [[ -n "$plan_file" && -f "$plan_file" ]]; then
                rm -f "$plan_file"
            fi
            return 1
            ;;
        2)
            log_info "Changes planned for $layer layer"
            if [[ -n "$plan_file" ]]; then
                log_debug "Plan saved to: $plan_file"
            fi
            return 2  # Changes detected
            ;;
        *)
            log_error "Unexpected exit code from terraform plan: $plan_exitcode"
            # Clean up plan file on error
            if [[ -n "$plan_file" && -f "$plan_file" ]]; then
                rm -f "$plan_file"
            fi
            return 1
            ;;
    esac
}

terraform_apply() {
    local layer="$1"
    local layer_dir="$2"
    local plan_file="${3:-}"  # Optional plan file to apply
    
    log_info "Applying Terraform changes for $layer layer..."
    
    # Substitute bucket placeholder before apply
    if ! substitute_bucket_placeholder "$layer_dir"; then
        log_error "Failed to substitute bucket placeholder"
        return 1
    fi
    
    cd "$layer_dir"
    
    local apply_cmd
    if [[ -n "$plan_file" && -f "$plan_file" ]]; then
        # Apply from plan file (no need for -auto-approve or var args)
        apply_cmd="terraform apply $plan_file"
        log_debug "Applying from plan file: $plan_file"
    else
        # Traditional apply with variables
        local var_args
        if ! var_args=$(get_terraform_var_args "$layer"); then
            restore_bucket_placeholder "$layer_dir"
            return 1
        fi
        
        apply_cmd="terraform apply"
        
        if [[ "$AUTO_APPROVE" == "true" ]]; then
            apply_cmd="$apply_cmd -auto-approve"
        fi
        
        # Add variable arguments  
        while IFS= read -r arg; do
            if [[ -n "$arg" ]]; then
                apply_cmd="$apply_cmd $arg"
            fi
        done <<< "$var_args"
    fi
    
    log_debug "Running: $apply_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $apply_cmd"
        restore_bucket_placeholder "$layer_dir"
        return 0
    fi
    
    if ! eval "$apply_cmd"; then
        log_error "Terraform apply failed for $layer layer"
        restore_bucket_placeholder "$layer_dir"
        # Clean up plan file on error
        if [[ -n "$plan_file" && -f "$plan_file" ]]; then
            rm -f "$plan_file"
        fi
        return 1
    fi
    
    log_success "Terraform apply completed for $layer layer"
    
    # Clean up plan file after successful apply
    if [[ -n "$plan_file" && -f "$plan_file" ]]; then
        rm -f "$plan_file"
        log_debug "Removed plan file: $plan_file"
    fi
    
    # Restore placeholder
    restore_bucket_placeholder "$layer_dir"
}

terraform_destroy() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Destroying Terraform resources for $layer layer..."
    
    # Substitute bucket placeholder before destroy
    if ! substitute_bucket_placeholder "$layer_dir"; then
        log_error "Failed to substitute bucket placeholder"
        return 1
    fi
    
    local var_args
    if ! var_args=$(get_terraform_var_args "$layer"); then
        restore_bucket_placeholder "$layer_dir"
        return 1
    fi
    
    cd "$layer_dir"
    
    local destroy_cmd="terraform destroy"
    
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        destroy_cmd="$destroy_cmd -auto-approve"
    fi
    
    # Add variable arguments
    while IFS= read -r arg; do
        if [[ -n "$arg" ]]; then
            destroy_cmd="$destroy_cmd $arg"
        fi
    done <<< "$var_args"
    
    log_debug "Running: $destroy_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $destroy_cmd"
        restore_bucket_placeholder "$layer_dir"
        return 0
    fi
    
    if ! eval "$destroy_cmd"; then
        log_error "Terraform destroy failed for $layer layer"
        restore_bucket_placeholder "$layer_dir"
        return 1
    fi
    
    log_success "Terraform destroy completed for $layer layer"
    
    # Restore placeholder
    restore_bucket_placeholder "$layer_dir"
}

terraform_output() {
    local layer="$1"
    local layer_dir="$2"
    local output_name="${3:-}"
    
    cd "$layer_dir"
    
    if [[ -n "$output_name" ]]; then
        terraform output -raw "$output_name" 2>/dev/null || echo ""
    else
        terraform output -json 2>/dev/null || echo "{}"
    fi
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
    echo "  Failed at: $failed_layer"
    echo
    echo "To recover:"
    echo "  1. Review the error messages above"
    echo "  2. Fix the issue in the $failed_layer layer"
    echo "  3. Re-run deployment for just the failed layer:"
    echo "     ./deploy.sh --layer $failed_layer deploy"
    echo
    
    case "$failed_layer" in
        "base")
            echo "Common base layer issues:"
            echo "  - Duplicate terraform provider configuration (check main.tf and versions.tf)"
            echo "  - Invalid AWS credentials or insufficient permissions"
            echo "  - VPC or subnet configuration issues"
            echo "  - S3 bucket does not exist or is not accessible"
            ;;
        "middleware")
            echo "Common middleware layer issues:"
            echo "  - Base layer not fully deployed"
            echo "  - Kubernetes authentication issues"
            echo "  - Helm chart repository not accessible"
            ;;
        "application")
            echo "Common application layer issues:"
            echo "  - Base or middleware layers not fully deployed"
            echo "  - ADO PAT secret value not set"
            echo "  - ECR repository name conflicts"
            ;;
    esac
    echo
    echo "To check layer status:"
    echo "  ./deploy.sh status"
    echo
    echo "To destroy and start over:"
    echo "  ./deploy.sh destroy"
    echo
}

get_layer_status() {
    local layer="$1"
    local layer_dir="$2"
    
    if [[ ! -d "$layer_dir" ]]; then
        echo "missing"
        return 0
    fi
    
    # Substitute bucket placeholder before checking state
    substitute_bucket_placeholder "$layer_dir" &>/dev/null
    
    cd "$layer_dir"
    
    # Check if Terraform is initialized
    if [[ ! -d ".terraform" ]]; then
        restore_bucket_placeholder "$layer_dir" &>/dev/null
        echo "not-initialized"
        return 0
    fi
    
    # Check if state exists
    if ! terraform show &>/dev/null; then
        restore_bucket_placeholder "$layer_dir" &>/dev/null
        echo "no-state"
        return 0
    fi
    
    # Check if there are any resources in state
    local resource_count
    resource_count=$(terraform state list 2>/dev/null | wc -l)
    
    # Restore placeholder
    restore_bucket_placeholder "$layer_dir" &>/dev/null
    
    if [[ "$resource_count" -eq 0 ]]; then
        echo "empty-state"
    else
        echo "deployed"
    fi
}

# =============================================================================
# Layer-Specific Operations
# =============================================================================

validate_layer_dependencies() {
    local layer="$1"
    
    if [[ "$FORCE" == "true" ]]; then
        log_warning "Skipping dependency checks due to --force flag"
        return 0
    fi
    
    case "$layer" in
        "base")
            # Base layer has no dependencies
            return 0
            ;;
        "middleware")
            local base_status
            base_status=$(get_layer_status "base" "$BASE_LAYER_DIR")
            if [[ "$base_status" != "deployed" ]]; then
                log_error "Middleware layer requires base layer to be deployed (status: $base_status)"
                log_error "Deploy base layer first or use --force to skip this check"
                return 1
            fi
            ;;
        "application")
            local base_status middleware_status
            base_status=$(get_layer_status "base" "$BASE_LAYER_DIR")
            middleware_status=$(get_layer_status "middleware" "$MIDDLEWARE_LAYER_DIR")
            
            if [[ "$base_status" != "deployed" ]]; then
                log_error "Application layer requires base layer to be deployed (status: $base_status)"
                return 1
            fi
            
            if [[ "$middleware_status" != "deployed" ]]; then
                log_error "Application layer requires middleware layer to be deployed (status: $middleware_status)"
                return 1
            fi
            ;;
        "config")
            # Config layer requires all infrastructure layers to be deployed
            local base_status middleware_status application_status
            base_status=$(get_layer_status "base" "$BASE_LAYER_DIR")
            middleware_status=$(get_layer_status "middleware" "$MIDDLEWARE_LAYER_DIR")
            application_status=$(get_layer_status "application" "$APPLICATION_LAYER_DIR")
            
            if [[ "$base_status" != "deployed" ]]; then
                log_error "Config layer requires base layer to be deployed (status: $base_status)"
                return 1
            fi
            
            if [[ "$middleware_status" != "deployed" ]]; then
                log_error "Config layer requires middleware layer to be deployed (status: $middleware_status)"
                return 1
            fi
            
            if [[ "$application_status" != "deployed" ]]; then
                log_error "Config layer requires application layer to be deployed (status: $application_status)"
                log_error "The application layer deploys the ExternalSecret resources that config layer configures"
                return 1
            fi
            ;;
        *)
            log_error "Unknown layer: $layer"
            return 1
            ;;
    esac
    
    return 0
}

# =============================================================================
# Config Layer Functions (Post-Deployment Configuration)
# =============================================================================

detect_cluster_name_from_tf() {
    local cluster_name=""
    
    # Try middleware layer first (most reliable)
    if [[ -d "$MIDDLEWARE_LAYER_DIR" ]]; then
        log_debug "Attempting to get cluster_name from middleware layer..."
        
        # Initialize if needed using the script's proper initialization
        if terraform_init "middleware" "$MIDDLEWARE_LAYER_DIR" &>/dev/null; then
            cluster_name=$(cd "$MIDDLEWARE_LAYER_DIR" && terraform output -raw cluster_name 2>/dev/null || echo "")
        fi
    fi
    
    # Fallback: Try base layer
    if [[ -z "$cluster_name" && -d "$BASE_LAYER_DIR" ]]; then
        log_debug "Attempting to get cluster_name from base layer..."
        
        if terraform_init "base" "$BASE_LAYER_DIR" &>/dev/null; then
            cluster_name=$(cd "$BASE_LAYER_DIR" && terraform output -raw cluster_name 2>/dev/null || echo "")
        fi
    fi
    
    # Final fallback: List EKS clusters in the region (assumes only one cluster)
    if [[ -z "$cluster_name" ]]; then
        log_debug "Fallback: Listing EKS clusters in region $AWS_REGION..."
        cluster_name=$(aws eks list-clusters --region "$AWS_REGION" --query 'clusters[0]' --output text 2>/dev/null || echo "")
        
        if [[ -n "$cluster_name" && "$cluster_name" != "None" ]]; then
            log_info "Detected cluster from AWS EKS: $cluster_name"
        fi
    fi
    
    echo "$cluster_name"
}

get_eso_config_from_tf() {
    local output_name="$1"
    local default_value="$2"
    local value=""
    
    # Try to get from middleware layer
    if [[ -d "$MIDDLEWARE_LAYER_DIR" ]]; then
        log_debug "Attempting to get $output_name from middleware layer..."
        
        # Initialize if needed
        if terraform_init "middleware" "$MIDDLEWARE_LAYER_DIR" &>/dev/null; then
            value=$(cd "$MIDDLEWARE_LAYER_DIR" && terraform output -raw "$output_name" 2>/dev/null || echo "")
        fi
    fi
    
    # Use default if not found
    if [[ -z "$value" ]]; then
        log_debug "Using default value for $output_name: $default_value"
        value="$default_value"
    fi
    
    echo "$value"
}

configure_kubectl_for_cluster() {
    local cluster_name="$1"
    local region="$2"
    
    log_info "Configuring kubectl for cluster: $cluster_name (region: $region)"
    
    if ! aws eks update-kubeconfig \
        --name "$cluster_name" \
        --region "$region" \
        --kubeconfig "${KUBECONFIG:-$HOME/.kube/config}"; then
        log_error "Failed to update kubeconfig"
        return 1
    fi
    
    # Verify kubectl access
    if ! kubectl get nodes &>/dev/null; then
        log_error "Cannot access cluster with kubectl"
        return 1
    fi
    
    log_success "kubectl configured successfully"
    return 0
}

create_cluster_secret_store() {
    local region="$1"
    
    log_info "Creating ClusterSecretStore for AWS Secrets Manager..."
    
    # Get ESO configuration from Terraform outputs
    local eso_namespace=$(get_eso_config_from_tf "eso_namespace" "external-secrets-system")
    local eso_sa_name=$(get_eso_config_from_tf "eso_service_account_name" "external-secrets")
    local css_name=$(get_eso_config_from_tf "cluster_secret_store_name" "aws-secrets-manager")
    
    log_info "ESO Configuration:"
    log_info "  Namespace: $eso_namespace"
    log_info "  ServiceAccount: $eso_sa_name"
    log_info "  ClusterSecretStore: $css_name"
    
    # Create the ClusterSecretStore manifest
    cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: ${css_name}
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
    
    if [[ $? -eq 0 ]]; then
        log_success "ClusterSecretStore created successfully"
        
        # Wait for the ClusterSecretStore to be ready
        log_info "Waiting for ClusterSecretStore to become ready..."
        local max_attempts=30
        local attempt=0
        
        while [[ $attempt -lt $max_attempts ]]; do
            local status=$(kubectl get clustersecretstore "$css_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            if [[ "$status" == "True" ]]; then
                log_success "ClusterSecretStore is ready"
                return 0
            fi
            
            attempt=$((attempt + 1))
            sleep 2
        done
        
        log_warning "ClusterSecretStore may not be ready yet (check with: kubectl get clustersecretstore $css_name)"
        return 0
    else
        log_error "Failed to create ClusterSecretStore"
        return 1
    fi
}

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
        read -sp "Enter Azure DevOps PAT Token: " ADO_PAT
        echo ""
    else
        log_info "Using ADO_PAT from environment variable"
    fi
    
    # Check for ADO_ORG_URL environment variable first, then prompt
    if [[ -z "${ADO_ORG_URL:-}" ]]; then
        log_info "ADO_ORG_URL environment variable not set"
        read -p "Enter Azure DevOps Organization URL (e.g., https://dev.azure.com/myorg): " ADO_ORG_URL
    else
        log_info "Using ADO_ORG_URL from environment variable"
    fi
    
    if [[ -z "$ADO_ORG_URL" || -z "$ADO_PAT" ]]; then
        log_error "Organization URL and PAT token are required"
        log_error "Set via environment variables: ADO_PAT and ADO_ORG_URL"
        return 1
    fi
    
    log_success "Credentials received"
    return 0
}

inject_ado_secret() {
    local region="$1"
    local cluster_name="$2"
    
    # Default behavior: DO NOT update the secret unless explicitly requested
    if [[ "${UPDATE_ADO_SECRET:-false}" != "true" ]]; then
        log_info "Skipping ADO secret update (use --update-ado-secret to update credentials)"
        log_info "The Terraform-managed secret container exists and is configured"
        return 0
    fi
    
    log_info "Updating ADO PAT credentials in Terraform-managed secret..."
    
    # Get the secret name from application layer tfvars or use default
    # The secret name is defined in application layer variables with default "ado-agent-pat"
    local secret_name="ado-agent-pat"
    
    # Try to read from tfvars if it exists
    if [[ -f "$APPLICATION_LAYER_DIR/terraform.tfvars" ]]; then
        local tfvars_secret=$(grep "^ado_pat_secret_name" "$APPLICATION_LAYER_DIR/terraform.tfvars" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "")
        if [[ -n "$tfvars_secret" ]]; then
            secret_name="$tfvars_secret"
            log_info "Using secret name from tfvars: $secret_name"
        else
            log_info "Using default secret name: $secret_name"
        fi
    else
        log_info "Using default secret name: $secret_name"
    fi
    
    # Verify the secret exists (created by Terraform)
    if ! aws secretsmanager describe-secret \
        --secret-id "$secret_name" \
        --region "$region" &>/dev/null; then
        log_error "Secret '$secret_name' does not exist in AWS Secrets Manager"
        log_error "Ensure the application layer has been deployed first (creates the secret container)"
        return 1
    fi
    
    log_success "Found Terraform-managed secret: $secret_name"
    
    # Prompt for credentials if not already set
    if ! prompt_for_ado_credentials; then
        return 1
    fi
    
    # Extract organization name from URL (remove https://dev.azure.com/ prefix and trailing slash)
    local org_name=$(echo "$ADO_ORG_URL" | sed 's|https://dev.azure.com/||' | sed 's|/$||')
    
    # Update the existing Terraform-managed secret with actual credentials
    # Use the same structure as Terraform expects (personalAccessToken, organization, adourl)
    log_info "Updating secret content with provided credentials..."
    
    local secret_json=$(cat <<EOF
{
  "personalAccessToken": "$ADO_PAT",
  "organization": "$org_name",
  "adourl": "$ADO_ORG_URL"
}
EOF
)
    
    if aws secretsmanager put-secret-value \
        --secret-id "$secret_name" \
        --secret-string "$secret_json" \
        --region "$region" &>/dev/null; then
        log_success "Secret content updated successfully: $secret_name"
        log_info "  Organization: $org_name"
        log_info "  URL: $ADO_ORG_URL"
    else
        log_error "Failed to update secret content: $secret_name"
        return 1
    fi
    
    # Verify the ExternalSecret resource exists
    log_info "Verifying ExternalSecret configuration..."
    if kubectl get externalsecret -n ado-agents &>/dev/null; then
        log_success "ExternalSecret resources found in ado-agents namespace"
        
        # Trigger a refresh if possible
        log_info "ExternalSecrets will sync automatically within ~1 minute"
        log_info "Check sync status: kubectl get externalsecret -n ado-agents"
    else
        log_warning "No ExternalSecret resources found"
        log_warning "Ensure application layer Helm chart has been deployed"
    fi
    
    return 0
}

deploy_config_layer() {
    log_info "Deploying config layer (post-deployment configuration)..."
    
    # Check prerequisites
    for cmd in aws kubectl; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    # Detect cluster name from Terraform outputs
    local cluster_name=$(detect_cluster_name_from_tf)
    if [[ -z "$cluster_name" ]]; then
        log_error "Could not detect cluster name from Terraform outputs"
        log_error "Make sure base and middleware layers are deployed"
        return 1
    fi
    
    log_info "Detected cluster: $cluster_name"
    
    # Get ESO configuration for later use in messages
    local css_name=$(get_eso_config_from_tf "cluster_secret_store_name" "aws-secrets-manager")
    local ado_namespace=$(get_eso_config_from_tf "ado_agents_namespace" "ado-agents")
    local ado_secret=$(get_eso_config_from_tf "ado_secret_name" "ado-pat")
    
    # Configure kubectl
    if ! configure_kubectl_for_cluster "$cluster_name" "$AWS_REGION"; then
        return 1
    fi
    
    # Create ClusterSecretStore
    if ! create_cluster_secret_store "$AWS_REGION"; then
        log_warning "ClusterSecretStore creation had issues, but continuing..."
    fi
    
    # Inject ADO secret (only if --update-ado-secret flag is set)
    log ""
    if ! inject_ado_secret "$AWS_REGION" "$cluster_name"; then
        log_warning "ADO secret update failed or was skipped"
        if [[ "${UPDATE_ADO_SECRET:-false}" == "true" ]]; then
            log_warning "To retry, run: ./deploy.sh --layer config --update-ado-secret deploy"
        else
            log_info "To update credentials, run: ./deploy.sh --layer config --update-ado-secret deploy"
        fi
    fi
    
    log_success "Config layer deployment completed"
    
    # Show next steps with dynamic values
    log ""
    log "Next Steps:"
    log "  1. Verify ClusterSecretStore:"
    log "     kubectl get clustersecretstore $css_name"
    log ""
    log "  2. Update ADO PAT secret (if needed):"
    log "     export ADO_PAT='your-pat-token'"
    log "     export ADO_ORG_URL='https://dev.azure.com/your-org'"
    log "     ./deploy.sh --layer config --update-ado-secret deploy"
    log ""
    log "  3. Verify ExternalSecret syncs:"
    log "     kubectl get externalsecret -n $ado_namespace"
    log "     kubectl get secret -n $ado_namespace $ado_secret"
    log ""
    log "  4. Monitor KEDA and agent pods:"
    log "     kubectl get scaledobject -n $ado_namespace"
    log "     kubectl get pods -n $ado_namespace -w"
    log ""
    
    return 0
}

deploy_layer() {
    local layer="$1"
    local layer_dir="$2"
    
    log "Starting deployment of $layer layer..."
    
    # Special handling for config layer (doesn't use Terraform)
    if [[ "$layer" == "config" ]]; then
        deploy_config_layer
        return $?
    fi
    
    # Validate layer directory
    if ! validate_layer_directory "$layer" "$layer_dir"; then
        return 1
    fi
    
    # Check dependencies
    if ! validate_layer_dependencies "$layer"; then
        return 1
    fi
    
    # Initialize Terraform
    if ! terraform_init "$layer" "$layer_dir"; then
        return 1
    fi
    
    # Validate configuration
    if ! terraform_validate "$layer" "$layer_dir"; then
        return 1
    fi
    
    # Create temporary plan file
    local plan_file="$layer_dir/terraform-deploy-$layer.tfplan"
    
    # Plan changes with output file
    local plan_exitcode=0
    terraform_plan "$layer" "$layer_dir" "$plan_file" || plan_exitcode=$?
    
    case $plan_exitcode in
        0)
            log_success "$layer layer is up to date"
            # Still run post-deployment validation to ensure k8s resources are deployed
            validate_layer_deployment "$layer" "$layer_dir"
            return 0
            ;;
        1)
            return 1  # Plan failed
            ;;
        2)
            # Changes detected, proceed with confirmation and apply
            ;;
        *)
            log_error "Unexpected plan result for $layer layer"
            return 1
            ;;
    esac
    
    # Confirm before applying (unless auto-approved or dry-run)
    if [[ "$DRY_RUN" != "true" && "$AUTO_APPROVE" != "true" ]]; then
        echo
        if ! confirm_action "Apply the planned changes to $layer layer?"; then
            log_info "Deployment cancelled by user"
            # Clean up plan file
            rm -f "$plan_file"
            return 1
        fi
    fi
    
    # Apply changes using the plan file
    if ! terraform_apply "$layer" "$layer_dir" "$plan_file"; then
        return 1
    fi
    
    # Post-deployment validation
    validate_layer_deployment "$layer" "$layer_dir"
    
    log_success "$layer layer deployment completed"
    return 0
}

validate_layer_deployment() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Validating $layer layer deployment..."
    
    case "$layer" in
        "base")
            validate_base_layer_deployment "$layer_dir"
            ;;
        "middleware")
            validate_middleware_layer_deployment "$layer_dir"
            ;;
        "application")
            validate_application_layer_deployment "$layer_dir"
            ;;
    esac
}

validate_base_layer_deployment() {
    local layer_dir="$1"
    
    log_debug "Validating base layer deployment"
    
    # Check if cluster is accessible
    local cluster_name
    cluster_name=$(terraform_output "base" "$layer_dir" "cluster_name")
    
    if [[ -n "$cluster_name" ]]; then
        log_info "EKS cluster: $cluster_name"
        
        # Configure kubectl with cluster name as alias
        configure_kubectl_alias "$cluster_name" "$AWS_REGION" "$cluster_name"
    fi
}

deploy_cluster_autoscaler() {
    local layer_dir="$1"
    
    log_info "Deploying Cluster Autoscaler..."
    
    # Get cluster name - try multiple methods
    local cluster_name=""
    
    # Method 1: Try from terraform output (if available)
    cluster_name=$(terraform_output "base" "$BASE_LAYER_DIR" "cluster_name" 2>/dev/null || echo "")
    
    # Method 2: If that failed, detect from kubectl context
    if [[ -z "$cluster_name" ]]; then
        cluster_name=$(kubectl config current-context 2>/dev/null | cut -d'/' -f2 2>/dev/null || echo "")
        if [[ -n "$cluster_name" ]]; then
            log_debug "Detected cluster name from kubectl context: $cluster_name"
        fi
    fi
    
    # Method 3: List EKS clusters in region
    if [[ -z "$cluster_name" ]]; then
        cluster_name=$(aws eks list-clusters --region "${AWS_REGION}" --query 'clusters[0]' --output text 2>/dev/null || echo "")
        if [[ -n "$cluster_name" && "$cluster_name" != "None" ]]; then
            log_debug "Detected cluster name from AWS: $cluster_name"
        fi
    fi
    
    if [[ -z "$cluster_name" ]]; then
        log_warning "Could not determine cluster name - skipping cluster autoscaler deployment"
        return 0
    fi
    
    # Check if IAM role exists for cluster autoscaler
    local cluster_autoscaler_role_arn=""
    local expected_role_name="${cluster_name}-cluster-autoscaler-role"
    
    # Try to get role ARN from AWS IAM
    cluster_autoscaler_role_arn=$(aws iam get-role --role-name "$expected_role_name" --query 'Role.Arn' --output text 2>/dev/null || echo "")
    
    # If role doesn't exist, autoscaler is disabled
    if [[ -z "$cluster_autoscaler_role_arn" || "$cluster_autoscaler_role_arn" == "None" ]]; then
        log_info "Cluster autoscaler IAM role not found ($expected_role_name) - skipping deployment"
        log_info "To enable cluster autoscaler, set enable_cluster_autoscaler = true in base/terraform.tfvars"
        return 0
    fi
    
    local aws_region="${AWS_REGION}"
    
    # Use version 1.30.0 which supports EKS 1.30+
    local cluster_autoscaler_version="v1.30.0"
    
    log_info "Cluster Autoscaler configuration:"
    log_info "  Cluster: $cluster_name"
    log_info "  Role ARN: $cluster_autoscaler_role_arn"
    log_info "  Region: $aws_region"
    log_info "  Version: $cluster_autoscaler_version"
    
    # Check if cluster autoscaler manifest exists
    local manifest_template="$layer_dir/cluster-autoscaler.yaml"
    if [[ ! -f "$manifest_template" ]]; then
        log_error "Cluster autoscaler manifest not found: $manifest_template"
        return 1
    fi
    
    # Create temporary manifest with substituted values
    local temp_manifest
    temp_manifest=$(mktemp)
    
    sed -e "s|CLUSTER_AUTOSCALER_ROLE_ARN_PLACEHOLDER|${cluster_autoscaler_role_arn}|g" \
        -e "s|CLUSTER_NAME_PLACEHOLDER|${cluster_name}|g" \
        -e "s|AWS_REGION_PLACEHOLDER|${aws_region}|g" \
        -e "s|CLUSTER_AUTOSCALER_VERSION_PLACEHOLDER|${cluster_autoscaler_version}|g" \
        "$manifest_template" > "$temp_manifest"
    
    # Apply the manifest
    if kubectl apply -f "$temp_manifest"; then
        log_success "Cluster autoscaler deployed successfully"
        
        # Wait for deployment to be ready
        log_info "Waiting for cluster autoscaler deployment to be ready..."
        if kubectl wait --for=condition=available --timeout=180s deployment/cluster-autoscaler -n kube-system 2>/dev/null; then
            log_success "Cluster autoscaler is running"
        else
            log_warning "Cluster autoscaler deployment timeout - check manually with: kubectl get deployment -n kube-system cluster-autoscaler"
        fi
    else
        log_error "Failed to deploy cluster autoscaler"
        rm -f "$temp_manifest"
        return 1
    fi
    
    # Clean up temp file
    rm -f "$temp_manifest"
    
    return 0
}

validate_middleware_layer_deployment() {
    local layer_dir="$1"
    
    log_debug "Validating middleware layer deployment"
    
    # Check KEDA deployment
    if kubectl get deployment -n keda-system keda-operator &>/dev/null; then
        log_success "KEDA operator is deployed"
    else
        log_warning "KEDA operator not found"
    fi
    
    # Check External Secrets Operator
    if kubectl get deployment -n external-secrets-system external-secrets &>/dev/null; then
        log_success "External Secrets Operator is deployed"
    else
        log_warning "External Secrets Operator not found"
    fi
    
    # Deploy cluster autoscaler if enabled
    deploy_cluster_autoscaler "$layer_dir"
    
    # Check Cluster Autoscaler deployment
    if kubectl get deployment -n kube-system cluster-autoscaler &>/dev/null; then
        log_success "Cluster autoscaler is deployed"
    else
        log_info "Cluster autoscaler not deployed (may be disabled or failed)"
    fi
}

validate_application_layer_deployment() {
    local layer_dir="$1"
    
    log_debug "Validating application layer deployment"
    
    # Check Helm release
    local helm_release_name
    helm_release_name=$(terraform_output "application" "$layer_dir" "helm_release.name" 2>/dev/null || echo "")
    
    if [[ -n "$helm_release_name" ]]; then
        local helm_namespace
        helm_namespace=$(terraform_output "application" "$layer_dir" "helm_release.namespace" 2>/dev/null || echo "")
        
        if helm status "$helm_release_name" -n "$helm_namespace" &>/dev/null; then
            log_success "Helm release $helm_release_name is deployed"
        else
            log_warning "Helm release $helm_release_name not found"
        fi
    fi
}

destroy_layer() {
    local layer="$1"
    local layer_dir="$2"
    
    log "Starting destruction of $layer layer..."
    
    # Special handling for config layer
    if [[ "$layer" == "config" ]]; then
        log_info "Config layer cleanup (manual steps required):"
        log_info "  1. Delete ClusterSecretStore: kubectl delete clustersecretstore aws-secrets-manager"
        log_info "Config layer destroy is informational only"
        return 0
    fi
    
    # Check if layer exists and has resources
    local status
    status=$(get_layer_status "$layer" "$layer_dir")
    
    case "$status" in
        "missing"|"not-initialized"|"no-state"|"empty-state")
            log_info "$layer layer has no resources to destroy (status: $status)"
            return 0
            ;;
        "deployed")
            log_info "$layer layer has resources that will be destroyed"
            ;;
        *)
            log_warning "Unknown status for $layer layer: $status"
            ;;
    esac
    
    # Confirm before destroying (unless auto-approved or dry-run)
    if [[ "$DRY_RUN" != "true" && "$AUTO_APPROVE" != "true" ]]; then
        if ! confirm_action "Destroy $layer layer resources?"; then
            log_info "Destruction cancelled by user"
            return 1
        fi
    fi
    
    # Destroy resources
    if ! terraform_destroy "$layer" "$layer_dir"; then
        return 1
    fi
    
    log_success "$layer layer destruction completed"
}

# =============================================================================
# Main Commands
# =============================================================================

cmd_deploy() {
    # Get layer configuration using helper
    local layer_config
    layer_config=$(get_layers_and_dirs "$TARGET_LAYER" false) || exit 1
    
    local layers=()
    local layer_dirs=()
    
    while IFS='|' read -r layer layer_dir; do
        layers+=("$layer")
        layer_dirs+=("$layer_dir")
    done <<< "$layer_config"
    
    log "Starting deployment of ${#layers[@]} layer(s)..."
    
    # Check all layer directories first
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
        if ! validate_layer_directory "$layer" "$layer_dir"; then
            log_error "Layer validation failed: $layer"
            exit 1
        fi
    done
    
    # Deploy layers in order
    local failed_layers=()
    local successful_layers=()
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
        if ! deploy_layer "$layer" "$layer_dir"; then
            log_error "Failed to deploy $layer layer"
            failed_layers+=("$layer")
            
            # Show deployment status so far
            echo
            echo "================================"
            echo "DEPLOYMENT INTERRUPTED"
            echo "================================"
            echo
            if [[ ${#successful_layers[@]} -gt 0 ]]; then
                echo "Successfully deployed:"
                for success in "${successful_layers[@]}"; do
                    echo "  ✓ $success"
                done
                echo
            fi
            echo "Failed at:"
            echo "  ✗ $layer"
            echo
            if [[ $((i+1)) -lt ${#layers[@]} ]]; then
                echo "Not yet deployed:"
                for ((j=i+1; j<${#layers[@]}; j++)); do
                    echo "  ○ ${layers[$j]}"
                done
                echo
            fi
            
            # Always exit on error - no option to continue
            log_error "Deployment failed at $layer layer"
            show_recovery_guidance "$layer" "${successful_layers[@]}"
            exit 1
        else
            successful_layers+=("$layer")
        fi
    done
    
    # Report results
    if [[ ${#failed_layers[@]} -eq 0 ]]; then
        echo
        echo "================================"
        echo "DEPLOYMENT SUCCESSFUL"
        echo "================================"
        echo
        
        if [[ -n "$TARGET_LAYER" ]]; then
            log_success "Target layer deployed successfully: $TARGET_LAYER"
            show_layer_list "Deployed" "✓" "${successful_layers[@]}"
            
            # Show skipped layers
            calculate_skipped_layers successful_layers
        else
            log_success "All layers deployed successfully"
            show_layer_list "Deployed" "✓" "${successful_layers[@]}"
        fi
        
        # Show post-deployment information
        show_deployment_info
        
    else
        echo
        echo "================================"
        echo "DEPLOYMENT COMPLETED WITH ERRORS"
        echo "================================"
        echo
        show_layer_list "Successfully deployed" "✓" "${successful_layers[@]}"
        show_layer_list "Failed layers" "✗" "${failed_layers[@]}"
        show_recovery_guidance "${failed_layers[0]}" "${successful_layers[@]}"
        exit 1
    fi
}

cmd_plan() {
    # Get layer configuration using helper
    local layer_config
    layer_config=$(get_layers_and_dirs "$TARGET_LAYER" false) || exit 1
    
    local layers=()
    local layer_dirs=()
    
    while IFS='|' read -r layer layer_dir; do
        layers+=("$layer")
        layer_dirs+=("$layer_dir")
    done <<< "$layer_config"
    
    log "Showing deployment plan for ${#layers[@]} layer(s)..."
    
    local planned_layers=()
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
        # Skip config layer - it doesn't use Terraform
        if [[ "$layer" == "config" ]]; then
            log_info "Skipping plan for config layer (no Terraform)"
            continue
        fi
        
        echo
        log "Planning $layer layer..."
        echo "----------------------------------------"
        
        if ! validate_layer_directory "$layer" "$layer_dir"; then
            log_error "Layer validation failed: $layer"
            continue
        fi
        
        if ! terraform_init "$layer" "$layer_dir"; then
            log_error "Terraform init failed: $layer"
            continue
        fi
        
        if ! terraform_validate "$layer" "$layer_dir"; then
            log_error "Terraform validation failed: $layer"
            continue
        fi
        
        terraform_plan "$layer" "$layer_dir"
        planned_layers+=("$layer")
        echo
    done
    
    # Show summary if in layer mode
    if [[ -n "$TARGET_LAYER" ]]; then
        echo
        echo "================================"
        echo "PLAN MODE: LAYER $TARGET_LAYER"
        echo "================================"
        echo
        log_info "Planned layer: $TARGET_LAYER"
        
        # Show skipped layers
        calculate_skipped_layers planned_layers
    fi
}

cmd_validate() {
    # Get layer configuration using helper
    local layer_config
    layer_config=$(get_layers_and_dirs "$TARGET_LAYER" false) || exit 1
    
    local layers=()
    local layer_dirs=()
    
    while IFS='|' read -r layer layer_dir; do
        layers+=("$layer")
        layer_dirs+=("$layer_dir")
    done <<< "$layer_config"
    
    log "Validating ${#layers[@]} layer(s)..."
    
    local validation_errors=()
    local validated_layers=()
    
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
        # Skip config layer - it doesn't use Terraform
        if [[ "$layer" == "config" ]]; then
            log_info "Skipping validation for config layer (no Terraform)"
            log_success "$layer layer validation passed (runtime checks only)"
            validated_layers+=("$layer")
            continue
        fi
        
        log_info "Validating $layer layer..."
        
        if ! validate_layer_directory "$layer" "$layer_dir"; then
            validation_errors+=("$layer: directory validation failed")
            continue
        fi
        
        if ! terraform_init "$layer" "$layer_dir"; then
            validation_errors+=("$layer: terraform init failed")
            continue
        fi
        
        if ! terraform_validate "$layer" "$layer_dir"; then
            validation_errors+=("$layer: terraform validation failed")
            continue
        fi
        
        log_success "$layer layer validation passed"
        validated_layers+=("$layer")
    done
    
    # Validate Helm chart
    if [[ -d "$HELM_CHART_DIR" ]]; then
        log_info "Validating Helm chart..."
        if helm lint "$HELM_CHART_DIR" &>/dev/null; then
            log_success "Helm chart validation passed"
        else
            validation_errors+=("helm: chart validation failed")
        fi
    fi
    
    # Report results
    if [[ ${#validation_errors[@]} -eq 0 ]]; then
        echo
        if [[ -n "$TARGET_LAYER" ]]; then
            log_success "Target layer validation passed: $TARGET_LAYER"
            
            # Show skipped layers
            calculate_skipped_layers validated_layers
        else
            log_success "All validations passed"
        fi
    else
        log_error "Validation errors found:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        exit 1
    fi
}

cmd_destroy() {
    # Get layer configuration using helper (reverse order for destroy)
    local layer_config
    layer_config=$(get_layers_and_dirs "$TARGET_LAYER" true) || exit 1
    
    local layers=()
    local layer_dirs=()
    
    while IFS='|' read -r layer layer_dir; do
        layers+=("$layer")
        layer_dirs+=("$layer_dir")
    done <<< "$layer_config"
    
    log_warning "This will destroy ${#layers[@]} layer(s) in reverse order: ${layers[*]}"
    log_warning "This action cannot be undone!"
    
    if [[ "$AUTO_APPROVE" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        log_warning "You are about to destroy infrastructure resources."
        log_warning "This will DELETE all resources managed by Terraform in these layers."
        log_warning "Make sure you have backups of any important data."
        echo
        
        if ! confirm_action "Are you absolutely sure you want to proceed?"; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    # Destroy layers in reverse order
    local failed_layers=()
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
        if ! destroy_layer "$layer" "$layer_dir"; then
            log_error "Failed to destroy $layer layer"
            failed_layers+=("$layer")
            
            # Always exit on error - no option to continue
            log_error "Destruction halted at $layer layer"
            log_error "Failed to destroy layers: ${failed_layers[*]}"
            exit 1
        fi
    done
    
    # Report results
    if [[ ${#failed_layers[@]} -eq 0 ]]; then
        echo
        if [[ -n "$TARGET_LAYER" ]]; then
            log_success "Target layer destroyed successfully: $TARGET_LAYER"
            
            # Show skipped layers
            local destroyed_layers=("$TARGET_LAYER")
            calculate_skipped_layers destroyed_layers
        else
            log_success "All layers destroyed successfully"
        fi
    else
        log_error "Destruction failed for layers: ${failed_layers[*]}"
        exit 1
    fi
}

cmd_status() {
    local layers=("base" "middleware" "application")
    local layer_dirs=("$BASE_LAYER_DIR" "$MIDDLEWARE_LAYER_DIR" "$APPLICATION_LAYER_DIR")
    
    log "Infrastructure Status Report"
    echo "============================="
    echo
    
    # Show AWS context
    local aws_account aws_region caller_arn
    aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    aws_region=$(aws configure get region 2>/dev/null || echo "$AWS_REGION")
    caller_arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "unknown")
    
    echo "AWS Context:"
    echo "  Account: $aws_account"
    echo "  Region: $aws_region"
    echo "  Identity: $caller_arn"
    echo
    
    # Show layer status
    echo "Layer Status:"
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        local status
        status=$(get_layer_status "$layer" "$layer_dir")
        
        local status_color=""
        case "$status" in
            "deployed") status_color="$GREEN" ;;
            "missing"|"not-initialized"|"no-state"|"empty-state") status_color="$RED" ;;
            *) status_color="$YELLOW" ;;
        esac
        
        echo -e "  ${layer}: ${status_color}${status}${NC}"
        
        # Show additional details for deployed layers
        if [[ "$status" == "deployed" ]]; then
            case "$layer" in
                "base")
                    local cluster_name
                    cluster_name=$(terraform_output "$layer" "$layer_dir" "cluster_name")
                    if [[ -n "$cluster_name" ]]; then
                        echo "    Cluster: $cluster_name"
                    fi
                    ;;
                "middleware")
                    local eso_namespace keda_namespace
                    eso_namespace=$(terraform_output "$layer" "$layer_dir" "external_secrets_namespace" 2>/dev/null)
                    keda_namespace=$(terraform_output "$layer" "$layer_dir" "keda_namespace" 2>/dev/null)
                    if [[ -n "$eso_namespace" ]]; then
                        echo "    ESO Namespace: $eso_namespace"
                    fi
                    if [[ -n "$keda_namespace" ]]; then
                        echo "    KEDA Namespace: $keda_namespace"
                    fi
                    ;;
                "application")
                    local helm_release_name helm_namespace
                    helm_release_name=$(terraform_output "$layer" "$layer_dir" "helm_release.name" 2>/dev/null)
                    helm_namespace=$(terraform_output "$layer" "$layer_dir" "helm_release.namespace" 2>/dev/null)
                    if [[ -n "$helm_release_name" && -n "$helm_namespace" ]]; then
                        echo "    Helm Release: $helm_release_name (namespace: $helm_namespace)"
                    fi
                    ;;
            esac
        fi
    done
    echo
    
    # Show Helm chart status if available
    if [[ -d "$HELM_CHART_DIR" ]]; then
        echo "Helm Chart:"
        echo "  Chart Directory: $HELM_CHART_DIR"
        if [[ -f "$HELM_CHART_DIR/Chart.yaml" ]]; then
            local chart_version chart_name
            chart_version=$(grep '^version:' "$HELM_CHART_DIR/Chart.yaml" | awk '{print $2}' 2>/dev/null || echo "unknown")
            chart_name=$(grep '^name:' "$HELM_CHART_DIR/Chart.yaml" | awk '{print $2}' 2>/dev/null || echo "unknown")
            echo "  Chart Name: $chart_name"
            echo "  Chart Version: $chart_version"
        fi
        echo
    fi
    
    # Show dependency status
    echo "Dependencies:"
    for tool in aws terraform helm kubectl; do
        if command -v "$tool" &> /dev/null; then
            local version
            case "$tool" in
                "aws") version=$(aws --version 2>&1 | cut -d' ' -f1) ;;
                "terraform") version="terraform $(terraform version -json | jq -r '.terraform_version')" ;;
                "helm") version="helm $(helm version --short 2>/dev/null | cut -d: -f2 | tr -d ' ')" ;;
                "kubectl") version="kubectl $(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion | cut -d: -f2 | tr -d ' ')" ;;
            esac
            echo -e "  ${tool}: ${GREEN}${version}${NC}"
        else
            echo -e "  ${tool}: ${RED}not installed${NC}"
        fi
    done
}

show_deployment_info() {
    echo
    log_success "Deployment completed successfully!"
    echo
    echo "Next Steps:"
    echo "==========="
    echo
    
    # Get cluster information
    local cluster_name
    cluster_name=$(terraform_output "base" "$BASE_LAYER_DIR" "cluster_name" 2>/dev/null || echo "")
    
    if [[ -n "$cluster_name" ]]; then
        echo "1. Configure kubectl to access your cluster:"
        echo "   aws eks update-kubeconfig --region $AWS_REGION --name $cluster_name"
        echo
        
        echo "2. Verify cluster connectivity:"
        echo "   kubectl cluster-info"
        echo "   kubectl get nodes"
        echo
        
        echo "3. Check ADO agent deployment:"
        echo "   kubectl get pods -n ado-agents"
        echo "   kubectl get scaledobjects -n ado-agents"
        echo
        
        echo "4. Monitor agent scaling:"
        echo "   kubectl logs -n keda-system deployment/keda-operator"
        echo "   kubectl describe scaledobject ado-agent -n ado-agents"
        echo
    fi
    
    echo "5. Configure Azure DevOps:"
    echo "   - Create agent pools matching your configuration"
    echo "   - Update your pipelines to use the new agent pools"
    echo
    
    echo "6. Update ADO PAT secret (if needed):"
    echo "   aws secretsmanager update-secret --secret-id ado-agent-pat \\"
    echo "     --secret-string '{\"personalAccessToken\":\"NEW_PAT\",\"organization\":\"YOUR_ORG\",\"adourl\":\"YOUR_URL\"}'"
    echo
    
    echo "For detailed operational information, see the outputs from each layer:"
    echo "  terraform output -json"
    echo
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_arguments() {
    local command=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --backend-config)
                BACKEND_CONFIG_FILE="$2"
                shift 2
                ;;
            --var-file)
                VAR_FILE="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --update-ado-secret)
                UPDATE_ADO_SECRET=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            deploy|plan|validate|destroy|status)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    log_error "Multiple commands specified: $command, $1"
                    exit 1
                fi
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set default command if none specified
    if [[ -z "$command" ]]; then
        command="$DEFAULT_COMMAND"
    fi
    
    echo "$command"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local command
    
    # Parse arguments - this sets global variables (TARGET_LAYER, AUTO_APPROVE, etc.)
    # and returns the command. We use a temporary file to avoid subshell issues.
    local temp_cmd_file="/tmp/deploy_cmd_$$"
    parse_arguments "$@" > "$temp_cmd_file"
    command=$(cat "$temp_cmd_file")
    rm -f "$temp_cmd_file"
    
    # Show configuration in verbose mode
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Configuration:"
        log_debug "  Command: $command"
        log_debug "  Target Layer: ${TARGET_LAYER:-all}"
        log_debug "  AWS Region: $AWS_REGION"
        log_debug "  Auto Approve: $AUTO_APPROVE"
        log_debug "  Dry Run: $DRY_RUN"
        log_debug "  Verbose: $VERBOSE"
        log_debug "  Force: $FORCE"
        log_debug "  Backend Config: ${BACKEND_CONFIG_FILE:-default}"
        log_debug "  Variables File: ${VAR_FILE:-default}"
        echo
    fi
    
    # Check prerequisites (skip for status and help)
    if [[ "$command" != "status" ]]; then
        check_prerequisites
    fi
    
    # Execute command
    case "$command" in
        deploy)
            cmd_deploy
            ;;
        plan)
            cmd_plan
            ;;
        validate)
            cmd_validate
            ;;
        destroy)
            cmd_destroy
            ;;
        status)
            cmd_status
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi