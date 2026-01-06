output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.repository.name
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.repository.arn
}

output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.repository.repository_url
}

output "registry_id" {
  description = "Registry ID of the ECR repository"
  value       = aws_ecr_repository.repository.registry_id
}

output "lifecycle_policy_text" {
  description = "The lifecycle policy text applied to the repository"
  value       = aws_ecr_lifecycle_policy.policy.policy
}
