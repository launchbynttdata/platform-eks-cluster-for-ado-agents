# Networking Layer
#
# Installs optional cluster CNI components after the base layer creates the EKS
# control plane. The default VPC CNI mode is intentionally a Terraform-valid
# no-op so this layer can remain in the deployment sequence for all clusters.

locals {
  cilium_enabled            = var.pod_networking_mode == "cilium-overlay"
  base_pod_networking_mode  = try(data.terraform_remote_state.base.outputs.pod_networking_mode, var.pod_networking_mode)
  cilium_cluster_pool_cidrs = var.cilium_networking.cluster_pool_ipv4_pod_cidr_list
  cilium_cluster_pool_mask  = var.cilium_networking.cluster_pool_ipv4_mask_size
  cilium_default_helm_values = {
    routingMode          = "tunnel"
    tunnelProtocol       = "vxlan"
    kubeProxyReplacement = false
    ipam = {
      mode = "cluster-pool"
      operator = {
        clusterPoolIPv4PodCIDRList = local.cilium_cluster_pool_cidrs
        clusterPoolIPv4MaskSize    = local.cilium_cluster_pool_mask
      }
    }
  }
  cilium_helm_values = merge(local.cilium_default_helm_values, var.cilium_networking.helm_values_override)
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

resource "helm_release" "cilium" {
  count = local.cilium_enabled ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_networking.chart_version
  namespace  = "kube-system"

  atomic  = true
  timeout = 900
  wait    = true

  values = [
    yamlencode(local.cilium_helm_values)
  ]

  depends_on = [terraform_data.networking_mode_validation]
}
