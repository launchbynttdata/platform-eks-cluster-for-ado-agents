# Middleware Layer Outputs
#
# These outputs are used by the application layer via remote state data sources.

# KEDA Information
output "keda_namespace" {
  description = "Kubernetes namespace where KEDA is installed"
  value       = var.keda_namespace
}

output "keda_operator_role_arn" {
  description = "ARN of the KEDA operator IAM role"
  value       = module.keda_operator_role.role_arn
}

output "keda_installed" {
  description = "Whether KEDA operator is installed"
  value       = var.install_keda
}

# External Secrets Operator Information
output "eso_namespace" {
  description = "Kubernetes namespace where External Secrets Operator is installed"
  value       = var.eso_namespace
}

output "eso_service_account_name" {
  description = "Name of the External Secrets Operator service account"
  value       = var.install_eso ? module.external_secrets_operator[0].service_account_name : "external-secrets"
}

output "eso_role_arn" {
  description = "ARN of the External Secrets Operator IAM role"
  value       = module.eso_role.role_arn
}

output "eso_installed" {
  description = "Whether External Secrets Operator is installed"
  value       = var.install_eso
}

output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore for AWS Secrets Manager"
  value       = var.cluster_secret_store_name
}

# CloudWatch Logging / Observability
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups created for platform observability"
  value = var.enable_cloudwatch_observability ? concat(
    [for group in aws_cloudwatch_log_group.platform : group.name],
    [for group in aws_cloudwatch_log_group.fargate_fluentbit : group.name]
  ) : []
}

output "cloudwatch_observability_addon_enabled" {
  description = "Whether the Amazon CloudWatch Observability EKS add-on is enabled"
  value       = var.enable_cloudwatch_observability && var.enable_cloudwatch_observability_addon
}

# ADO Agents Namespace
output "ado_agents_namespace" {
  description = "Kubernetes namespace for ADO agents"
  value       = var.ado_agents_namespace
}

output "ado_secret_name" {
  description = "Name of the Kubernetes secret for ADO PAT"
  value       = var.ado_secret_name
}

# Buildkitd Information
output "buildkitd_enabled" {
  description = "Whether buildkitd service is enabled"
  value       = var.enable_buildkitd
}

output "buildkitd_namespace" {
  description = "Kubernetes namespace for buildkitd service"
  value       = var.buildkitd_namespace
}

output "buildkitd_service_name" {
  description = "Name of the buildkitd Kubernetes service"
  value       = var.enable_buildkitd ? "buildkitd" : null
}

output "buildkitd_service_endpoint" {
  description = "Buildkitd service endpoint for use by other pods"
  value       = var.enable_buildkitd ? "${kubernetes_service.buildkitd[0].metadata[0].name}.${var.buildkitd_namespace}.svc.cluster.local:1234" : null
}

output "buildkitd_service_alias" {
  description = "Buildkitd service alias in ado-agents namespace (for convenience)"
  value       = var.enable_buildkitd ? "buildkitd.${var.ado_agents_namespace}.svc.cluster.local:1234" : null
}

output "buildkitd_short_name" {
  description = "Short name for buildkitd service (usable from ado-agents namespace)"
  value       = var.enable_buildkitd ? "buildkitd:1234" : null
}

output "buildkit_irsa_role_arn" {
  description = "IRSA role for buildkitd pods; add to cross-account ECR repository policies when the daemon pushes to other accounts"
  value       = var.enable_buildkitd ? module.buildkit_irsa_role[0].role_arn : null
}

output "ecr_pull_through_cache_rules" {
  description = "ECR pull-through cache rules created by the middleware layer"
  value = {
    for prefix, rule in aws_ecr_pull_through_cache_rule.cache : prefix => {
      upstream_registry_url = rule.upstream_registry_url
      registry_id           = rule.registry_id
    }
  }
}

output "ecr_pull_through_cache_repository_templates" {
  description = "ECR repository creation templates applied to pull-through cache-created repositories"
  value = {
    for prefix, template in aws_ecr_repository_creation_template.pull_through_cache : prefix => {
      registry_id = template.registry_id
      prefix      = template.prefix
    }
  }
}

output "buildkitd_effective_registry_mirrors" {
  description = "Registry mirror configuration rendered into buildkitd.toml, including mirrors derived from ECR pull-through cache rules"
  value       = local.buildkitd_effective_registry_mirrors
}

# Common Information
output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

output "cluster_name" {
  description = "Name of the EKS cluster (from base layer)"
  value       = local.cluster_name
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}
