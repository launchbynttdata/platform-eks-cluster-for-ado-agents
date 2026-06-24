# =============================================================================
# Networking Layer Terragrunt Configuration
# =============================================================================
# This layer validates pod networking configuration after the base EKS cluster
# exists and before middleware/application workloads are deployed.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "common" {
  path = find_in_parent_folders("common.hcl")
}

terraform {
  source = "."

  before_hook "check_base_dependency" {
    commands = ["apply", "plan"]
    execute  = ["echo", "Networking layer depends on base layer outputs..."]
  }

  after_hook "networking_deployed" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "echo 'Networking layer deployed.'"]
    run_on_error = false
  }

  before_hook "validate_kubectl" {
    commands = ["apply"]
    execute  = ["bash", "-c", "kubectl cluster-info --context ${local.env.locals.cluster_name} 2>/dev/null || (echo 'Warning: kubectl not configured.'; aws eks update-kubeconfig --alias ${local.env.locals.cluster_name} --region ${local.env.locals.aws_region} --name ${local.env.locals.cluster_name}; kubectl cluster-info --context ${local.env.locals.cluster_name})"]
  }
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

dependencies {
  paths = [
    "../base"
  ]
}

inputs = {
  remote_state_bucket      = get_env("TF_STATE_BUCKET")
  remote_state_region      = get_env("TF_STATE_REGION", local.env.locals.aws_region)
  remote_state_environment = local.env.locals.environment
  base_state_key           = "base/terraform.tfstate"

  pod_networking_mode = try(local.env.locals.pod_networking_mode, "vpc-cni")
  cilium_networking   = try(local.env.locals.cilium_networking, {})
}
