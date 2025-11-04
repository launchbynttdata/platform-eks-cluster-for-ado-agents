# Data sources
# data "aws_region" "current" {}

# Main ADO Agent EKS Cluster Configuration
module "ado_eks_cluster" {
  source = "./modules/collections/ado-eks-cluster"

  # Cluster Configuration
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  eks_addons      = var.eks_addons
  fargate_profile_selectors = concat(var.fargate_profile_selectors, [
    {
      namespace = var.keda_namespace
    },
    {
      namespace = var.ado_agents_namespace
    }
  ])
  fargate_system_profile_selectors = var.fargate_system_profile_selectors

  # Networking
  vpc_id                 = var.vpc_id
  subnet_ids             = var.subnet_ids
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # IAM Configuration
  create_iam_roles          = var.create_iam_roles
  existing_cluster_role_arn = var.existing_cluster_role_arn
  existing_fargate_role_arn = var.existing_fargate_role_arn

  # Security
  create_kms_key                  = var.create_kms_key
  kms_key_arn                     = var.kms_key_arn
  kms_key_description             = var.kms_key_description
  kms_key_deletion_window_in_days = var.kms_key_deletion_window_in_days
  enabled_cluster_log_types       = var.enabled_cluster_log_types

  # KEDA Configuration
  install_keda         = var.install_keda
  keda_namespace       = var.keda_namespace
  keda_version         = var.keda_version
  ado_agents_namespace = var.ado_agents_namespace

  # External Secrets Operator Configuration
  install_eso                    = var.install_eso
  eso_namespace                  = var.eso_namespace
  eso_version                    = var.eso_version
  eso_create_ado_external_secret = var.eso_create_ado_external_secret
  create_cluster_secret_store    = var.create_cluster_secret_store
  create_external_secrets        = var.create_external_secrets
  eso_webhook_enabled            = var.eso_webhook_enabled
  eso_webhook_failure_policy     = var.eso_webhook_failure_policy

  # ADO Configuration
  ado_org              = var.ado_org
  ado_pat_value        = var.ado_pat_value
  ado_pat_secret_name  = var.ado_pat_secret_name
  secret_recovery_days = var.secret_recovery_days
  create_ado_secret    = var.create_ado_secret
  ado_secret_name      = var.ado_secret_name

  # ADO Agent Execution Roles
  create_ado_execution_roles = var.create_ado_execution_roles
  ado_execution_roles        = var.ado_execution_roles

  # VPC Endpoints
  create_vpc_endpoints          = var.create_vpc_endpoints
  vpc_endpoint_services         = var.vpc_endpoint_services
  exclude_vpc_endpoint_services = var.exclude_vpc_endpoint_services
  ec2_node_group                = var.ec2_node_group
  ec2_node_group_policies       = var.ec2_node_group_policies

  # Cluster Autoscaler Configuration
  enable_cluster_autoscaler    = var.enable_cluster_autoscaler
  cluster_autoscaler_version   = var.cluster_autoscaler_version
  cluster_autoscaler_namespace = var.cluster_autoscaler_namespace
  cluster_autoscaler_settings  = var.cluster_autoscaler_settings

  # Tagging
  tags        = local.common_tags
  environment = var.environment
  project     = var.project
}



# Create ECR repositories using the new modular approach
module "ecr" {
  source = "./modules/collections/ecr"

  count = length(local.all_ecr_repositories) > 0 ? 1 : 0

  ecr_repositories       = local.all_ecr_repositories
  cluster_name           = var.cluster_name
  create_iam_policies    = true
  attach_pull_to_fargate = var.create_iam_roles # Only attach if we created the roles
  fargate_role_name      = var.create_iam_roles ? "${var.cluster_name}-fargate-pod-execution-role" : ""
  attach_bastion_policy  = var.bastion_role_arn != ""
  bastion_role_name      = local.bastion_role_name
  tags                   = local.common_tags

  depends_on = [module.ado_eks_cluster]
}
