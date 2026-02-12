output "namespace" {
  description = "The namespace where External Secrets Operator is installed"
  value       = var.namespace
}

output "service_account_name" {
  description = "The name of the External Secrets Operator service account"
  value       = var.service_account_name
}

output "cluster_secret_store_name" {
  description = "The name of the ClusterSecretStore"
  value       = var.create_cluster_secret_store ? var.cluster_secret_store_name : null
}

output "helm_release_name" {
  description = "The name of the Helm release"
  value       = helm_release.external_secrets.name
}

output "helm_release_status" {
  description = "The status of the Helm release"
  value       = helm_release.external_secrets.status
}

output "external_secrets_created" {
  description = "Map of ExternalSecret resources created"
  value       = var.create_external_secrets ? keys(var.external_secrets) : []
}
