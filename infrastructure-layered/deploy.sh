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
#   --layer LAYER        Deploy specific layer only (base|middleware|application)
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
readonly HELM_CHART_DIR="$LAYERS_DIR/helm/ado-agent-cluster"

# Default configuration
DEFAULT_REGION="us-east-1"
DEFAULT_COMMAND="deploy"
AUTO_APPROVE=false
DRY_RUN=false
VERBOSE=false
FORCE=false
TARGET_LAYER=""
BACKEND_CONFIG_FILE=""
VAR_FILE=""
AWS_REGION="$DEFAULT_REGION"

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
    --layer LAYER        Target specific layer only (base|middleware|application)
    --auto-approve       Skip interactive confirmation prompts
    --dry-run           Show actions without executing them
    --backend-config     Path to backend configuration file
    --var-file FILE     Path to terraform variables file
    --region REGION     AWS region (default: us-east-1)
    --verbose           Enable verbose debug output
    --force             Skip safety checks and dependencies (dangerous)
    --help              Show this help message

EXAMPLES:
    # Deploy entire stack interactively
    $0 deploy

    # Deploy only base layer with auto-approval
    $0 --layer base --auto-approve deploy

    # Show deployment plan for all layers
    $0 plan

    # Validate configuration without deploying
    $0 validate

    # Deploy with custom backend config
    $0 --backend-config backend.hcl deploy

    # Deploy with custom variables file
    $0 --var-file production.tfvars deploy

    # Check status of all layers
    $0 status

    # Destroy in dry-run mode
    $0 --dry-run destroy

LAYER DEPENDENCIES:
    base → middleware → application

    Each layer depends on outputs from the previous layer via remote state.
    Layers must be deployed in order and destroyed in reverse order.

PREREQUISITES:
    • AWS CLI configured with appropriate permissions
    • Terraform >= 1.5 installed
    • Helm >= 3.10 installed  
    • kubectl configured (for post-deployment validation)
    • S3 bucket for remote state storage
    • DynamoDB table for state locking (recommended)

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
    for tool in aws terraform helm kubectl; do
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
    
    # Check AWS region
    local current_region
    current_region=$(aws configure get region || echo "")
    if [[ -z "$current_region" ]]; then
        log_warning "No default AWS region configured, using: $AWS_REGION"
    else
        log_info "AWS region: $current_region"
    fi
    
    log_success "Prerequisites check passed"
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

get_terraform_backend_args() {
    local layer="$1"
    local backend_args=()
    
    if [[ -n "$BACKEND_CONFIG_FILE" ]]; then
        if [[ -f "$BACKEND_CONFIG_FILE" ]]; then
            backend_args+=("-backend-config=$BACKEND_CONFIG_FILE")
        else
            log_error "Backend config file not found: $BACKEND_CONFIG_FILE"
            return 1
        fi
    else
        # Default backend configuration
        backend_args+=("-backend-config=key=$layer/terraform.tfstate")
        
        # Add region if specified
        if [[ -n "$AWS_REGION" ]]; then
            backend_args+=("-backend-config=region=$AWS_REGION")
        fi
    fi
    
    printf '%s\n' "${backend_args[@]}"
}

get_terraform_var_args() {
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
    
    printf '%s\n' "${var_args[@]}"
}

# =============================================================================
# Terraform Operations
# =============================================================================

terraform_init() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Initializing Terraform for $layer layer..."
    
    local backend_args
    if ! backend_args=$(get_terraform_backend_args "$layer"); then
        return 1
    fi
    
    cd "$layer_dir"
    
    local init_cmd="terraform init"
    
    # Add backend configuration
    while IFS= read -r arg; do
        init_cmd="$init_cmd $arg"
    done <<< "$backend_args"
    
    log_debug "Running: $init_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $init_cmd"
        return 0
    fi
    
    if ! eval "$init_cmd"; then
        log_error "Terraform init failed for $layer layer"
        return 1
    fi
    
    log_success "Terraform initialized for $layer layer"
}

terraform_validate() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Validating Terraform configuration for $layer layer..."
    
    cd "$layer_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate Terraform configuration"
        return 0
    fi
    
    if ! terraform validate; then
        log_error "Terraform validation failed for $layer layer"
        return 1
    fi
    
    log_success "Terraform validation passed for $layer layer"
}

