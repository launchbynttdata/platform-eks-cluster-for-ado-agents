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
