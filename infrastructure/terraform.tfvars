# Example terraform.tfvars for ADO Agent EKS Cluster Module

# Required Variables - Must be customized for your environment

# Cluster Configuration
cluster_name = "ado-agent-cluster" # Name of the EKS cluster

# VPC Configuration
vpc_id = "vpc-0ca0d2293218c687a" # Replace with your VPC ID
subnet_ids = [
  "subnet-058e2fecdfb7edbd3", # Private subnet 1
  "subnet-06bacf2e83326a44d", # Private subnet 2
  "subnet-0c426c2b82bdd77cf", # Private subnet 3 (optional)
  "subnet-02447ee5446e66638"  # Private subnet 4 (optional)
]

# ADO Configuration
ado_org = "NVDMVDevOps" # Replace with your ADO organization name

# Optional Variables (defaults provided)
# cluster_version            = "1.29"
# Cluster endpoint access - disabled for security while waiting for network connectivity
endpoint_public_access = true
# public_access_cidrs       = ["0.0.0.0/0"]
# create_iam_roles          = true
# install_keda              = true
# keda_namespace            = "keda-system"
# ado_agents_namespace      = "ado-agents"
# create_vpc_endpoints      = true
# environment               = "dev"
# project                   = "ado-agent-cluster"

# ADO Personal Access Token (should be set via environment variable or CI/CD)
# ado_pat_value = "your-ado-pat-here"  # Set via TF_VAR_ado_pat_value

# ECR Repository URL (if using custom ADO agent image)
# ecr_repository_url = "ghcr.io/launchbynttdata/launch-build-agent-azure:gitignore-and-rebuild"

exclude_vpc_endpoint_services = [
  "s3",
  "ecr_api",
  "logs",
  "ecr_dkr"
]

environment = "poc"

# Additional Tags
tags = {
  "ProjectId"          = "MVITMR"
  "ProjectName"        = "batch-poc"
  "OwnerEmail"         = "bvaughan@dmv.nv.gov"
  "DataClassification" = "Sensitive"
  "Environment"        = "poc"
}

bastion_role_arn = "arn:aws:iam::742846647113:role/batch-poc-bastion-role"

# Authentication Management
# Set to false for initial cluster deployment, then true for subsequent updates
enable_kube_auth_management = true

# External Secrets Operator Settings
create_cluster_secret_store = true
create_external_secrets     = true
eso_webhook_enabled         = false # Disabled by default for Fargate
eso_webhook_failure_policy  = "Ignore"

# Secret management - let ESO manage the secret content
create_ado_secret = false # Let ESO create and manage the secret

ecr_repositories = {
  default = {
    repository_name         = "ado-agent-cluster-ado-agents"
    image_tag_mutability    = "MUTABLE"
    encryption_type         = "KMS"
    scan_on_push            = true
    lifecycle_untagged_days = 7
    keep_tagged_count       = 10
  },
  iac-agents = {
    repository_name         = "ado-agent-cluster-iac-agents"
    image_tag_mutability    = "MUTABLE"
    encryption_type         = "KMS"
    scan_on_push            = true
    lifecycle_untagged_days = 7
    keep_tagged_count       = 5
  }
}

# Cluster Autoscaler Configuration
enable_cluster_autoscaler  = true
cluster_autoscaler_version = "v1.33.0"

fargate_profile_selectors = [
  # {
  #   namespace = "kube-system",
  #   labels = {
  #     "app.kubernetes.io/name" = "metrics-server"
  #   }
  # }
]