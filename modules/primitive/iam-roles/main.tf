# EKS Cluster Service Role
module "eks_cluster_role" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_cluster_role ? 1 : 0

  name = "${var.cluster_name}-cluster-role"

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

  tags = var.tags
}

module "eks_cluster_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_cluster_role ? 1 : 0

  role_name  = module.eks_cluster_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

module "eks_vpc_resource_controller_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_cluster_role ? 1 : 0

  role_name  = module.eks_cluster_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# Fargate Pod Execution Role
module "fargate_pod_execution_role" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_fargate_role ? 1 : 0

  name = "${var.cluster_name}-fargate-pod-execution-role"

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

  tags = var.tags
}

module "fargate_pod_execution_role_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_fargate_role ? 1 : 0

  role_name  = module.fargate_pod_execution_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# KEDA Operator Role (for metrics and scaling)
module "keda_operator_role" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_keda_role ? 1 : 0

  name = "${var.cluster_name}-keda-operator-role"

  assume_role_policy = [
    {
      actions = ["sts:AssumeRole"]
      principals = [
        {
          type        = "Federated"
          identifiers = [var.oidc_provider_arn]
        }
      ]
      conditions = [
        {
          test     = "StringEquals"
          variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub"
          values   = ["system:serviceaccount:${var.keda_namespace}:keda-operator"]
        },
        {
          test     = "StringEquals"
          variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud"
          values   = ["sts.amazonaws.com"]
        }
      ]
    }
  ]

  tags = var.tags
}

module "keda_operator_policy" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = var.create_keda_role ? 1 : 0

  policy_name = "${var.cluster_name}-keda-operator-policy"

  policy_statement = {
    secrets_manager = {
      sid       = "AllowSecretsManagerAccess"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = [var.ado_pat_secret_arn]
    }
    cloudwatch_logs = {
      sid       = "AllowCloudWatchLogs"
      actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      resources = ["arn:aws:logs:*:*:*"]
    }
  }

  tags = var.tags
}

module "keda_operator_policy_attachment" {
  # checkov:skip=CKV_TF_1: module source is trusted internal registry
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_keda_role ? 1 : 0

  role_name  = module.keda_operator_role[0].role_name
  policy_arn = module.keda_operator_policy[0].policy_arn
}
