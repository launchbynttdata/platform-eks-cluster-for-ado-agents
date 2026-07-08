# =============================================================================
# Middleware Layer Terragrunt Configuration
# =============================================================================
# This layer creates cluster operators and middleware services:
# - KEDA (Kubernetes Event Driven Autoscaling)
# - External Secrets Operator (ESO)
# - Buildkitd (container image builder)
# - Namespaces and RBAC configuration
#
# Dependencies: Base Layer (requires EKS cluster and KMS key) + Networking Layer ordering

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

  # Ensure base and networking layers are applied before middleware
  before_hook "check_base_dependency" {
    commands = ["apply", "plan"]
    execute  = ["echo", "Middleware layer depends on base and networking layers..."]
  }

  after_hook "middleware_deployed" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "echo '✅ Middleware layer deployed. KEDA and ESO are now available in the cluster.'"]
    run_on_error = false
  }

  # Validate kubectl access before apply (requires EKS access entry for caller IAM role).
  # Keep plan cluster-access-free for PR validation and pre-cluster workflows.
  before_hook "validate_kubectl" {
    commands = ["apply"]
    execute  = ["bash", "-c", "kubectl cluster-info --context ${dependency.base.outputs.cluster_name} 2>/dev/null || (echo '⚠️  Warning: kubectl not configured.'; aws eks update-kubeconfig --alias ${dependency.base.outputs.cluster_name} --name ${dependency.base.outputs.cluster_name}; kubectl cluster-info --context ${dependency.base.outputs.cluster_name})"]
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
# This layer depends on the base layer for cluster information and the
# networking layer for CNI readiness ordering.

dependencies {
  paths = ["../networking"]
}

dependency "base" {
  config_path = "../base"

  # Mock outputs allow running plan/validate before base layer exists
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"

  mock_outputs = local.common.locals.mock_outputs_base
}

# =============================================================================
# Layer-Specific Inputs
# =============================================================================
# These inputs are specific to the middleware layer

inputs = {
  # Remote state configuration
  remote_state_bucket      = get_env("TF_STATE_BUCKET")
  remote_state_region      = get_env("TF_STATE_REGION", local.env.locals.aws_region)
  remote_state_environment = local.env.locals.environment
  base_state_key           = "base/terraform.tfstate"

  # CloudWatch logging / observability
  enable_cloudwatch_observability        = try(local.env.locals.enable_cloudwatch_observability, true)
  enable_cloudwatch_observability_addon  = try(local.env.locals.enable_cloudwatch_observability_addon, true)
  cloudwatch_observability_addon_version = try(local.env.locals.cloudwatch_observability_addon_version, null)
  enable_cloudwatch_application_signals_auto_monitor              = try(local.env.locals.enable_cloudwatch_application_signals_auto_monitor, true)
  cloudwatch_application_signals_auto_monitor_excluded_namespaces = try(local.env.locals.cloudwatch_application_signals_auto_monitor_excluded_namespaces, [])
  cloudwatch_log_retention_days                                  = try(local.env.locals.cloudwatch_log_retention_days, 30)
  enable_fargate_cloudwatch_logging                              = try(local.env.locals.enable_fargate_cloudwatch_logging, true)
  fargate_fluentbit_log_level                                    = try(local.env.locals.fargate_fluentbit_log_level, "info")
  fargate_fluentbit_include_process_logs = try(local.env.locals.fargate_fluentbit_include_process_logs, false)
  platform_log_groups                    = try(local.env.locals.platform_log_groups, ["application", "dataplane", "host", "performance", "ado-agents", "buildkit", "keda", "cluster-autoscaler"])
  enable_ado_agent_cloudwatch_log_groups = try(local.env.locals.enable_ado_agent_cloudwatch_log_groups, true)
  application_crd_ready_wait_seconds     = try(local.env.locals.application_crd_ready_wait_seconds, 60)

  # KEDA Configuration
  install_keda                         = local.env.locals.install_keda
  keda_namespace                       = local.env.locals.keda_namespace
  keda_version                         = local.env.locals.keda_version
  keda_enable_cloudeventsource         = local.env.locals.keda_enable_cloudeventsource
  keda_enable_cluster_cloudeventsource = local.env.locals.keda_enable_cluster_cloudeventsource
  install_metrics_server               = local.env.locals.install_metrics_server
  metrics_server_namespace             = local.env.locals.metrics_server_namespace
  metrics_server_chart_version         = local.env.locals.metrics_server_chart_version
  metrics_server_args                  = local.env.locals.metrics_server_args
  metrics_server_node_selector         = local.env.locals.metrics_server_node_selector
  metrics_server_tolerations           = local.env.locals.metrics_server_tolerations
  metrics_server_resources             = local.env.locals.metrics_server_resources

  # ADO Agent Configuration
  ado_agents_namespace = local.env.locals.ado_agents_namespace
  ado_secret_name      = try(local.env.locals.ado_secret_name, local.env.locals.ado_pat_secret_name)

  # External Secrets Operator Configuration
  install_eso                = local.env.locals.install_eso
  eso_namespace              = local.env.locals.eso_namespace
  eso_version                = local.env.locals.eso_version
  eso_webhook_enabled        = local.env.locals.eso_webhook_enabled
  eso_webhook_failure_policy = local.env.locals.eso_webhook_failure_policy
  cluster_secret_store_name  = local.env.locals.cluster_secret_store_name

  # Buildkitd Configuration
  enable_buildkitd                                   = local.env.locals.enable_buildkitd
  buildkitd_namespace                                = local.env.locals.buildkitd_namespace
  buildkitd_image                                    = local.env.locals.buildkitd_image
  buildkitd_replicas                                 = local.env.locals.buildkitd_replicas
  buildkitd_node_selector                            = local.env.locals.buildkitd_node_selector
  buildkitd_tolerations                              = local.env.locals.buildkitd_tolerations
  buildkitd_resources                                = local.env.locals.buildkitd_resources
  buildkitd_storage_size                             = local.env.locals.buildkitd_storage_size
  buildkitd_hpa_enabled                              = local.env.locals.buildkitd_hpa_enabled
  buildkitd_hpa_min_replicas                         = local.env.locals.buildkitd_hpa_min_replicas
  buildkitd_hpa_max_replicas                         = local.env.locals.buildkitd_hpa_max_replicas
  buildkitd_hpa_target_memory_utilization_percentage = local.env.locals.buildkitd_hpa_target_memory_utilization_percentage
  buildkitd_ecr_registry_account_ids                 = try(local.env.locals.buildkitd_ecr_registry_account_ids, [])
  buildkitd_ecr_repository_arns                      = try(local.env.locals.buildkitd_ecr_repository_arns, [])
  buildkitd_kms_key_arn_patterns                     = try(local.env.locals.buildkitd_kms_key_arn_patterns, [])
  buildkitd_registry_mirrors                         = try(local.env.locals.buildkitd_registry_mirrors, {})
  buildkitd_topology_spread_enabled                  = try(local.env.locals.buildkitd_topology_spread_enabled, true)
  buildkitd_pdb_enabled                              = try(local.env.locals.buildkitd_pdb_enabled, true)
  buildkitd_pdb_min_available                        = try(local.env.locals.buildkitd_pdb_min_available, 1)
  buildkitd_tls_enabled                              = try(local.env.locals.buildkitd_tls_enabled, false)
  buildkitd_tls_secret_name                          = try(local.env.locals.buildkitd_tls_secret_name, "")

  enable_ecr_pull_through_cache = try(local.env.locals.enable_ecr_pull_through_cache, true)
  ecr_pull_through_cache_rules = try(local.env.locals.ecr_pull_through_cache_rules, {
    ecr-public = {
      upstream_registry_url = "public.ecr.aws"
    }
    k8s = {
      upstream_registry_url = "registry.k8s.io"
    }
    quay = {
      upstream_registry_url = "quay.io"
    }
  })
  create_ecr_pull_through_cache_repository_templates = try(local.env.locals.create_ecr_pull_through_cache_repository_templates, true)
  create_ecr_pull_through_cache_repository_policies  = try(local.env.locals.create_ecr_pull_through_cache_repository_policies, true)

  # Node auto-heal / AWS Node Termination Handler configuration
  node_auto_heal_chart_version           = try(local.env.locals.node_auto_heal_chart_version, "0.27.6")
  node_auto_heal_daemonset_node_selector = local.env.locals.node_auto_heal_daemonset_node_selector
  node_auto_heal_daemonset_tolerations   = local.env.locals.node_auto_heal_daemonset_tolerations
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
