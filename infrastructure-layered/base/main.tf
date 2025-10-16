# Base Infrastructure Layer - EKS Cluster Foundation
#
# This layer creates the foundational EKS cluster infrastructure including:
# - EKS Cluster
# - IAM Roles and Policies (cluster, Fargate, node groups)
# - Security Groups
# - KMS Keys for encryption
# - VPC Endpoints
# - Fargate Profiles
# - EKS Add-ons
# - EC2 Node Groups (optional)
# - Cluster Autoscaler (optional)
#
# This layer has NO dependencies on middleware or application components.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  
  # REVIEW: Remote state configuration - requires S3 bucket to be created externally
  backend "s3" {
    # These values should be configured via terraform init -backend-config
    # or environment variables:
    # - bucket: S3 bucket for state storage
    # - key: "base/terraform.tfstate" 
    # - region: AWS region
    # - dynamodb_table: DynamoDB table for state locking (optional)
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

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

# Local values
locals {
  cluster_name = var.cluster_name
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
      Layer       = "base-infrastructure"
    },
    var.tags
  )
}

# KMS Key for EKS encryption
resource "aws_kms_key" "eks_encryption" {
  count = var.create_kms_key ? 1 : 0

  description             = var.kms_key_description
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key by EKS"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-eks-encryption-key"
  })
}

resource "aws_kms_alias" "eks_encryption" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.cluster_name}-eks-encryption"
  target_key_id = aws_kms_key.eks_encryption[0].key_id
}

# Local value to determine which KMS key to use
locals {
  kms_key_arn = var.create_kms_key ? aws_kms_key.eks_encryption[0].arn : var.kms_key_arn
}

# IAM roles for EKS cluster and Fargate
# REVIEW: Using existing primitive modules for consistency
module "iam_roles" {
  source = "../../infrastructure/modules/primitive/iam-roles"

  cluster_name        = local.cluster_name
  create_cluster_role = var.create_iam_roles
  create_fargate_role = var.create_iam_roles
  create_keda_role    = false # KEDA role will be created in middleware layer
  keda_namespace      = ""    # Not needed in base layer
  ado_pat_secret_arn  = ""    # Secret will be created in application layer

  tags = local.common_tags
}

# Security groups
module "security_groups" {
  source = "../../infrastructure/modules/primitive/security-groups"

  cluster_name        = local.cluster_name
  vpc_id              = var.vpc_id
  vpc_cidr            = data.aws_vpc.selected.cidr_block
  create_cluster_sg   = true
  create_fargate_sg   = true
  allowed_cidr_blocks = [data.aws_vpc.selected.cidr_block]

  tags = local.common_tags
}

# EKS Cluster
module "eks_cluster" {
  source = "../../infrastructure/modules/primitive/eks-cluster"

  cluster_name           = local.cluster_name
  cluster_role_arn       = var.create_iam_roles ? module.iam_roles.cluster_role_arn : var.existing_cluster_role_arn
  cluster_version        = var.cluster_version
  subnet_ids             = var.subnet_ids
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs
  additional_security_group_ids = compact([
    module.security_groups.cluster_security_group_id,
    module.security_groups.fargate_security_group_id
  ])

  kms_key_arn               = local.kms_key_arn
  enabled_cluster_log_types = var.enabled_cluster_log_types

  # Don't create any addons here - manage all separately after Fargate profiles
  addons = {}

  tags = local.common_tags

  depends_on = [module.iam_roles]
}

# Create OIDC provider for IRSA
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"] # EKS OIDC root CA thumbprint
  url             = module.eks_cluster.cluster_oidc_issuer_url

  tags = local.common_tags
}

# VPC Endpoints (optional)
module "vpc_endpoints" {
  count  = var.create_vpc_endpoints ? 1 : 0
  source = "../../infrastructure/modules/primitive/vpc-endpoints"

  cluster_name              = local.cluster_name
  vpc_id                    = var.vpc_id
  subnet_ids                = var.subnet_ids
  route_table_ids           = data.aws_route_tables.private.ids
  security_group_ids        = [module.security_groups.fargate_security_group_id]
  endpoint_services         = var.vpc_endpoint_services
  exclude_endpoint_services = var.exclude_vpc_endpoint_services

  tags = local.common_tags
}

# Application Fargate profile (for middleware and applications)
module "fargate_profile" {
  source = "../../infrastructure/modules/primitive/fargate-profile"

  cluster_name           = module.eks_cluster.cluster_name
  profile_name           = "${local.cluster_name}-apps-fargate-profile"
  pod_execution_role_arn = var.create_iam_roles ? module.iam_roles.fargate_role_arn : var.existing_fargate_role_arn
  subnet_ids             = var.subnet_ids
  selectors              = var.fargate_profile_selectors

  tags = local.common_tags

  depends_on = [
    module.eks_cluster,
    module.iam_roles
  ]
}

# System Fargate profile (CoreDNS only)
module "fargate_profile_system" {
  count = length(var.fargate_system_profile_selectors) > 0 ? 1 : 0
  
  source = "../../infrastructure/modules/primitive/fargate-profile"

  cluster_name           = module.eks_cluster.cluster_name
  profile_name           = "${local.cluster_name}-system-fargate-profile"
  pod_execution_role_arn = var.create_iam_roles ? module.iam_roles.fargate_role_arn : var.existing_fargate_role_arn
  subnet_ids             = var.subnet_ids
  selectors              = var.fargate_system_profile_selectors

  tags = local.common_tags

  depends_on = [
    module.eks_cluster,
    module.iam_roles
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
    module.fargate_profile_system,
    module.fargate_profile,
    module.eks_cluster
  ]

  tags = local.common_tags
}

# EC2 Node Groups (optional)
module "ec2_nodes" {
  source   = "../../infrastructure/modules/primitive/eks-node-group"
  for_each = var.ec2_node_group

  node_group_name = each.key
  cluster_name    = module.eks_cluster.cluster_name
  node_role_arn   = aws_iam_role.ec2_node_group_role.arn
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

# IAM Role for EC2 Node Groups
resource "aws_iam_role" "ec2_node_group_role" {
  count = length(var.ec2_node_group) > 0 ? 1 : 0
  
  name = "${local.cluster_name}-eks-node-group-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_node_group_policies" {
  for_each   = length(var.ec2_node_group) > 0 ? toset(var.ec2_node_group_policies) : []
  role       = aws_iam_role.ec2_node_group_role[0].name
  policy_arn = each.value
}

# Cluster Autoscaler IAM Role (only created if autoscaler is enabled)
resource "aws_iam_role" "cluster_autoscaler_role" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  name  = "${local.cluster_name}-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${var.cluster_autoscaler_namespace}:cluster-autoscaler"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "cluster_autoscaler_policy" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  name  = "${local.cluster_name}-cluster-autoscaler-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
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
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler_policy_attachment" {
  count      = var.enable_cluster_autoscaler ? 1 : 0
  policy_arn = aws_iam_policy.cluster_autoscaler_policy[0].arn
  role       = aws_iam_role.cluster_autoscaler_role[0].name
}