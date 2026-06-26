# =============================================================================
# Application Layer Terragrunt Configuration
# =============================================================================
# This layer creates application-specific resources:
# - ECR repositories for custom ADO agent images
# - AWS Secrets Manager secrets for ADO PAT
# - IAM execution roles for ADO agents
# - Helm deployment of ADO agents
# - KEDA ScaledJobs for per-job workers
#
# Dependencies: Base Layer (cluster info) + Middleware Layer (KEDA, ESO)

# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
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
    execute  = ["bash", "-c", "kubectl cluster-info --context ${local.env.locals.cluster_name} 2>/dev/null || (echo '⚠️  Warning: kubectl not configured.'; aws eks update-kubeconfig --alias ${local.env.locals.cluster_name} --region ${local.env.locals.aws_region} --name ${local.env.locals.cluster_name}; kubectl cluster-info --context ${local.env.locals.cluster_name})"]
  }

  # Show agent status after deployment
  after_hook "show_agent_status" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "echo '\n📊 To check agent status:\n  kubectl get pods -n ${local.env.locals.ado_agents_namespace}\n  kubectl get scaledjobs -n ${local.env.locals.ado_agents_namespace}\n  kubectl get jobs -n ${local.env.locals.ado_agents_namespace}'"]
    run_on_error = false
  }
}

# Load environment configuration
locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))

  ado_org_url_override = trimspace(get_env("ADO_ORG_URL", ""))
  effective_ado_url    = local.ado_org_url_override != "" ? trimsuffix(local.ado_org_url_override, "/") : local.env.locals.ado_url
  effective_ado_org    = local.ado_org_url_override != "" ? replace(local.effective_ado_url, "https://dev.azure.com/", "") : get_env("ADO_ORG", local.env.locals.ado_org)
}

# =============================================================================
# Dependencies
# =============================================================================
# This layer depends on both base and middleware layers. Terraform reads the actual
# values through terraform_remote_state; Terragrunt only needs ordering here.
dependencies {
  paths = [
    "../base",
    "../middleware"
  ]
}

# =============================================================================
# Layer-Specific Inputs
# =============================================================================
# These inputs are specific to the application layer

inputs = {
  # Remote state configuration (for compatibility)
  remote_state_environment = local.env.locals.environment
  remote_state_bucket      = get_env("TF_STATE_BUCKET")
  remote_state_region      = get_env("TF_STATE_REGION", local.env.locals.aws_region)

  # Azure DevOps Configuration
  ado_org                 = local.effective_ado_org
  ado_url                 = local.effective_ado_url
  ado_pat_secret_name     = local.env.locals.ado_pat_secret_name
  ado_agent_auth_mode     = try(local.env.locals.ado_agent_auth_mode, "pat")
  ado_agent_spn_secret    = try(local.env.locals.ado_agent_spn_secret, { aws_secret_name = "" })
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
  agent_pools                            = local.env.locals.agent_pools
  agent_run_once                         = try(local.env.locals.agent_run_once, true)
  agent_recycle_pod_after_run_once       = try(local.env.locals.agent_recycle_pod_after_run_once, false)
  agent_cleanup_timeout_seconds          = try(local.env.locals.agent_cleanup_timeout_seconds, 300)
  agent_termination_grace_period_seconds = try(local.env.locals.agent_termination_grace_period_seconds, 420)
  agent_automount_service_account_token  = try(local.env.locals.agent_automount_service_account_token, true)
  ado_agents_helm_atomic                 = try(local.env.locals.ado_agents_helm_atomic, false)
  ado_agents_helm_cleanup_on_fail        = try(local.env.locals.ado_agents_helm_cleanup_on_fail, false)
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
    # Generated by Terragrunt. Cluster values are loaded by Terraform from remote state.
    
    data "aws_eks_cluster_auth" "cluster" {
      name = data.terraform_remote_state.base.outputs.cluster_name
    }
    
    provider "kubernetes" {
      host                   = data.terraform_remote_state.base.outputs.cluster_endpoint
      cluster_ca_certificate = base64decode(data.terraform_remote_state.base.outputs.cluster_certificate_authority_data)
      token                  = data.aws_eks_cluster_auth.cluster.token
    }
    
    provider "helm" {
      kubernetes {
        host                   = data.terraform_remote_state.base.outputs.cluster_endpoint
        cluster_ca_certificate = base64decode(data.terraform_remote_state.base.outputs.cluster_certificate_authority_data)
        token                  = data.aws_eks_cluster_auth.cluster.token
      }
    }
  EOF
}

# =============================================================================
# Hooks
# =============================================================================
# Hooks are now in the terraform block above
