# EKS Cluster Service Role
module "eks_cluster_role" {
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
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_cluster_role ? 1 : 0

  role_name  = module.eks_cluster_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

module "eks_vpc_resource_controller_attachment" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_cluster_role ? 1 : 0

  role_name  = module.eks_cluster_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# Fargate Pod Execution Role
module "fargate_pod_execution_role" {
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
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_fargate_role ? 1 : 0

  role_name  = module.fargate_pod_execution_role[0].role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# KEDA Operator Role
module "keda_operator_role" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role/aws"
  version = "~> 0.1"
  count   = var.create_keda_role ? 1 : 0

  name = "${var.cluster_name}-keda-operator"

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
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = var.create_keda_role ? 1 : 0

  name        = "${var.cluster_name}-keda-operator-policy"
  description = "Policy for KEDA operator to read CloudWatch metrics"
  policy      = data.aws_iam_policy_document.keda_operator[0].json
}

module "keda_operator_policy_attachment" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.create_keda_role ? 1 : 0

  role_name  = module.keda_operator_role[0].role_name
  policy_arn = module.keda_operator_policy[0].arn
}
