# =============================================================================
# Common Configuration
# =============================================================================
# This file contains helper functions and common logic shared across layers.
# It's optional but useful for DRY principles and reusable patterns.
#
# Note: This file does NOT load env.hcl directly. Each layer should load
# env.hcl in its own terragrunt.hcl file.

locals {
  # =============================================================================
  # Dependency Patterns
  # =============================================================================
  
  # Mock outputs for when dependencies don't exist yet
  # Useful during initial deployment or when running plan/validate
  mock_outputs_base = {
    cluster_name                      = "mock-cluster"
    cluster_id                       = "mock-cluster-id"
    cluster_arn                      = "arn:aws:eks:us-west-2:123456789012:cluster/mock-cluster"
    cluster_endpoint                 = "https://mock.eks.amazonaws.com"
    cluster_ca_cert                  = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
    oidc_provider_arn                = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/MOCK"
    kms_key_id                       = "mock-key-id"
    kms_key_arn                      = "arn:aws:kms:us-west-2:123456789012:key/mock"
    vpc_id                = "vpc-mock"
    subnet_ids            = ["subnet-mock1", "subnet-mock2"]
    security_group_id     = "sg-mock"
    node_security_group_id = "sg-mock-node"
  }
  
  mock_outputs_middleware = {
    keda_namespace               = "keda-system"
    eso_namespace                = "external-secrets-system"
    cluster_secret_store_name    = "aws-secrets-manager"
    buildkitd_namespace          = "buildkit-system"
    buildkitd_service_account    = "buildkitd"
    ado_agents_namespace         = "ado-agents"
  }
  
  # =============================================================================
  # Helper Functions
  # =============================================================================
  
  # Get the layer name from the current directory
  layer_name = basename(get_terragrunt_dir())
  
  # Determine if we're in a specific layer
  is_base_layer        = local.layer_name == "base"
  is_middleware_layer  = local.layer_name == "middleware"
  is_application_layer = local.layer_name == "application"
}
