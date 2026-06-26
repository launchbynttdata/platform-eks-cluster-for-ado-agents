# Remote State Data Sources
#
# This file defines remote state data sources for dependencies from other layers.

locals {
  base_state_prefix = var.remote_state_environment != "" ? "${var.remote_state_environment}/" : ""
}

data "terraform_remote_state" "base" {
  backend   = "s3"
  workspace = "default"
  config = {
    bucket = var.remote_state_bucket
    key    = "${local.base_state_prefix}${var.base_state_key}"
    region = var.remote_state_region
  }
}
