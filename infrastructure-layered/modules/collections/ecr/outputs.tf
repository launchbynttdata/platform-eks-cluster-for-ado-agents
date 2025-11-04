output "repository_arns" {
  description = "Map of repository ARNs"
  value       = { for k, repo in module.ecr_repositories : k => repo.repository_arn }
}

output "repository_urls" {
  description = "Map of repository URLs"
  value       = { for k, repo in module.ecr_repositories : k => repo.repository_url }
}

output "repository_names" {
  description = "Map of repository names"
  value       = { for k, repo in module.ecr_repositories : k => repo.repository_name }
}

output "registry_ids" {
  description = "Map of registry IDs"
  value       = { for k, repo in module.ecr_repositories : k => repo.registry_id }
}

output "pull_policy_arn" {
  description = "ARN of the ECR pull policy"
  value       = var.create_iam_policies && length(var.ecr_repositories) > 0 ? module.ecr_pull_policy[0].policy_arn : ""
}

output "bastion_policy_arn" {
  description = "ARN of the ECR bastion policy"
  value       = var.create_iam_policies && length(var.ecr_repositories) > 0 ? module.ecr_bastion_policy[0].policy_arn : ""
}

# Backward compatibility outputs for single repository
output "repository_name" {
  description = "Name of the first ECR repository (for backward compatibility)"
  value       = length(var.ecr_repositories) > 0 ? values(module.ecr_repositories)[0].repository_name : ""
}

output "repository_arn" {
  description = "ARN of the first ECR repository (for backward compatibility)"
  value       = length(var.ecr_repositories) > 0 ? values(module.ecr_repositories)[0].repository_arn : ""
}

output "repository_url" {
  description = "URL of the first ECR repository (for backward compatibility)"
  value       = length(var.ecr_repositories) > 0 ? values(module.ecr_repositories)[0].repository_url : ""
}

output "registry_id" {
  description = "Registry ID of the first ECR repository (for backward compatibility)"
  value       = length(var.ecr_repositories) > 0 ? values(module.ecr_repositories)[0].registry_id : ""
}
