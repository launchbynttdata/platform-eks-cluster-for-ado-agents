# Base Infrastructure Layer Outputs
#
# These outputs are used by the middleware and application layers
# via remote state data sources.

# Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks_cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes version of the EKS cluster"
  value       = module.eks_cluster.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_cluster.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.security_groups.cluster_security_group_id
}

# OIDC Provider Information
output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC identity provider"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks_cluster.cluster_oidc_issuer_url
}

# IAM Role Information
output "cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = var.create_iam_roles ? module.iam_roles.cluster_role_arn : var.existing_cluster_role_arn
}

output "fargate_role_arn" {
  description = "ARN of the Fargate pod execution role"
  value       = var.create_iam_roles ? module.iam_roles.fargate_role_arn : var.existing_fargate_role_arn
}

output "cluster_role_name" {
  description = "Name of the EKS cluster service role"
  value       = var.create_iam_roles ? module.iam_roles.cluster_role_name : null
}

output "fargate_role_name" {
  description = "Name of the Fargate pod execution role"
  value       = var.create_iam_roles ? module.iam_roles.fargate_role_name : null
}

# Security Group Information
output "fargate_security_group_id" {
  description = "Security group ID for Fargate pods"
  value       = module.security_groups.fargate_security_group_id
}

# KMS Information
output "kms_key_arn" {
  description = "ARN of the KMS key used for EKS encryption"
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for EKS encryption"
  value       = var.create_kms_key ? aws_kms_key.eks_encryption[0].key_id : null
}

# Networking Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = var.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = var.subnet_ids
}

# VPC Endpoints
output "vpc_endpoints" {
  description = "Map of VPC endpoint information"
  value = var.create_vpc_endpoints ? {
    gateway   = module.vpc_endpoints[0].gateway_endpoint_ids
    interface = module.vpc_endpoints[0].interface_endpoint_ids
  } : {}
}

# EC2 Node Groups (if any)
output "ec2_node_group_ids" {
  description = "Map of EC2 node group IDs"
  value = {
    for k, v in module.ec2_nodes : k => v.node_group_id
  }
}

output "ec2_node_group_role_arn" {
  description = "ARN of the EC2 node group IAM role"
  value       = length(var.ec2_node_group) > 0 ? aws_iam_role.ec2_node_group_role[0].arn : null
}

# Cluster Autoscaler
output "cluster_autoscaler_role_arn" {
  description = "ARN of the cluster autoscaler IAM role"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler_role[0].arn : null
}

output "cluster_autoscaler_namespace" {
  description = "Kubernetes namespace for cluster autoscaler"
  value       = var.cluster_autoscaler_namespace
}

# Common Information
output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}