# Local values for common configuration
locals {
  cluster_name = var.cluster_name
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    },
    var.tags
  )
  ado_secret_name = var.ado_secret_name != null && trimspace(var.ado_secret_name) != "" ? var.ado_secret_name : var.ado_pat_secret_name
}

locals {
  ado_external_secret_name = "${local.ado_secret_name}-secret"
}

# Data sources
data "aws_region" "current" {}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = var.subnet_ids
  }
}

data "aws_route_tables" "private" {
  vpc_id = var.vpc_id

  filter {
    name   = "association.subnet-id"
    values = var.subnet_ids
  }
}

# KMS Key for EKS encryption (optional)
data "aws_caller_identity" "current" {}

module "eks_encryption_key" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/kms_key/aws"
  version = "~> 0.1"
  count   = var.create_kms_key ? 1 : 0

  description             = var.kms_key_description
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true
  policy = {
    allow_root_account = {
      sid    = "Enable IAM User Permissions"
      effect = "Allow"
      principals = {
        AWS = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
      }
      actions   = ["kms:*"]
      resources = ["*"]
    }
    allow_eks_service = {
      sid    = "Allow use of the key by EKS"
      effect = "Allow"
      principals = {
        Service = ["eks.amazonaws.com"]
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-eks-encryption-key"
  })
}

resource "aws_kms_alias" "eks_encryption" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.cluster_name}-eks-encryption"
  target_key_id = module.eks_encryption_key[0].key_id
}

# Local value to determine which KMS key to use
locals {
  kms_key_arn = var.create_kms_key ? module.eks_encryption_key[0].arn : var.kms_key_arn
}

# IAM roles for EKS control plane and Fargate
module "eks_cluster_role" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = [
    {
      actions = ["sts:AssumeRole"]
      principals = [
        {
          type        = "Service"
          identifiers = ["eks.amazonaws.com"]
        }
      ]
    }
  ]

  tags = local.common_tags
}

module "eks_cluster_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  role_name  = module.eks_cluster_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

module "eks_vpc_resource_controller_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  role_name  = module.eks_cluster_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

module "fargate_pod_execution_role" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  name = "${local.cluster_name}-fargate-pod-execution-role"

  assume_role_policy = [
    {
      actions = ["sts:AssumeRole"]
      principals = [
        {
          type        = "Service"
          identifiers = ["eks-fargate-pods.amazonaws.com"]
        }
      ]
    }
  ]

  tags = local.common_tags
}

module "fargate_pod_execution_role_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  role_name  = module.fargate_pod_execution_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# Security groups
module "cluster_security_group" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/security_group/aws"
  version = "~> 0.1"

  name                  = local.cluster_name
  security_group_suffix = "cluster"
  description           = "Security group for EKS cluster ${local.cluster_name}"
  vpc_id                = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-cluster-sg"
      Type = "EKS-Cluster"
    }
  )
}

module "cluster_security_group_ingress_vpc" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws"
  version = "~> 0.1"

  security_group_id = module.cluster_security_group.security_group_id
  description       = "Allow HTTPS access from VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags              = merge(local.common_tags, { Name = "${local.cluster_name}-cluster-sg-api" })
}

module "cluster_security_group_egress_all" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_egress_rule/aws"
  version = "~> 0.1"

  security_group_id = module.cluster_security_group.security_group_id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(local.common_tags, { Name = "${local.cluster_name}-cluster-sg-egress" })
}

module "fargate_security_group" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/security_group/aws"
  version = "~> 0.1"

  name                  = local.cluster_name
  security_group_suffix = "fargate-pods"
  description           = "Security group for Fargate pods in EKS cluster ${local.cluster_name}"
  vpc_id                = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-fargate-pods-sg"
      Type = "EKS-Fargate-Pods"
    }
  )
}

module "fargate_security_group_ingress_from_vpc" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws"
  version = "~> 0.1"

  security_group_id = module.fargate_security_group.security_group_id
  description       = "Allow all TCP traffic from VPC"
  ip_protocol       = "tcp"
  from_port         = 0
  to_port           = 65535
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags              = merge(local.common_tags, { Name = "${local.cluster_name}-fargate-sg-vpc" })
}

module "fargate_security_group_egress_all" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_egress_rule/aws"
  version = "~> 0.1"

  security_group_id = module.fargate_security_group.security_group_id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(local.common_tags, { Name = "${local.cluster_name}-fargate-sg-egress" })
}

