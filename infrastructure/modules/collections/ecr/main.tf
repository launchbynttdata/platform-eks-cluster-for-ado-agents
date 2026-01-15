# Create ECR repositories using the primitive module
module "ecr_repositories" {
  source = "../../primitive/ecr-repository"

  for_each = var.ecr_repositories

  repository_name             = each.value.repository_name
  image_tag_mutability        = each.value.image_tag_mutability
  encryption_type             = each.value.encryption_type
  kms_key_arn                 = each.value.kms_key_arn
  scan_on_push                = each.value.scan_on_push
  lifecycle_untagged_days     = each.value.lifecycle_untagged_days
  keep_tagged_count           = each.value.keep_tagged_count
  image_tag_mutability_filter = each.value.image_tag_mutability_filter
  tags                        = var.tags
}

# Create IAM policies for ECR access if repositories exist and policies are enabled
locals {
  ecr_repository_arns  = [for repo in values(module.ecr_repositories) : repo.repository_arn]
  iam_policies_enabled = var.create_iam_policies && length(local.ecr_repository_arns) > 0

  ecr_pull_policy_statements = {
    ecr_get_auth = {
      sid       = "ECRGetAuth"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
    ecr_pull = {
      sid = "ECRPull"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ]
      resources = local.ecr_repository_arns
    }
    ecr_public_read = {
      sid       = "ECRPublicECRRead"
      actions   = ["ecr:DescribeRepositories", "ecr:GetRepositoryPolicy"]
      resources = local.ecr_repository_arns
    }
  }

  ecr_bastion_policy_statements = {
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
      resources = local.ecr_repository_arns
    }
    ecr_describe = {
      sid = "ECRDescribe"
      actions = [
        "ecr:DescribeRepositories",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ]
      resources = local.ecr_repository_arns
    }
  }
}

module "ecr_pull_policy" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = local.iam_policies_enabled ? 1 : 0

  policy_name      = "${var.cluster_name}-ecr-pull"
  policy_statement = local.ecr_pull_policy_statements
  tags             = var.tags

  depends_on = [module.ecr_repositories]
}

module "ecr_bastion_policy" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_policy/aws"
  version = "~> 0.1"
  count   = local.iam_policies_enabled ? 1 : 0

  policy_name      = "${var.cluster_name}-ecr-bastion"
  policy_statement = local.ecr_bastion_policy_statements
  tags             = var.tags

  depends_on = [module.ecr_repositories]
}

module "ecr_pull_policy_attachment" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = local.iam_policies_enabled && var.attach_pull_to_fargate && var.fargate_role_name != "" ? 1 : 0

  role_name  = var.fargate_role_name
  policy_arn = module.ecr_pull_policy[0].policy_arn
}

module "ecr_bastion_policy_attachment" {
  source  = "terraform.registry.launch.nttdata.com/module_primitive/iam_role_policy_attachment/aws"
  version = "~> 0.1"
  count   = local.iam_policies_enabled && var.attach_bastion_policy && var.bastion_role_name != "" ? 1 : 0

  role_name  = var.bastion_role_name
  policy_arn = module.ecr_bastion_policy[0].policy_arn
}
