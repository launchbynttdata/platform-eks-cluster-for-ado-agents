# Minimal IAM policy that can be attached to roles which need to pull images from ECR repos
module "ecr_pull_policy" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = var.create_pull_policy ? 1 : 0

  policy_name = "${var.cluster_name}-ecr-pull"

  policy_statement = {
    ecr_get_auth = {
      sid       = "ECRGetAuth"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
    ecr_pull = {
      sid       = "ECRPull"
      actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
      resources = var.ecr_repository_arns
    }
    ecr_public_read = {
      sid       = "ECRPublicECRRead"
      actions   = ["ecr:DescribeRepositories", "ecr:GetRepositoryPolicy"]
      resources = var.ecr_repository_arns
    }
  }

  tags = var.tags
}

# Comprehensive ECR policy for bastion host (push and pull permissions)
module "ecr_bastion_policy" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = var.create_bastion_policy ? 1 : 0

  policy_name = "${var.cluster_name}-ecr-bastion"

  policy_statement = {
    ecr_get_auth = {
      sid       = "ECRGetAuth"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
    ecr_push_pull = {
      sid = "ECRPushPull"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ]
      resources = var.ecr_repository_arns
    }
    ecr_describe = {
      sid       = "ECRDescribe"
      actions   = ["ecr:DescribeRepositories", "ecr:GetRepositoryPolicy", "ecr:DescribeImages", "ecr:ListImages"]
      resources = var.ecr_repository_arns
    }
  }

  tags = var.tags
}

# Attach the pull policy to the Fargate execution role
module "ecr_pull_to_fargate_attachment" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.attach_pull_to_fargate && var.create_pull_policy ? 1 : 0

  role_name  = var.fargate_role_name
  policy_arn = module.ecr_pull_policy[0].policy_arn
}

# Attach the bastion policy to the bastion host role
module "ecr_bastion_policy_attachment" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = var.attach_bastion_policy && var.create_bastion_policy ? 1 : 0

  role_name  = var.bastion_role_name
  policy_arn = module.ecr_bastion_policy[0].policy_arn
}