module "fargate_security_group_egress_https" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_egress_rule/aws"
  version = "~> 0.1"

  security_group_id = module.fargate_security_group.security_group_id
  description       = "Explicit HTTPS outbound for ADO API"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
  tags              = merge(local.common_tags, { Name = "${local.cluster_name}-fargate-sg-https" })
}

module "fargate_security_group_ingress_from_cluster" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws"
  version = "~> 0.1"

  security_group_id            = module.fargate_security_group.security_group_id
  referenced_security_group_id = module.cluster_security_group.security_group_id
  description                  = "Allow communication from EKS cluster to Fargate pods"
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  tags                         = merge(local.common_tags, { Name = "${local.cluster_name}-cluster-to-fargate" })
}

module "cluster_security_group_ingress_from_fargate" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/vpc_security_group_ingress_rule/aws"
  version = "~> 0.1"

  security_group_id            = module.cluster_security_group.security_group_id
  referenced_security_group_id = module.fargate_security_group.security_group_id
  description                  = "Allow Fargate pods to communicate with EKS cluster API"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  tags                         = merge(local.common_tags, { Name = "${local.cluster_name}-fargate-to-cluster" })
}

# EKS Cluster
module "eks_cluster" {
  source = "../../primitive/eks-cluster"

  cluster_name           = local.cluster_name
  cluster_role_arn       = var.create_iam_roles ? module.eks_cluster_role[0].role_arn : var.existing_cluster_role_arn
  cluster_version        = var.cluster_version
  subnet_ids             = var.subnet_ids
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs
  additional_security_group_ids = compact([
    module.cluster_security_group.security_group_id,
    module.fargate_security_group.security_group_id
  ])

  kms_key_arn               = local.kms_key_arn
  enabled_cluster_log_types = var.enabled_cluster_log_types

  # Don't create any addons here - manage all separately after Fargate profiles
  addons = {}

  tags = local.common_tags

  depends_on = [
    module.eks_cluster_role,
    module.eks_cluster_policy_attachment,
    module.eks_vpc_resource_controller_attachment
  ]
}

# Create OIDC provider for IRSA
module "eks_cluster_oidc" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_openid_connect_provider/aws"
  version = "~> 0.1"

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"] # EKS OIDC root CA thumbprint
  url             = module.eks_cluster.cluster_oidc_issuer_url

  tags = local.common_tags
}
# Local values derived from cluster OIDC provider configuration
locals {
  cluster_oidc_host = replace(module.eks_cluster_oidc.url, "https://", "")
}
# resource "aws_iam_openid_connect_provider" "eks" {
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"] # EKS OIDC root CA thumbprint
#   url             = module.eks_cluster.cluster_oidc_issuer_url

#   tags = local.common_tags
# }

# KEDA Operator Role (created after OIDC provider for IRSA)
module "keda_operator_role" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0
  name    = "${local.cluster_name}-keda-operator-role"
  assume_role_policy = [
    {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      principals = [
        {
          type        = "Federated"
          identifiers = [module.eks_cluster_oidc.arn]
        }
      ]
      conditions = [
        {
          test     = "StringEquals"
          variable = "${local.cluster_oidc_host}:sub"
          values = [
            "system:serviceaccount:${var.keda_namespace}:keda-operator"
          ]
        },
        {
          test     = "StringEquals"
          variable = "${local.cluster_oidc_host}:aud"
          values   = ["sts.amazonaws.com"]
        }
      ]
    }
  ]
  tags = local.common_tags
}

# resource "aws_iam_role" "keda_operator_role" {
#   count = var.create_iam_roles ? 1 : 0
#   name  = "${local.cluster_name}-keda-operator-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = aws_iam_openid_connect_provider.eks.arn
#         }
#         Condition = {
#           StringEquals = {
#             "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${var.keda_namespace}:keda-operator"
#             "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })

#   tags = local.common_tags
# }

