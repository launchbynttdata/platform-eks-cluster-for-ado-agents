# Remote State Data Sources
#
# This file defines remote state data sources for dependencies from other layers.

# Base Infrastructure Layer State
data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = var.base_state_key
    region = var.aws_region
  }
}