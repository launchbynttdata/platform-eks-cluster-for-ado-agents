output "use_host_network_for_control_plane_reachability" {
  description = "Whether metrics-server uses hostNetwork for control-plane reachability"
  value       = var.use_host_network_for_control_plane_reachability
}

output "host_network_container_port" {
  description = "HTTPS port used by metrics-server when hostNetwork is enabled"
  value       = var.use_host_network_for_control_plane_reachability ? local.container_port : null
}

output "release_name" {
  description = "Helm release name for metrics-server"
  value       = helm_release.this.name
}