# KEDA Role Policy for CloudWatch, SQS, and Secrets Manager access
module "keda_operator_policy" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  policy_name = "${local.cluster_name}-keda-operator-policy"

  policy_statement = {
    secrets_manager = {
      sid       = "AllowSecretsManagerAccess"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = [aws_secretsmanager_secret.ado_pat.arn]
    }
    cloudwatch_logs = {
      sid     = "AllowCloudWatchLogs"
      actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      resources = [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.cluster_name}/*",
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:keda-operator-*"
      ]
    }
    sqs_queue_access = {
      sid       = "AllowSQSQueueAccess"
      actions   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      resources = ["arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
    sqs_list_queues = {
      sid       = "AllowSQSListQueues"
      actions   = ["sqs:ListQueues"]
      resources = ["*"]
    }
    cloudwatch_metrics = {
      sid       = "AllowCloudWatchMetrics"
      actions   = ["cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics"]
      resources = ["*"]
    }
  }

  tags = local.common_tags
}

# Attach KEDA policy to KEDA role
module "keda_operator_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  role_name  = module.keda_operator_role[0].role_name
  policy_arn = module.keda_operator_policy[0].policy_arn
}

module "eso_role" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0
  name    = "${local.cluster_name}-external-secrets-role"
  assume_role_policy = [
    {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      principals = [
        {
          type        = "Federated"
          identifiers = [module.eks_cluster_oidc.arn]
        }
      ]
      conditions = [
        {
          test     = "StringEquals"
          variable = "${local.cluster_oidc_host}:sub"
          values = [
            "system:serviceaccount:${var.eso_namespace}:external-secrets"
          ]
        },
        {
          test     = "StringEquals"
          variable = "${local.cluster_oidc_host}:aud"
          values   = ["sts.amazonaws.com"]
        }
      ]
    }
  ]
  tags = local.common_tags
}

# # External Secrets Operator Role (created after OIDC provider for IRSA)
# resource "aws_iam_role" "eso_role" {
#   count = var.create_iam_roles ? 1 : 0
#   name  = "${local.cluster_name}-external-secrets-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = module.eks_cluster_oidc.arn
#         }
#         Condition = {
#           StringEquals = {
#             "${replace(module.eks_cluster_oidc.url, "https://", "")}:sub" = "system:serviceaccount:${var.eso_namespace}:external-secrets"
#             "${replace(module.eks_cluster_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })

#   tags = local.common_tags
# }

# External Secrets Operator Policy for Secrets Manager access
# This policy is scoped to the ADO PAT secret specifically
# To add additional secrets, add their ARNs to the Resource array below
module "eso_policy" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  policy_name = "${local.cluster_name}-external-secrets-policy"

  policy_statement = {
    secrets_manager = {
      sid     = "AllowSecretsManagerAccess"
      actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      # Currently scoped to the ADO PAT secret only
      # To add additional secrets, add their ARNs to this array:
      # Example: [
      #   aws_secretsmanager_secret.ado_pat.arn,
      #   "arn:aws:secretsmanager:region:account:secret:another-secret-name/*"
      # ]
      resources = [aws_secretsmanager_secret.ado_pat.arn]
    }
  }

  tags = local.common_tags
}

# Attach ESO policy to ESO role
module "eso_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_iam_roles ? 1 : 0

  role_name  = module.eso_role[0].name
  policy_arn = module.eso_policy[0].policy_arn
}

# ADO Agent Execution Roles (created after OIDC provider for IRSA)
locals {
  create_managed_ado_roles = var.create_ado_execution_roles && var.create_iam_roles

  ado_managed_role_configs = create_managed_ado_roles ? {
    for key, cfg in var.ado_execution_roles :
    key => cfg
    if try(trimspace(cfg.existing_role_arn), "") == ""
  } : {}

  ado_existing_role_configs = {
    for key, cfg in var.ado_execution_roles :
    key => cfg
    if try(trimspace(cfg.existing_role_arn), "") != ""
  }

  ado_managed_role_configs_with_permissions = {
    for key, cfg in local.ado_managed_role_configs :
    key => cfg
    if length(try(cfg.permissions, [])) > 0
  }

  ado_attached_policy_pairs = local.create_managed_ado_roles ? {
    for attachment in flatten([
      for role_key, cfg in local.ado_managed_role_configs : [
        for policy_index, policy_arn in try(cfg.attach_policy_arns, []) : {
          key        = "${role_key}-${policy_index}"
          role_key   = role_key
          policy_arn = policy_arn
        }
      ]
      ]) : attachment.key => {
      role_key   = attachment.role_key
      policy_arn = attachment.policy_arn
    }
  } : {}
}

module "ado_agent_execution_roles" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source   = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version  = "~> 0.1"
  for_each = local.ado_managed_role_configs

  name = "${local.cluster_name}-ado-agent-${each.key}-role"

  assume_role_policy = [
    {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      principals = [
        {
          type        = "Federated"
          identifiers = [module.eks_cluster_oidc.arn]
        }
      ]
      conditions = [
        {
          test     = "StringEquals"
          variable = "${replace(module.eks_cluster_oidc.url, "https://", "")}:sub"
          values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"]
        },
        {
          test     = "StringEquals"
          variable = "${replace(module.eks_cluster_oidc.url, "https://", "")}:aud"
          values   = ["sts.amazonaws.com"]
        }
      ]
    }
  ]

  tags = merge(local.common_tags, {
    Role = "ADO-Agent-${title(each.key)}"
  })
}

# ADO Agent Execution Role Policies
module "ado_agent_execution_policies" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source   = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version  = "~> 0.1"
  for_each = local.ado_managed_role_configs_with_permissions

  policy_name = "${local.cluster_name}-ado-agent-${each.key}-policy"

  policy_statement = {
    for idx, permission in each.value.permissions : "statement_${idx}" => {
      sid       = try(permission.sid, null)
      actions   = permission.actions
      resources = permission.resources
    }
  }

  tags = merge(local.common_tags, {
    Role = "ADO-Agent-${title(each.key)}"
  })
}

# Attach ADO agent policies to ADO agent roles
module "ado_agent_execution_policy_attachments" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source   = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version  = "~> 0.1"
  for_each = local.ado_managed_role_configs_with_permissions

  role_name  = module.ado_agent_execution_roles[each.key].name
  policy_arn = module.ado_agent_execution_policies[each.key].policy_arn
}

module "ado_agent_execution_existing_policy_attachments" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source   = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version  = "~> 0.1"
  for_each = local.ado_attached_policy_pairs

  role_name  = module.ado_agent_execution_roles[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

locals {
  ado_execution_role_arns = merge(
    local.create_managed_ado_roles ? { for k, v in module.ado_agent_execution_roles : k => v.arn } : {},
    { for k, cfg in local.ado_existing_role_configs : k => cfg.existing_role_arn }
  )

  ado_execution_role_names = merge(
    local.create_managed_ado_roles ? { for k, v in module.ado_agent_execution_roles : k => v.name } : {},
    { for k, cfg in local.ado_existing_role_configs : k => element(reverse(split("/", cfg.existing_role_arn)), 0) }
  )
}

# VPC Endpoints (optional)
module "vpc_endpoints" {
  count  = var.create_vpc_endpoints ? 1 : 0
  source = "../../primitive/vpc-endpoints"

  cluster_name              = local.cluster_name
  vpc_id                    = var.vpc_id
  subnet_ids                = var.subnet_ids
  route_table_ids           = data.aws_route_tables.private.ids
  security_group_ids        = [module.fargate_security_group.security_group_id]
  endpoint_services         = var.vpc_endpoint_services
  exclude_endpoint_services = var.exclude_vpc_endpoint_services

  tags = local.common_tags
}

# Application Fargate profile (KEDA + ESO + ADO agents)
module "fargate_profile" {
  source = "../../primitive/fargate-profile"

  cluster_name           = module.eks_cluster.cluster_name
  profile_name           = "${local.cluster_name}-apps-fargate-profile"
  pod_execution_role_arn = var.create_iam_roles ? module.fargate_pod_execution_role[0].role_arn : var.existing_fargate_role_arn
  subnet_ids             = var.subnet_ids
  selectors              = var.fargate_profile_selectors

  tags = local.common_tags

  depends_on = [
    module.eks_cluster,
    module.fargate_pod_execution_role
  ]
}

# System Fargate profile (CoreDNS only)
module "fargate_profile_system" {
  source                 = "../../primitive/fargate-profile"
  count                  = length(var.fargate_system_profile_selectors) > 0 ? 1 : 0
  cluster_name           = module.eks_cluster.cluster_name
  profile_name           = "${local.cluster_name}-system-fargate-profile"
  pod_execution_role_arn = var.create_iam_roles ? module.fargate_pod_execution_role[0].role_arn : var.existing_fargate_role_arn
  subnet_ids             = var.subnet_ids

  # selectors = [
  #   {
  #     namespace = "kube-system"
  #     labels = {
  #       "k8s-app" = "kube-dns" # Only CoreDNS pods
  #     }
  #   }
  # ]

  selectors = var.fargate_system_profile_selectors

  tags = local.common_tags

  depends_on = [
    module.eks_cluster,
    module.fargate_pod_execution_role
  ]
}

# EKS Addons - created after both Fargate profiles are ready
resource "aws_eks_addon" "addons" {
  for_each = var.eks_addons

  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")
  service_account_role_arn    = try(each.value.service_account_role_arn, null)
  configuration_values        = try(each.value.configuration_values, null)

  depends_on = [
    module.fargate_profile_system, # Wait for system Fargate profile
    module.fargate_profile,        # Wait for application Fargate profile
    module.eks_cluster
  ]

  tags = local.common_tags
}

# AWS Secret for ADO PAT
resource "aws_secretsmanager_secret" "ado_pat" {
  name                    = var.ado_pat_secret_name
  description             = "Personal Access Token for Azure DevOps integration"
  recovery_window_in_days = var.secret_recovery_days
  kms_key_id              = var.kms_key_arn

  tags = merge(
    local.common_tags,
    {
      Purpose = "ADO-Integration"
    }
  )
}

resource "aws_secretsmanager_secret_version" "ado_pat" {
  secret_id = aws_secretsmanager_secret.ado_pat.id
  secret_string = jsonencode({
    personalAccessToken = var.ado_pat_value
    organization        = var.ado_org
  })
}

# KEDA Operator (optional, can be installed separately)
module "keda_operator" {
  count  = var.install_keda ? 1 : 0
  source = "../../primitive/keda-operator"

  cluster_name         = local.cluster_name
  namespace            = var.keda_namespace
  ado_namespace        = var.ado_agents_namespace
  create_namespace     = true
  create_ado_namespace = true
  keda_version         = var.keda_version

  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = var.create_iam_roles ? module.keda_operator_role[0].arn : ""
  }

  create_ado_secret    = var.create_ado_secret
  eso_managed_secret   = var.eso_create_ado_external_secret
  ado_secret_name      = local.ado_secret_name
  create_scaled_object = false # Will be created separately with actual deployment
  tolerations = [{
    key      = "ks.amazonaws.com/compute-type"
    operator = "Equal"
    value    = "fargate"
    effect   = "NoSchedule"
  }]

  depends_on = [
    module.eks_cluster,
    module.fargate_profile,
    # aws_iam_openid_connect_provider.eks
    module.keda_operator_role
  ]
}

# External Secrets Operator (optional, can be installed separately)
module "external_secrets_operator" {
  count  = var.install_eso ? 1 : 0
  source = "../../primitive/external-secrets-operator"

  cluster_name     = local.cluster_name
  namespace        = var.eso_namespace
  create_namespace = true
  eso_version      = var.eso_version
  aws_region       = data.aws_region.current.name

  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = var.create_iam_roles ? module.eso_role[0].arn : ""
  }

  # Webhook configuration - disabled by default for Fargate compatibility
  webhook_enabled       = var.eso_webhook_enabled
  webhook_failurePolicy = var.eso_webhook_failure_policy

  # Create ClusterSecretStore for AWS Secrets Manager
  create_cluster_secret_store = var.create_cluster_secret_store # Set to false initially, then true for custom resources
  cluster_secret_store_name   = "aws-secrets-manager"
  # checkov:skip=CKV_SECRET_6: not a secret

  # Create ExternalSecret for ADO PAT
  create_external_secrets = var.create_external_secrets # Set to false initially, then true for custom resources
  external_secrets = var.eso_create_ado_external_secret ? {
    "${local.ado_external_secret_name}" = {
      namespace        = var.ado_agents_namespace
      secret_name      = local.ado_secret_name
      aws_secret_name  = aws_secretsmanager_secret.ado_pat.name
      refresh_interval = "1h"
      secret_type      = "Opaque"
      data_key_mapping = {
        "personalAccessToken" = "personalAccessToken"
        "organization"        = "organization"
        "adourl"              = "adourl"
      }
    }
  } : {}

  depends_on = [
    module.eks_cluster,
    module.fargate_profile,
    # aws_iam_openid_connect_provider.eks,
    module.eks_cluster_oidc,
    module.keda_operator # Ensure KEDA creates the ADO namespace before ESO tries to use it
  ]
}

module "ec2_nodes" {
  source   = "../../primitive/eks-node-group"
  for_each = var.ec2_node_group

  node_group_name = each.key
  cluster_name    = module.eks_cluster.cluster_name
  node_role_arn   = module.ec2_node_group_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = try(each.value.instance_types, ["t3.medium"])
  disk_size       = try(each.value.disk_size, 50)
  ami_type        = try(each.value.ami_type, null)
  capacity_type   = try(each.value.capacity_type, "ON_DEMAND")
  labels          = try(each.value.labels, {})
  desired_size    = try(each.value.desired_size, 1)
  max_size        = try(each.value.max_size, 3)
  min_size        = try(each.value.min_size, 0)
  taints          = try(each.value.taints, [])

  # Cluster Autoscaler Configuration
  enable_cluster_autoscaler = var.enable_cluster_autoscaler
  cluster_autoscaler_tags = var.enable_cluster_autoscaler ? merge(
    {
      "k8s.io/cluster-autoscaler/node-template/label/eks.amazonaws.com/compute-type" = "ec2"
    },
    # Dynamically create taint labels from the actual taints configuration
    {
      for taint in try(each.value.taints, []) :
      "k8s.io/cluster-autoscaler/node-template/taint/${taint.key}" => "${taint.value}:${taint.effect}"
    },
    # Dynamically create labels from the actual labels configuration
    {
      for label_key, label_value in coalesce(each.value.labels, {}) :
      "k8s.io/cluster-autoscaler/node-template/label/${label_key}" => label_value
    }
  ) : {}

  tags = merge(
    local.common_tags,
    {
      Name = each.key
    },
    try(each.value.tags, {})
  )
}

module "ec2_node_group_role" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  name    = "eks-buildkit-nodes"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# resource "aws_iam_role" "ec2_node_group_role" {
#   name = "eks-buildkit-nodes"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

module "ec2_node_group_policy_attachments" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source   = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version  = "~> 0.1"
  for_each = toset(var.ec2_node_group_policies)

  role_name  = module.ec2_node_group_role.name
  policy_arn = each.value
}

# module "ec2_node_group_sg" {
#   source = "../../primitive/security-group"
#   name   = "${local.cluster_name}-ec2-node-group-sg"
#   security_group_suffix = "ec2-node-group"
#   vpc_id = var.vpc_id
#   description = "Security group for EKS EC2 node group"
#   ingress_rules = [
#     for subnet in data.aws_subnets.selected.subnets :
#     {
#       name = "allow-metrics-server"
#       from_port   = 10250
#       to_port     = 10250
#       protocol    = "tcp"
#       cidr_ipv4   = subnet.cidr_block
#       description = "Allow metrics server access from within the VPC"
#     }]
# }

module "cluster_autoscaler_role" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.enable_cluster_autoscaler ? 1 : 0
  name    = "${local.cluster_name}-cluster-autoscaler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks_cluster_oidc.arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks_cluster_oidc.url, "https://", "")}:sub" = "system:serviceaccount:${var.cluster_autoscaler_namespace}:cluster-autoscaler"
            "${replace(module.eks_cluster_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
  tags = local.common_tags
}

# # Cluster Autoscaler IAM Role (only created if autoscaler is enabled)
# resource "aws_iam_role" "cluster_autoscaler_role" {
#   count = var.enable_cluster_autoscaler ? 1 : 0
#   name  = "${local.cluster_name}-cluster-autoscaler-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Effect = "Allow"
#         Principal = {
#           Federated = module.eks_cluster_oidc.arn
#         }
#         Condition = {
#           StringEquals = {
#             "${replace(module.eks_cluster_oidc.url, "https://", "")}:sub" = "system:serviceaccount:${var.cluster_autoscaler_namespace}:cluster-autoscaler"
#             "${replace(module.eks_cluster_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })

#   tags = local.common_tags
# }

module "cluster_autoscaler_policy" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = var.enable_cluster_autoscaler ? 1 : 0

  policy_name = "${local.cluster_name}-cluster-autoscaler-policy"

  policy_statement = {
    autoscaling_and_ec2 = {
      sid = "AllowAutoscalingAndEC2Actions"
      actions = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "eks:DescribeNodegroup"
      ]
      resources = ["*"]
    }
  }

  tags = local.common_tags
}

module "cluster_autoscaler_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.enable_cluster_autoscaler ? 1 : 0

  role_name  = module.cluster_autoscaler_role[0].name
  policy_arn = module.cluster_autoscaler_policy[0].policy_arn
}
