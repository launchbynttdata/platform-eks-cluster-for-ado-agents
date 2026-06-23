output "pod_networking_mode" {
  description = "Configured pod networking mode for this layer."
  value       = var.pod_networking_mode
}

output "cilium_enabled" {
  description = "Whether the networking layer installed Cilium."
  value       = local.cilium_enabled
}

output "cilium_release" {
  description = "Cilium Helm release metadata when enabled."
  value = local.cilium_enabled ? {
    name      = helm_release.cilium[0].name
    namespace = helm_release.cilium[0].namespace
    version   = helm_release.cilium[0].version
    status    = helm_release.cilium[0].status
  } : null
}
