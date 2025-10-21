output "pull_policy_arn" {
  description = "ARN of the ECR pull policy"
  value       = var.create_pull_policy ? aws_iam_policy.ecr_pull_policy[0].arn : ""
}

output "pull_policy_name" {
  description = "Name of the ECR pull policy"
  value       = var.create_pull_policy ? aws_iam_policy.ecr_pull_policy[0].name : ""
}

output "bastion_policy_arn" {
  description = "ARN of the ECR bastion policy"
  value       = var.create_bastion_policy ? aws_iam_policy.ecr_bastion_policy[0].arn : ""
}

output "bastion_policy_name" {
  description = "Name of the ECR bastion policy"
  value       = var.create_bastion_policy ? aws_iam_policy.ecr_bastion_policy[0].name : ""
}

output "fargate_attachment_id" {
  description = "ID of the Fargate role policy attachment"
  value       = var.attach_pull_to_fargate && var.create_pull_policy ? aws_iam_role_policy_attachment.ecr_pull_to_fargate[0].id : ""
}

output "bastion_attachment_id" {
  description = "ID of the bastion role policy attachment"
  value       = var.attach_bastion_policy && var.create_bastion_policy ? aws_iam_role_policy_attachment.ecr_bastion_policy[0].id : ""
}
