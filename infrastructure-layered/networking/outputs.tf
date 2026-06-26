output "pod_networking_mode" {
  description = "Configured pod networking mode for this layer."
  value       = var.pod_networking_mode
}

output "cilium_enabled" {
  description = "Whether Cilium overlay mode is enabled."
  value       = local.cilium_enabled
}

output "cilium_release" {
  description = "Cilium Helm release metadata. Cilium overlay is bootstrapped in the base layer before EC2 managed node groups."
  value = local.cilium_enabled ? {
    name      = "cilium"
    namespace = "kube-system"
    version   = var.cilium_networking.chart_version
  } : null
}
