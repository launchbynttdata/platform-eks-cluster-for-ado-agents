# Remote State Configuration - Application Layer
#
# This file configures access to remote state from other layers.
# The application layer depends on both base and middleware layers.

# Base infrastructure layer state (EKS cluster, networking, IAM)
locals {
  remote_state_prefix = var.remote_state_environment != "" ? "${var.remote_state_environment}/" : ""
}

data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = "${local.remote_state_prefix}base/terraform.tfstate"
    region = var.remote_state_region
  }
}

# Middleware layer state (KEDA, ESO, buildkitd, namespaces)
data "terraform_remote_state" "middleware" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = "${local.remote_state_prefix}middleware/terraform.tfstate"
    region = var.remote_state_region
  }
}

# Variables for remote state configuration
variable "remote_state_bucket" {
  description = "S3 bucket name for remote state storage"
  type        = string
}

variable "remote_state_region" {
  description = "AWS region for remote state bucket"
  type        = string
}

variable "remote_state_environment" {
  description = "Environment prefix for remote state keys (matches env.hcl environment)"
  type        = string
  default     = ""
}