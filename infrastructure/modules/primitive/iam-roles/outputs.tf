output "cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = var.create_cluster_role ? aws_iam_role.eks_cluster_role[0].arn : null
}

output "fargate_role_arn" {
  description = "ARN of the Fargate pod execution role"
  value       = var.create_fargate_role ? aws_iam_role.fargate_pod_execution_role[0].arn : null
}

output "keda_role_arn" {
  description = "ARN of the KEDA operator role"
  value       = var.create_keda_role ? aws_iam_role.keda_operator_role[0].arn : null
}

output "cluster_role_name" {
  description = "Name of the EKS cluster service role"
  value       = var.create_cluster_role ? aws_iam_role.eks_cluster_role[0].name : null
}

output "fargate_role_name" {
  description = "Name of the Fargate pod execution role"
  value       = var.create_fargate_role ? aws_iam_role.fargate_pod_execution_role[0].name : null
}

output "keda_role_name" {
  description = "Name of the KEDA operator role"
  value       = var.create_keda_role ? aws_iam_role.keda_operator_role[0].name : null
}
