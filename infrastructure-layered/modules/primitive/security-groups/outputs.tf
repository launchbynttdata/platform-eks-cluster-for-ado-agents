output "cluster_security_group_id" {
  description = "ID of the EKS cluster security group"
  value       = var.create_cluster_sg ? aws_security_group.eks_cluster[0].id : null
}

output "fargate_security_group_id" {
  description = "ID of the Fargate pods security group"
  value       = var.create_fargate_sg ? aws_security_group.fargate_pods[0].id : null
}

output "cluster_security_group_arn" {
  description = "ARN of the EKS cluster security group"
  value       = var.create_cluster_sg ? aws_security_group.eks_cluster[0].arn : null
}

output "fargate_security_group_arn" {
  description = "ARN of the Fargate pods security group"
  value       = var.create_fargate_sg ? aws_security_group.fargate_pods[0].arn : null
}

output "security_group_ids" {
  description = "List of all created security group IDs"
  value = compact([
    var.create_cluster_sg ? aws_security_group.eks_cluster[0].id : "",
    var.create_fargate_sg ? aws_security_group.fargate_pods[0].id : ""
  ])
}
