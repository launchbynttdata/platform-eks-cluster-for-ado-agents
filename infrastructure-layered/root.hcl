# =============================================================================
# Root Terragrunt Configuration
# =============================================================================
# This is the root configuration file for all infrastructure layers.
# It defines common settings, remote state configuration, and provider setup.
#
# All child terragrunt.hcl files will inherit these settings automatically.

locals {
  # Load environment-specific configuration  
  # This allows switching between dev/staging/prod by changing env.hcl
  # Use find_in_parent_folders with fallback to current directory
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl", "${get_terragrunt_dir()}/env.hcl"))
  
  # Extract commonly used values
  environment  = local.env_vars.locals.environment
  aws_region   = local.env_vars.locals.aws_region
  project_name = local.env_vars.locals.project_name
  
  # Construct resource naming conventions
  name_prefix = "${local.project_name}-${local.environment}"
  
  # Common tags applied to all resources
  common_tags = merge(
    local.env_vars.locals.common_tags,
    {
      Project     = local.project_name
      Environment = local.environment
      ManagedBy   = "Terragrunt"
      Terraform   = "true"
      Repository  = "platform-eks-cluster-for-ado-agents"
    }
  )
}

# =============================================================================
# Remote State Configuration
# =============================================================================
# Configure S3 backend for Terraform state
# State bucket must be created beforehand (via TF_STATE_BUCKET env var)
#
# Features:
# - Native S3 locking (Terraform 1.10+, no DynamoDB needed)
# - Encryption at rest
# - Versioning enabled (configured on bucket)
# - Per-layer state files

remote_state {
  backend = "s3"
  
  generate = {
    path      = "backend_generated.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    # Bucket name from environment variable
    bucket = get_env("TF_STATE_BUCKET")
    
    # Dynamic key based on layer path
    # Example: base/terraform.tfstate, middleware/terraform.tfstate
    key = "${path_relative_to_include()}/terraform.tfstate"
    
    # Region from environment variable or env.hcl
    region = get_env("TF_STATE_REGION", local.aws_region)
    
    # Security settings
    encrypt        = true
    
    # Terraform 1.10+ uses native S3 locking - no DynamoDB table needed!
    # The state bucket itself handles locking via S3's built-in mechanisms
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================
# Generate AWS provider configuration with common settings
# This ensures consistency across all layers

generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite_terragrunt"
  
  contents = <<EOF
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"
  
  default_tags {
    tags = ${jsonencode(local.common_tags)}
  }
}
EOF
}

# =============================================================================
# Common Inputs
# =============================================================================
# These inputs are available to all child terragrunt.hcl configurations
# They can be overridden in layer-specific files

inputs = {
  # AWS Configuration
  aws_region = local.aws_region
  
  # Remote state bucket (for middleware and application layers)
  remote_state_bucket = get_env("TF_STATE_BUCKET")
  remote_state_region = get_env("TF_STATE_REGION", local.aws_region)
  
  # Common tags
  additional_tags = local.common_tags
}

# =============================================================================
# Terraform Configuration
# =============================================================================
# Control Terraform CLI behavior

terraform {
  # Run init if .terraform directory is missing or empty
  extra_arguments "init_args" {
    commands = [
      "init",
      "plan",
      "apply",
      "destroy",
      "refresh"
    ]
  }
  
  # Retry on common transient errors
  extra_arguments "retry_lock" {
    commands = get_terraform_commands_that_need_locking()
    
    arguments = [
      "-lock-timeout=10m"
    ]
  }
  
  # Common variables passed to all terraform commands
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
    
    # These are handled by the inputs block above
    # But we can add environment variable overrides here
    env_vars = {
      TF_INPUT = "false"
    }
  }
}

# =============================================================================
# Hooks
# =============================================================================
# Run custom commands before/after Terraform operations

# Before apply, show a summary of what will change
terraform_version_constraint = ">= 1.5.0"
terragrunt_version_constraint = ">= 0.48.0"
