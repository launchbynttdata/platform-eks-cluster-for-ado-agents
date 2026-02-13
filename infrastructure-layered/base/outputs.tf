# Base Infrastructure Layer Outputs
#
# These outputs are used by the middleware and application layers
# via remote state data sources.

# Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks_cluster.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks_cluster.arn
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks_cluster.endpoint
}

output "cluster_version" {
  description = "The Kubernetes version of the EKS cluster"
  value       = module.eks_cluster.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_cluster.certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.cluster_security_group.id
}

# OIDC Provider Information
output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC identity provider"
  value       = module.eks_cluster_oidc.arn
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks_cluster.identity_oidc_issuer
}

# IAM Role Information
output "cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = var.create_iam_roles ? module.eks_cluster_role[0].role_arn : var.existing_cluster_role_arn
}

output "fargate_role_arn" {
  description = "ARN of the Fargate pod execution role"
  value       = var.create_iam_roles ? module.fargate_pod_execution_role[0].role_arn : var.existing_fargate_role_arn
}

output "cluster_role_name" {
  description = "Name of the EKS cluster service role"
  value       = var.create_iam_roles ? module.eks_cluster_role[0].role_name : null
}

output "fargate_role_name" {
  description = "Name of the Fargate pod execution role"
  value       = var.create_iam_roles ? module.fargate_pod_execution_role[0].role_name : null
}

# Security Group Information
output "fargate_security_group_id" {
  description = "Security group ID for Fargate pods"
  value       = module.fargate_security_group.id
}

# KMS Information
output "kms_key_arn" {
  description = "ARN of the shared KMS key used for cluster encryption (EKS, Secrets Manager, ECR)"
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the shared KMS key used for cluster encryption"
  value       = local.kms_key_id
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
  value       = length(var.ec2_node_group) > 0 ? module.ec2_node_group_role[0].role_arn : null
}

# Cluster Autoscaler
output "cluster_autoscaler_role_arn" {
  description = "ARN of the cluster autoscaler IAM role"
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler_role[0].role_arn : null
}

output "cluster_autoscaler_namespace" {
  description = "Kubernetes namespace for cluster autoscaler"
  value       = var.cluster_autoscaler_namespace
}

output "cluster_autoscaler_version" {
  description = "Container image version for the Cluster Autoscaler"
  value       = var.cluster_autoscaler_version
}

output "cluster_autoscaler_extra_args" {
  description = "Additional CLI arguments to append to the Cluster Autoscaler command"
  value       = var.cluster_autoscaler_extra_args
}

output "node_auto_heal_enabled" {
  description = "Whether AWS Node Termination Handler infrastructure is enabled"
  value       = var.enable_node_auto_heal
}

output "node_auto_heal_role_arn" {
  description = "IAM role ARN used by the Node Termination Handler service account"
  value       = var.enable_node_auto_heal ? module.node_auto_heal_role[0].role_arn : null
}

output "node_auto_heal_queue_url" {
  description = "URL of the SQS queue that receives EC2/ASG termination events"
  value       = var.enable_node_auto_heal ? aws_sqs_queue.node_auto_heal[0].url : null
}

output "node_auto_heal_queue_arn" {
  description = "ARN of the SQS queue that receives EC2/ASG termination events"
  value       = var.enable_node_auto_heal ? aws_sqs_queue.node_auto_heal[0].arn : null
}

output "node_auto_heal_namespace" {
  description = "Namespace where the Node Termination Handler is deployed"
  value       = var.node_auto_heal_namespace
}

output "node_auto_heal_service_account" {
  description = "Service account name expected by the Node Termination Handler"
  value       = local.node_auto_heal_service_account
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
