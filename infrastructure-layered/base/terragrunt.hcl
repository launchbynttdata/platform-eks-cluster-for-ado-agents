# =============================================================================
# Base Layer Terragrunt Configuration
# =============================================================================
# This layer creates the foundational infrastructure:
# - EKS Cluster
# - VPC configuration (using existing VPC)
# - IAM roles and policies
# - KMS encryption keys
# - Fargate profiles
# - EKS add-ons
# - VPC endpoints

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
  
  # Before destroy, warn about dependencies
  before_hook "warn_before_destroy" {
    commands = ["destroy"]
    execute  = ["echo", "⚠️  WARNING: Destroying base layer will make middleware and application layers unusable!"]
  }
  
  after_hook "kubeconfig_after_apply" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "echo '✅ Base layer deployed. Configure kubectl: aws eks update-kubeconfig --region ${local.env.locals.aws_region} --name ${local.env.locals.cluster_name}'"]
    run_on_error = false
  }
}

# Load environment configuration
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# =============================================================================
# Layer-Specific Inputs
# =============================================================================
# These inputs are specific to the base layer and are sourced from env.hcl

inputs = {
  # Global Configuration
  environment = local.env.locals.environment
  project     = local.env.locals.project_name
  tags        = local.env.locals.common_tags
  
  # Cluster Configuration
  cluster_name    = local.env.locals.cluster_name
  cluster_version = local.env.locals.cluster_version
  
  # Networking Configuration
  vpc_id     = local.env.locals.vpc_id
  subnet_ids = local.env.locals.subnet_ids
  
  # Security Configuration
  endpoint_public_access = local.env.locals.endpoint_public_access
  public_access_cidrs    = local.env.locals.public_access_cidrs
  
  # IAM Configuration
  create_iam_roles = local.env.locals.create_iam_roles
  
  # KMS Configuration
  kms_key_description             = local.env.locals.kms_key_description
  kms_key_deletion_window_in_days = local.env.locals.kms_key_deletion_window_in_days
  
  # Fargate Configuration
  fargate_profiles = local.env.locals.fargate_profiles
  
  # EKS Add-ons Configuration
  eks_addons = local.env.locals.eks_addons
  
  # VPC Endpoints Configuration
  create_vpc_endpoints          = local.env.locals.create_vpc_endpoints
  vpc_endpoint_services         = local.env.locals.vpc_endpoint_services
  exclude_vpc_endpoint_services = local.env.locals.exclude_vpc_endpoint_services
  
  # EC2 Node Groups (optional)
  ec2_node_group = local.env.locals.ec2_node_groups
}

# =============================================================================
# Dependencies
# =============================================================================
# Base layer has no dependencies - it's the foundation