terraform_plan() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Planning Terraform changes for $layer layer..."
    
    local var_args
    if ! var_args=$(get_terraform_var_args); then
        return 1
    fi
    
    cd "$layer_dir"
    
    local plan_cmd="terraform plan -detailed-exitcode"
    
    # Add variable arguments
    while IFS= read -r arg; do
        if [[ -n "$arg" ]]; then
            plan_cmd="$plan_cmd $arg"
        fi
    done <<< "$var_args"
    
    log_debug "Running: $plan_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $plan_cmd"
        return 0
    fi
    
    # Run terraform plan and capture exit code
    local plan_exitcode=0
    eval "$plan_cmd" || plan_exitcode=$?
    
    case $plan_exitcode in
        0)
            log_success "No changes required for $layer layer"
            return 0
            ;;
        1)
            log_error "Terraform plan failed for $layer layer"
            return 1
            ;;
        2)
            log_info "Changes planned for $layer layer"
            return 2  # Changes detected
            ;;
        *)
            log_error "Unexpected exit code from terraform plan: $plan_exitcode"
            return 1
            ;;
    esac
}

terraform_apply() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Applying Terraform changes for $layer layer..."
    
    local var_args
    if ! var_args=$(get_terraform_var_args); then
        return 1
    fi
    
    cd "$layer_dir"
    
    local apply_cmd="terraform apply"
    
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        apply_cmd="$apply_cmd -auto-approve"
    fi
    
    # Add variable arguments  
    while IFS= read -r arg; do
        if [[ -n "$arg" ]]; then
            apply_cmd="$apply_cmd $arg"
        fi
    done <<< "$var_args"
    
    log_debug "Running: $apply_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $apply_cmd"
        return 0
    fi
    
    if ! eval "$apply_cmd"; then
        log_error "Terraform apply failed for $layer layer"
        return 1
    fi
    
    log_success "Terraform apply completed for $layer layer"
}

terraform_destroy() {
    local layer="$1"
    local layer_dir="$2"
    
    log_info "Destroying Terraform resources for $layer layer..."
    
    local var_args
    if ! var_args=$(get_terraform_var_args); then
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
        return 0
    fi
    
    if ! eval "$destroy_cmd"; then
        log_error "Terraform destroy failed for $layer layer"
        return 1
    fi
    
    log_success "Terraform destroy completed for $layer layer"
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

get_layer_status() {
    local layer="$1"
    local layer_dir="$2"
    
    if [[ ! -d "$layer_dir" ]]; then
        echo "missing"
        return 0
    fi
    
    cd "$layer_dir"
    
    # Check if Terraform is initialized
    if [[ ! -d ".terraform" ]]; then
        echo "not-initialized"
        return 0
    fi
    
    # Check if state exists
    if ! terraform show &>/dev/null; then
        echo "no-state"
        return 0
    fi
    
    # Check if there are any resources in state
    local resource_count
    resource_count=$(terraform state list 2>/dev/null | wc -l)
    
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
        *)
            log_error "Unknown layer: $layer"
            return 1
            ;;
    esac
    
    return 0
}

