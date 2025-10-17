# Middleware Layer Configuration
#
# Copy this file to terraform.tfvars and customize the values for your environment.
# This layer depends on the base infrastructure layer.

# AWS Configuration
aws_region = "us-west-2"

# Remote State Configuration (REQUIRED)
# S3 bucket where base layer state is stored
remote_state_bucket = "brv-eks-ado-cluster-rs-1935a"  # Replace with your state bucket
base_state_key      = "base/terraform.tfstate"

# KEDA Configuration
install_keda          = true
keda_namespace        = "keda-system"
keda_version          = "2.15.1"
ado_agents_namespace  = "ado-agents"
ado_secret_name       = "ado-pat"

# External Secrets Operator Configuration
install_eso                   = true
eso_namespace                 = "external-secrets-system"
eso_version                   = "0.10.4"
eso_webhook_enabled           = false  # Keep false for Fargate compatibility
eso_webhook_failure_policy    = "Ignore"
create_cluster_secret_store   = true
cluster_secret_store_name     = "aws-secrets-manager"

# Buildkitd Configuration
enable_buildkitd      = true
buildkitd_namespace   = "buildkit-system"
buildkitd_image       = "moby/buildkit:v0.12.5"
buildkitd_replicas    = 2

# Buildkitd node selection (use EC2 nodes if available)
buildkitd_node_selector = {
  # Uncomment if you have EC2 nodes with this label
  "workload-type" = "buildkit"
}

# Buildkitd tolerations (adjust based on your node setup)
buildkitd_tolerations = [
  # {
  #   key      = "ks.amazonaws.com/compute-type"
  #   operator = "Equal"
  #   value    = "fargate"
  #   effect   = "NoSchedule"
  # }
  # Add additional tolerations if using dedicated buildkit nodes:
  {
    key      = "workload-type"
    operator = "Equal"
    value    = "buildkit"
    effect   = "NoSchedule"
  }
]

# Buildkitd resource allocation
buildkitd_resources = {
  requests = {
    cpu    = "500m"
    memory = "1Gi"
  }
  limits = {
    cpu    = "2"
    memory = "4Gi"
  }
}

buildkitd_storage_size = "20Gi"

# Additional tags for middleware layer
additional_tags = {
  "Component" = "middleware"
  "Layer"     = "middleware"
}