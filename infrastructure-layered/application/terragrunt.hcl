# =============================================================================
# Application Layer Terragrunt Configuration
# =============================================================================
# This layer creates application-specific resources:
# - ECR repositories for custom ADO agent images
# - AWS Secrets Manager secrets for ADO PAT
# - IAM execution roles for ADO agents
# - Helm deployment of ADO agents
# - KEDA ScaledObjects for autoscaling
#
# Dependencies: Base Layer (cluster info) + Middleware Layer (KEDA, ESO)

# Include root configuration
include "root" {
  path = find_in_parent_folders()
}

# Include common configuration helpers
include "common" {
  path = find_in_parent_folders("common.hcl")
}

# Specify the Terraform source
terraform {
  source = "."
  
  # Check dependencies before applying
  before_hook "check_dependencies" {
    commands = ["apply", "plan"]
    execute  = ["echo", "⏳ Application layer depends on base and middleware layers..."]
  }
  
  # Check for ADO PAT environment variable
  before_hook "check_ado_pat" {
    commands = ["apply", "plan"]
    execute  = ["bash", "-c", "if [ -z \"$TF_VAR_ado_pat_value\" ]; then echo '⚠️  Warning: TF_VAR_ado_pat_value not set. ADO agents will not authenticate.'; fi"]
  }
  
  after_hook "application_deployed" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "echo '✅ Application layer deployed. ADO agents are now running and will scale based on queue depth.'"]
    run_on_error = false
  }
  
  # Validate kubectl access before applying
  before_hook "validate_kubectl" {
    commands = ["apply"]
    execute  = ["bash", "-c", "kubectl cluster-info --context ${dependency.base.outputs.cluster_name} 2>/dev/null || echo '⚠️  Warning: kubectl not configured.'"]
  }
  
  # Show agent status after deployment
  after_hook "show_agent_status" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "echo '\n📊 To check agent status:\n  kubectl get pods -n ${dependency.middleware.outputs.ado_agents_namespace}\n  kubectl get scaledobjects -n ${dependency.middleware.outputs.ado_agents_namespace}'"]
    run_on_error = false
  }
}

# Load environment configuration
locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

# =============================================================================
# Dependencies
# =============================================================================
# This layer depends on both base and middleware layers

dependency "base" {
  config_path = "../base"
  
  # Mock outputs allow running plan/validate before base layer exists
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  
  mock_outputs = local.common.locals.mock_outputs_base
}

dependency "middleware" {
  config_path = "../middleware"
  
  # Mock outputs allow running plan/validate before middleware layer exists
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
  
  mock_outputs = local.common.locals.mock_outputs_middleware
}

# =============================================================================
# Layer-Specific Inputs
# =============================================================================
# These inputs are specific to the application layer

inputs = {
  # Base layer outputs (dependencies)
  cluster_name         = dependency.base.outputs.cluster_name
  cluster_endpoint     = dependency.base.outputs.cluster_endpoint
  cluster_ca_cert      = dependency.base.outputs.cluster_certificate_authority_data
  oidc_provider_arn    = dependency.base.outputs.oidc_provider_arn
  kms_key_arn          = dependency.base.outputs.kms_key_arn
  kms_key_id           = dependency.base.outputs.kms_key_id
  
  # Middleware layer outputs (dependencies)
  keda_namespace            = dependency.middleware.outputs.keda_namespace
  eso_namespace             = dependency.middleware.outputs.eso_namespace
  cluster_secret_store_name = dependency.middleware.outputs.cluster_secret_store_name
  ado_agents_namespace      = dependency.middleware.outputs.ado_agents_namespace
  
  # Remote state configuration (for compatibility)
  base_state_key       = "base/terraform.tfstate"
  middleware_state_key = "middleware/terraform.tfstate"
  
  # Azure DevOps Configuration
  ado_org                 = local.env.locals.ado_org
  ado_url                 = local.env.locals.ado_url
  ado_pat_secret_name     = local.env.locals.ado_pat_secret_name
  secret_recovery_days    = local.env.locals.secret_recovery_days
  secret_refresh_interval = local.env.locals.secret_refresh_interval
  
  # NOTE: ado_pat_value should be provided via environment variable:
  # export TF_VAR_ado_pat_value="your-pat-here"
  # This prevents secrets from being stored in configuration files
  
  # ECR Repositories Configuration
  ecr_repositories = local.env.locals.ecr_repositories
  
  # IAM Execution Roles Configuration
  ado_execution_roles = local.env.locals.ado_execution_roles
  
  # ADO Agent Pools Configuration
  agent_pools = local.env.locals.agent_pools
}

# =============================================================================
# Kubernetes Provider Configuration
# =============================================================================
# Generate Kubernetes and Helm provider configurations using cluster info

generate "k8s_provider" {
  path      = "k8s_provider_generated.tf"
  if_exists = "overwrite_terragrunt"
  
  contents = <<-EOF
    # Kubernetes provider configuration
    # Generated by Terragrunt based on base layer outputs
    
    data "aws_eks_cluster_auth" "cluster" {
      name = "${dependency.base.outputs.cluster_name}"
    }
    
    provider "kubernetes" {
      host                   = "${dependency.base.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.base.outputs.cluster_certificate_authority_data}")
      token                  = data.aws_eks_cluster_auth.cluster.token
    }
    
    provider "helm" {
      kubernetes {
        host                   = "${dependency.base.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.base.outputs.cluster_certificate_authority_data}")
        token                  = data.aws_eks_cluster_auth.cluster.token
      }
    }
  EOF
}

# =============================================================================
# Hooks
# =============================================================================
# Hooks are now in the terraform block above