deploy_layer() {
    local layer="$1"
    local layer_dir="$2"
    
    log "Starting deployment of $layer layer..."
    
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
    
    # Plan changes
    local plan_exitcode=0
    terraform_plan "$layer" "$layer_dir" || plan_exitcode=$?
    
    case $plan_exitcode in
        0)
            log_success "$layer layer is up to date"
            return 0
            ;;
        1)
            return 1  # Plan failed
            ;;
        2)
            # Changes detected, proceed with apply
            ;;
        *)
            log_error "Unexpected plan result for $layer layer"
            return 1
            ;;
    esac
    
    # Confirm before applying (unless auto-approved or dry-run)
    if [[ "$DRY_RUN" != "true" && "$AUTO_APPROVE" != "true" ]]; then
        if ! confirm_action "Apply changes to $layer layer?"; then
            log_info "Deployment cancelled by user"
            return 1
        fi
    fi
    
    # Apply changes
    if ! terraform_apply "$layer" "$layer_dir"; then
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
        
        # Update kubeconfig
        if aws eks update-kubeconfig --region "$AWS_REGION" --name "$cluster_name" &>/dev/null; then
            log_success "Successfully configured kubectl for cluster $cluster_name"
            
            # Test cluster connectivity
            if kubectl cluster-info &>/dev/null; then
                log_success "Cluster connectivity verified"
            else
                log_warning "Cluster is not immediately accessible"
            fi
        else
            log_warning "Could not configure kubectl for cluster $cluster_name"
        fi
    fi
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
    local layers=("base" "middleware" "application")
    local layer_dirs=("$BASE_LAYER_DIR" "$MIDDLEWARE_LAYER_DIR" "$APPLICATION_LAYER_DIR")
    
    if [[ -n "$TARGET_LAYER" ]]; then
        case "$TARGET_LAYER" in
            "base")
                layers=("base")
                layer_dirs=("$BASE_LAYER_DIR")
                ;;
            "middleware")
                layers=("middleware")
                layer_dirs=("$MIDDLEWARE_LAYER_DIR")
                ;;
            "application")
                layers=("application")
                layer_dirs=("$APPLICATION_LAYER_DIR")
                ;;
            *)
                log_error "Invalid layer: $TARGET_LAYER"
                log_error "Valid layers: base, middleware, application"
                exit 1
                ;;
        esac
    fi
    
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
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
        if ! deploy_layer "$layer" "$layer_dir"; then
            log_error "Failed to deploy $layer layer"
            failed_layers+=("$layer")
            
            if [[ "$AUTO_APPROVE" != "true" ]]; then
                if ! confirm_action "Continue with remaining layers?"; then
                    break
                fi
            fi
        fi
    done
    
    # Report results
    if [[ ${#failed_layers[@]} -eq 0 ]]; then
        log_success "All layers deployed successfully"
        
        # Show post-deployment information
        show_deployment_info
        
    else
        log_error "Deployment failed for layers: ${failed_layers[*]}"
        exit 1
    fi
}

cmd_plan() {
    local layers=("base" "middleware" "application")
    local layer_dirs=("$BASE_LAYER_DIR" "$MIDDLEWARE_LAYER_DIR" "$APPLICATION_LAYER_DIR")
    
    if [[ -n "$TARGET_LAYER" ]]; then
        case "$TARGET_LAYER" in
            "base")
                layers=("base")
                layer_dirs=("$BASE_LAYER_DIR")
                ;;
            "middleware")
                layers=("middleware")
                layer_dirs=("$MIDDLEWARE_LAYER_DIR")
                ;;
            "application")
                layers=("application")
                layer_dirs=("$APPLICATION_LAYER_DIR")
                ;;
            *)
                log_error "Invalid layer: $TARGET_LAYER"
                exit 1
                ;;
        esac
    fi
    
    log "Showing deployment plan for ${#layers[@]} layer(s)..."
    
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
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
        echo
    done
}

cmd_validate() {
    local layers=("base" "middleware" "application")
    local layer_dirs=("$BASE_LAYER_DIR" "$MIDDLEWARE_LAYER_DIR" "$APPLICATION_LAYER_DIR")
    
    if [[ -n "$TARGET_LAYER" ]]; then
        case "$TARGET_LAYER" in
            "base")
                layers=("base")
                layer_dirs=("$BASE_LAYER_DIR")
                ;;
            "middleware")
                layers=("middleware")
                layer_dirs=("$MIDDLEWARE_LAYER_DIR")
                ;;
            "application")
                layers=("application")
                layer_dirs=("$APPLICATION_LAYER_DIR")
                ;;
            *)
                log_error "Invalid layer: $TARGET_LAYER"
                exit 1
                ;;
        esac
    fi
    
    log "Validating ${#layers[@]} layer(s)..."
    
    local validation_errors=()
    
    for i in "${!layers[@]}"; do
        local layer="${layers[$i]}"
        local layer_dir="${layer_dirs[$i]}"
        
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
        log_success "All validations passed"
    else
        log_error "Validation errors found:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        exit 1
    fi
}

cmd_destroy() {
    local layers=("application" "middleware" "base")  # Reverse order
    local layer_dirs=("$APPLICATION_LAYER_DIR" "$MIDDLEWARE_LAYER_DIR" "$BASE_LAYER_DIR")
    
    if [[ -n "$TARGET_LAYER" ]]; then
        case "$TARGET_LAYER" in
            "base")
                layers=("base")
                layer_dirs=("$BASE_LAYER_DIR")
                ;;
            "middleware")
                layers=("middleware")
                layer_dirs=("$MIDDLEWARE_LAYER_DIR")
                ;;
            "application")
                layers=("application")
                layer_dirs=("$APPLICATION_LAYER_DIR")
                ;;
            *)
                log_error "Invalid layer: $TARGET_LAYER"
                exit 1
                ;;
        esac
    fi
    
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
            
            if [[ "$AUTO_APPROVE" != "true" ]]; then
                if ! confirm_action "Continue with remaining layers?"; then
                    break
                fi
            fi
        fi
    done
    
    # Report results
    if [[ ${#failed_layers[@]} -eq 0 ]]; then
        log_success "All layers destroyed successfully"
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
    command=$(parse_arguments "$@")
    
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