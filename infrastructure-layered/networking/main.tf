# Networking Layer
#
# Validates optional cluster CNI configuration after the base layer. VPC CNI mode
# is intentionally a Terraform-valid no-op. Cilium overlay is bootstrapped in the
# base layer before EC2 managed node groups, because those nodes must see a CNI
# during kubelet startup to become Ready.

locals {
  cilium_enabled            = var.pod_networking_mode == "cilium-overlay"
  base_pod_networking_mode  = try(data.terraform_remote_state.base.outputs.pod_networking_mode, var.pod_networking_mode)
  cilium_cluster_pool_cidrs = var.cilium_networking.cluster_pool_ipv4_pod_cidr_list
  cilium_cluster_pool_mask  = var.cilium_networking.cluster_pool_ipv4_mask_size
}

resource "terraform_data" "networking_mode_validation" {
  input = var.pod_networking_mode

  lifecycle {
    precondition {
      condition     = local.base_pod_networking_mode == var.pod_networking_mode
      error_message = "The networking layer pod_networking_mode must match the base layer output."
    }

    precondition {
      condition     = !local.cilium_enabled || length(local.cilium_cluster_pool_cidrs) > 0
      error_message = "cilium-overlay mode requires at least one Cilium cluster-pool IPv4 pod CIDR."
    }
  }
}
