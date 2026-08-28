output "keda_namespace" {
  description = "Name of the KEDA namespace"
  value       = var.namespace
}

output "ado_namespace" {
  description = "Name of the ADO agents namespace"
  value       = var.ado_namespace
}

output "keda_release_name" {
  description = "Name of the KEDA Helm release"
  value       = helm_release.keda.name
}

output "keda_release_status" {
  description = "Status of the KEDA Helm release"
  value       = helm_release.keda.status
}

output "keda_service_account_name" {
  description = "Name of the KEDA service account"
  value       = var.service_account_name
}

output "ado_secret_name" {
  description = "Name of the ADO PAT secret"
  value       = var.create_ado_secret ? kubernetes_secret.ado_pat[0].metadata[0].name : null
}

output "scaled_object_name" {
  description = "Name of the KEDA ScaledObject"
  value       = var.create_scaled_object ? kubernetes_manifest.ado_scaledobject[0].manifest.metadata.name : null
}

output "use_host_network_for_control_plane_reachability" {
  description = "Whether KEDA metrics server and webhooks use hostNetwork for control-plane reachability"
  value       = var.use_host_network_for_control_plane_reachability
}

output "host_network_prometheus_metric_server_port" {
  description = "Prometheus /metrics port for the KEDA metrics server when hostNetwork is enabled"
  value       = var.use_host_network_for_control_plane_reachability ? 9080 : null
}

output "host_network_prometheus_webhooks_port" {
  description = "Prometheus /metrics port for KEDA admission webhooks when hostNetwork is enabled"
  value       = var.use_host_network_for_control_plane_reachability ? 9081 : null
}

output "metrics_server_dns_policy" {
  description = "DNS policy for the KEDA metrics server Helm values"
  value       = local.metrics_server_dns_policy
}
