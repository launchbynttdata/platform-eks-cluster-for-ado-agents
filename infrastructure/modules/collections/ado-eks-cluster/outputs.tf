output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = module.eks_cluster.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks_cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version of the EKS cluster"
  value       = module.eks_cluster.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_cluster.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "The cluster security group that was created by Amazon EKS for the cluster"
  value       = module.eks_cluster.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks_cluster.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks_cluster_oidc.arn
}

# IAM Role outputs
output "cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = var.create_iam_roles ? module.iam_roles.cluster_role_arn : var.existing_cluster_role_arn
}

output "fargate_role_arn" {
  description = "ARN of the Fargate pod execution role"
  value       = var.create_iam_roles ? module.iam_roles.fargate_role_arn : var.existing_fargate_role_arn
}

output "keda_role_arn" {
  description = "ARN of the KEDA operator role"
  value       = var.create_iam_roles ? module.keda_operator_role[0].arn : null
}

# Security Group outputs
output "additional_security_group_ids" {
  description = "List of additional security group IDs attached to the cluster"
  value = compact([
    module.cluster_security_group.security_group_id,
    module.fargate_security_group.security_group_id
  ])
}

output "fargate_security_group_id" {
  description = "ID of the Fargate pods security group"
  value       = module.fargate_security_group.security_group_id
}

# Fargate Profile outputs
output "fargate_profile_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Fargate Profile"
  value       = module.fargate_profile.fargate_profile_arn
}

output "fargate_profile_status" {
  description = "Status of the EKS Fargate Profile"
  value       = module.fargate_profile.fargate_profile_status
}

# VPC Endpoints outputs
output "vpc_endpoint_ids" {
  description = "List of VPC endpoint IDs"
  value       = var.create_vpc_endpoints ? module.vpc_endpoints[0].all_endpoint_ids : []
}

# Secret outputs
output "ado_pat_secret_arn" {
  description = "ARN of the AWS Secret containing ADO PAT"
  value       = aws_secretsmanager_secret.ado_pat.arn
}

output "ado_pat_secret_name" {
  description = "Name of the AWS Secret containing ADO PAT"
  value       = aws_secretsmanager_secret.ado_pat.name
}

output "ado_secret_name" {
  description = "Name of the Kubernetes secret for ADO PAT"
  value       = local.ado_secret_name
}

# KEDA outputs
output "keda_namespace" {
  description = "Name of the KEDA namespace"
  value       = var.install_keda ? module.keda_operator[0].keda_namespace : var.keda_namespace
}

output "ado_namespace" {
  description = "Name of the ADO agents namespace"
  value       = var.install_keda ? module.keda_operator[0].ado_namespace : var.ado_agents_namespace
}

output "keda_service_account_name" {
  description = "Name of the KEDA service account"
  value       = var.install_keda ? module.keda_operator[0].keda_service_account_name : null
}

# Connection information
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks_cluster.cluster_name}"
}

output "cluster_info" {
  description = "Cluster information summary"
  value = {
    cluster_name     = module.eks_cluster.cluster_name
    cluster_endpoint = module.eks_cluster.cluster_endpoint
    cluster_version  = module.eks_cluster.cluster_version
    fargate_profile  = module.fargate_profile.fargate_profile_name
    keda_installed   = var.install_keda
    vpc_endpoints    = var.create_vpc_endpoints
    ado_organization = var.ado_org
  }
}

# KMS Key outputs
output "kms_key_arn" {
  description = "ARN of the KMS key used for EKS encryption"
  value       = local.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for EKS encryption"
  value       = var.create_kms_key ? aws_kms_key.eks_encryption[0].key_id : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for EKS encryption"
  value       = var.create_kms_key ? aws_kms_alias.eks_encryption[0].name : null
}

# External Secrets Operator outputs
output "eso_role_arn" {
  description = "ARN of the External Secrets Operator IAM role"
  value       = var.create_iam_roles && var.install_eso ? module.eso_role[0].arn : null
}

output "eso_namespace" {
  description = "Namespace where External Secrets Operator is installed"
  value       = var.install_eso ? var.eso_namespace : null
}

output "eso_cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore for AWS Secrets Manager"
  value       = var.install_eso ? "aws-secrets-manager" : null
}

# ADO Agent Execution Roles outputs
output "ado_agent_execution_role_arns" {
  description = "ARNs of the ADO agent execution IAM roles"
  value       = var.create_ado_execution_roles && var.create_iam_roles ? { for k, v in module.ado_agent_execution_roles : k => v.arn } : {}
}

output "ado_agent_execution_role_names" {
  description = "Names of the ADO agent execution IAM roles"
  value       = var.create_ado_execution_roles && var.create_iam_roles ? { for k, v in module.ado_agent_execution_roles : k => v.name } : {}
}

output "ado_agent_service_account_annotations" {
  description = "Service account annotations for ADO agent roles (for Kubernetes ServiceAccount configuration)"
  value = var.create_ado_execution_roles && var.create_iam_roles ? {
    for role_name, role_config in var.ado_execution_roles : role_config.service_account_name => {
      "eks.amazonaws.com/role-arn" = module.ado_agent_execution_roles[role_name].arn
    }
  } : {}
}

# Cluster Autoscaler outputs
output "cluster_autoscaler_role_arn" {
  description = "ARN of the cluster autoscaler IAM role"
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler_role[0].arn : null
}

output "cluster_autoscaler_role_name" {
  description = "Name of the cluster autoscaler IAM role"
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler_role[0].name : null
}

output "cluster_autoscaler_enabled" {
  description = "Whether cluster autoscaler is enabled"
  value       = var.enable_cluster_autoscaler
}
