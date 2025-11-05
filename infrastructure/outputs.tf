output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = module.ado_eks_cluster.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.ado_eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.ado_eks_cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = module.ado_eks_cluster.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version of the EKS cluster"
  value       = module.ado_eks_cluster.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate data required to communicate with the cluster"
  value       = module.ado_eks_cluster.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "The cluster security group that was created by Amazon EKS for the cluster"
  value       = module.ado_eks_cluster.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.ado_eks_cluster.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.ado_eks_cluster.oidc_provider_arn
}

# IAM Role outputs
output "cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = module.ado_eks_cluster.cluster_role_arn
}

output "fargate_role_arn" {
  description = "ARN of the Fargate pod execution role"
  value       = module.ado_eks_cluster.fargate_role_arn
}

output "keda_role_arn" {
  description = "ARN of the KEDA operator role"
  value       = module.ado_eks_cluster.keda_role_arn
}

# Security Group outputs
output "additional_security_group_ids" {
  description = "List of additional security group IDs attached to the cluster"
  value       = module.ado_eks_cluster.additional_security_group_ids
}

output "fargate_security_group_id" {
  description = "ID of the Fargate pods security group"
  value       = module.ado_eks_cluster.fargate_security_group_id
}

# Fargate Profile outputs
output "fargate_profile_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Fargate Profile"
  value       = module.ado_eks_cluster.fargate_profile_arn
}

output "fargate_profile_status" {
  description = "Status of the EKS Fargate Profile"
  value       = module.ado_eks_cluster.fargate_profile_status
}

# VPC Endpoints outputs
output "vpc_endpoint_ids" {
  description = "List of VPC endpoint IDs"
  value       = module.ado_eks_cluster.vpc_endpoint_ids
}

# Secret outputs
output "ado_pat_secret_arn" {
  description = "ARN of the AWS Secret containing ADO PAT"
  value       = module.ado_eks_cluster.ado_pat_secret_arn
}

output "ado_pat_secret_name" {
  description = "Name of the AWS Secret containing ADO PAT"
  value       = module.ado_eks_cluster.ado_pat_secret_name
}

output "ado_secret_name" {
  description = "Name of the Kubernetes secret for ADO PAT"
  value       = module.ado_eks_cluster.ado_secret_name
}

# KEDA outputs
output "keda_namespace" {
  description = "Name of the KEDA namespace"
  value       = module.ado_eks_cluster.keda_namespace
}

output "ado_namespace" {
  description = "Name of the ADO agents namespace"
  value       = module.ado_eks_cluster.ado_namespace
}

output "keda_service_account_name" {
  description = "Name of the KEDA service account"
  value       = module.ado_eks_cluster.keda_service_account_name
}

# Connection information
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = module.ado_eks_cluster.kubectl_config_command
}

output "cluster_info" {
  description = "Cluster information summary"
  value       = module.ado_eks_cluster.cluster_info
}

# KMS Key outputs
output "kms_key_arn" {
  description = "ARN of the KMS key used for EKS encryption"
  value       = module.ado_eks_cluster.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for EKS encryption"
  value       = module.ado_eks_cluster.kms_key_id
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for EKS encryption"
  value       = module.ado_eks_cluster.kms_key_alias
}

# External Secrets Operator outputs
output "eso_role_arn" {
  description = "ARN of the External Secrets Operator IAM role"
  value       = module.ado_eks_cluster.eso_role_arn
}

output "eso_namespace" {
  description = "Namespace where External Secrets Operator is installed"
  value       = module.ado_eks_cluster.eso_namespace
}

output "eso_cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore for AWS Secrets Manager"
  value       = module.ado_eks_cluster.eso_cluster_secret_store_name
}

# ECR Outputs (both legacy single-repository and new multi-repository)
# Legacy outputs for backward compatibility
output "ecr_repository_name" {
  value       = length(module.ecr) > 0 ? module.ecr[0].repository_name : ""
  description = "Name of the created ECR repository (empty if not created)"
}

output "ecr_repository_arn" {
  value       = length(module.ecr) > 0 ? module.ecr[0].repository_arn : ""
  description = "ARN of the created ECR repository (empty if not created)"
}

output "ecr_registry_id" {
  value       = length(module.ecr) > 0 ? module.ecr[0].registry_id : ""
  description = "ECR Registry ID for the created repository (empty if not created)"
}

output "ecr_repository_url" {
  value       = length(module.ecr) > 0 ? module.ecr[0].repository_url : ""
  description = "Repository URL (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com/repo)"
}

output "ecr_bastion_policy_arn" {
  value       = length(module.ecr) > 0 ? module.ecr[0].bastion_policy_arn : ""
  description = "ARN of the ECR bastion policy for push/pull permissions (empty if not created)"
}

# New multi-repository outputs
output "ecr_repository_arns" {
  value       = length(module.ecr) > 0 ? module.ecr[0].repository_arns : {}
  description = "Map of ECR repository ARNs"
}

output "ecr_repository_urls" {
  value       = length(module.ecr) > 0 ? module.ecr[0].repository_urls : {}
  description = "Map of ECR repository URLs"
}

output "ecr_repository_names" {
  value       = length(module.ecr) > 0 ? module.ecr[0].repository_names : {}
  description = "Map of ECR repository names"
}

output "ecr_pull_policy_arn" {
  value       = length(module.ecr) > 0 ? module.ecr[0].pull_policy_arn : ""
  description = "ARN of the ECR pull policy (empty if not created)"
}

# ADO Agent Execution Roles outputs
output "ado_agent_execution_role_arns" {
  description = "ARNs of the ADO agent execution IAM roles"
  value       = module.ado_eks_cluster.ado_agent_execution_role_arns
}

output "ado_agent_execution_role_names" {
  description = "Names of the ADO agent execution IAM roles"
  value       = module.ado_eks_cluster.ado_agent_execution_role_names
}

output "ado_agent_service_account_annotations" {
  description = "Service account annotations for ADO agent roles (for Kubernetes ServiceAccount configuration)"
  value       = module.ado_eks_cluster.ado_agent_service_account_annotations
}

# Cluster Autoscaler outputs
output "cluster_autoscaler_role_arn" {
  description = "ARN of the cluster autoscaler IAM role"
  value       = module.ado_eks_cluster.cluster_autoscaler_role_arn
}

output "cluster_autoscaler_role_name" {
  description = "Name of the cluster autoscaler IAM role"
  value       = module.ado_eks_cluster.cluster_autoscaler_role_name
}

output "cluster_autoscaler_enabled" {
  description = "Whether cluster autoscaler is enabled"
  value       = module.ado_eks_cluster.cluster_autoscaler_enabled
}
