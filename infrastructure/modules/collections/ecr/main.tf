# Create ECR repositories using the primitive module
module "ecr_repositories" {
  source = "../../primitive/ecr-repository"

  for_each = var.ecr_repositories

  repository_name         = each.value.repository_name
  image_tag_mutability    = each.value.image_tag_mutability
  encryption_type         = each.value.encryption_type
  kms_key_arn             = each.value.kms_key_arn
  scan_on_push            = each.value.scan_on_push
  lifecycle_untagged_days = each.value.lifecycle_untagged_days
  keep_tagged_count       = each.value.keep_tagged_count
  tags                    = var.tags
}

# Create IAM policies for ECR access if repositories exist and policies are enabled
module "ecr_iam_policies" {
  source = "../../primitive/ecr-iam-policies"

  count = var.create_iam_policies && length(var.ecr_repositories) > 0 ? 1 : 0

  ecr_repository_arns    = [for repo in module.ecr_repositories : repo.repository_arn]
  cluster_name           = var.cluster_name
  create_pull_policy     = true
  create_bastion_policy  = true
  attach_pull_to_fargate = var.attach_pull_to_fargate
  fargate_role_name      = var.fargate_role_name
  attach_bastion_policy  = var.attach_bastion_policy
  bastion_role_name      = var.bastion_role_name
  tags                   = var.tags

  depends_on = [module.ecr_repositories]
}
