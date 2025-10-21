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
  # Remote state configuration - S3 backend with native state locking
  # Note: Terraform 1.10+ supports native S3 state locking without DynamoDB
  # The bucket name and region are provided via -backend-config during init
  # See: https://developer.hashicorp.com/terraform/language/backend#partial-configuration
  backend "s3" {
    bucket = "" # Provided via -backend-config="bucket=..."
    key    = "base/terraform.tfstate"
    region = "" # Provided via -backend-config="region=..."

    # Enable native S3 state locking (Terraform 1.10+)
    # No DynamoDB table required
    encrypt      = true
    use_lockfile = true
  }
}

# Configure AWS Provider
# Uses AWS_REGION environment variable if set, otherwise falls back to var.aws_region
provider "aws" {
  region = coalesce(
    try(var.aws_region, null),
    "us-west-2" # Explicit fallback
  )
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# VPC and Subnets - basic validation that they exist
data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnet" "selected" {
  for_each = toset(var.subnet_ids)
  id       = each.value
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

  # Determine if we have any compute resources configured
  has_fargate = length(var.fargate_profiles) > 0
  has_ec2     = length(var.ec2_node_group) > 0

  # Smart public endpoint logic:
  # - If user explicitly sets endpoint_public_access = true AND provides restricted CIDRs, use them
  # - If no restricted CIDRs provided (empty or only 0.0.0.0/0), disable public access
  # - This satisfies CKV_AWS_39 by preventing unrestricted public access
  has_restricted_cidrs   = length(var.public_access_cidrs) > 0 && !contains(var.public_access_cidrs, "0.0.0.0/0")
  enable_public_endpoint = var.endpoint_public_access && local.has_restricted_cidrs
  effective_public_cidrs = local.enable_public_endpoint ? var.public_access_cidrs : []
}

# KMS Key for EKS encryption
# KMS Key for cluster-wide encryption
# This single key is shared across:
# - EKS secrets encryption
# - Secrets Manager (ADO PAT)
# - ECR repositories (optional)
# - External Secrets Operator decryption
# This minimizes KMS key sprawl and reduces costs
resource "aws_kms_key" "cluster_encryption" {
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
        Sid    = "Allow use by EKS"
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
      },
      {
        Sid    = "Allow use by Secrets Manager"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.cluster_name}-cluster-encryption-key"
    Description = "Shared encryption key for EKS, Secrets Manager, and ECR"
  })
}

resource "aws_kms_alias" "cluster_encryption" {
  name          = "alias/${local.cluster_name}-cluster-encryption"
  target_key_id = aws_kms_key.cluster_encryption.key_id
}

# KMS key is now always created for cluster encryption
locals {
  kms_key_arn = aws_kms_key.cluster_encryption.arn
  kms_key_id  = aws_kms_key.cluster_encryption.key_id
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
#checkov:skip=CKV_AWS_39:Public endpoint access is restricted to specific CIDRs or disabled based on public_access_cidrs variable
#checkov:skip=CKV_AWS_38:Public endpoint CIDR restrictions enforced via local.enable_public_endpoint logic
module "eks_cluster" {
  source = "../../infrastructure/modules/primitive/eks-cluster"

  cluster_name           = local.cluster_name
  cluster_role_arn       = var.create_iam_roles ? module.iam_roles.cluster_role_arn : var.existing_cluster_role_arn
  cluster_version        = var.cluster_version
  subnet_ids             = var.subnet_ids
  endpoint_public_access = local.enable_public_endpoint
  public_access_cidrs    = local.effective_public_cidrs
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

# IAM Role for VPC CNI using IRSA
resource "aws_iam_role" "vpc_cni_irsa" {
  count = var.create_iam_roles ? 1 : 0

  name = "${local.cluster_name}-vpc-cni-irsa-role"

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
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for VPC CNI
resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  count = var.create_iam_roles ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_irsa[0].name
}

# VPC CNI Addon (deployed before compute resources)
resource "aws_eks_addon" "vpc_cni" {
  count = contains(keys(var.eks_addons), "vpc-cni") ? 1 : 0

  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = try(var.eks_addons["vpc-cni"].addon_version, null)
  service_account_role_arn    = var.create_iam_roles ? aws_iam_role.vpc_cni_irsa[0].arn : null
  resolve_conflicts_on_create = try(var.eks_addons["vpc-cni"].resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(var.eks_addons["vpc-cni"].resolve_conflicts_on_update, "OVERWRITE")

  depends_on = [
    module.eks_cluster,
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.vpc_cni_policy
  ]

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

# Fargate Profiles
# Create one Fargate profile per entry in the fargate_profiles map
# Each profile can have multiple namespace selectors
# IMPORTANT: Fargate pods need VPC CNI addon to be installed first
module "fargate_profile" {
  for_each = var.fargate_profiles
  source   = "../../infrastructure/modules/primitive/fargate-profile"

  cluster_name           = module.eks_cluster.cluster_name
  profile_name           = "${local.cluster_name}-${each.key}-fargate-profile"
  pod_execution_role_arn = var.create_iam_roles ? module.iam_roles.fargate_role_arn : var.existing_fargate_role_arn
  subnet_ids             = var.subnet_ids
  selectors              = each.value.selectors

  tags = local.common_tags

  # Wait for IAM roles, cluster, and VPC CNI addon to be ready
  depends_on = [
    module.eks_cluster,
    module.iam_roles,
    aws_eks_addon.vpc_cni
  ]
}

# EKS Addons (excluding VPC CNI which is installed earlier)
# Install remaining addons after compute resources are available
# VPC CNI is handled separately with IRSA before compute resources
resource "aws_eks_addon" "addons" {
  for_each = { for k, v in var.eks_addons : k => v if k != "vpc-cni" }

  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")
  service_account_role_arn    = try(each.value.service_account_role_arn, null)
  configuration_values        = try(each.value.configuration_values, null)

  # Wait for compute resources to be available
  depends_on = [
    module.eks_cluster,
    module.ec2_nodes,
    module.fargate_profile
  ]

  tags = local.common_tags
}

# EC2 Node Groups (optional)
# IMPORTANT: Nodes must wait for VPC CNI addon to be installed before they can join the cluster
module "ec2_nodes" {
  source   = "../../infrastructure/modules/primitive/eks-node-group"
  for_each = var.ec2_node_group

  node_group_name = each.key
  cluster_name    = module.eks_cluster.cluster_name
  node_role_arn   = aws_iam_role.ec2_node_group_role[0].arn
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

  # Wait for VPC CNI addon to be installed before creating nodes
  depends_on = [
    module.eks_cluster,
    aws_eks_addon.vpc_cni,
    aws_iam_role.ec2_node_group_role
  ]
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
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        # Scope write operations to autoscaling groups owned by this EKS cluster
        Resource = "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${local.cluster_name}" = "owned"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeNodegroup"
        ]
        # Scope to node groups in this cluster
        Resource = "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:nodegroup/${local.cluster_name}/*/*"
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