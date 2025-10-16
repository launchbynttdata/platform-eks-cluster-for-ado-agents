output "fargate_profile_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Fargate Profile"
  value       = aws_eks_fargate_profile.this.arn
}

output "fargate_profile_name" {
  description = "Name of the EKS Fargate Profile"
  value       = aws_eks_fargate_profile.this.fargate_profile_name
}

output "fargate_profile_status" {
  description = "Status of the EKS Fargate Profile"
  value       = aws_eks_fargate_profile.this.status
}

output "fargate_profile_tags" {
  description = "A map of tags assigned to the resource"
  value       = aws_eks_fargate_profile.this.tags_all
}
