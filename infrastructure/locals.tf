locals {
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    },
    var.tags
  )

  # cluster_name = var.cluster_name
  # ECR Configuration with backward compatibility
  # ECR KMS key logic from legacy implementation
  /*
  Local: ecr_kms_key_arn

  Purpose:
    Determine which KMS Key ARN to use for ECR encryption by consulting the
    cluster module output first and a fallback input variable second. If neither
    provides a non-empty value, an empty string is returned.

  Behavior / Logic:
    - coalesce(..., "") is used to convert potential nulls into empty strings so
      the subsequent string operations are safe.
    - trimspace(...) removes surrounding whitespace so values that are only
      whitespace are treated as empty.
    - length(...) > 0 tests whether the trimmed, coalesced string is non-empty.
    - Precedence:
        1. module.ado_eks_cluster.kms_key_arn (used if present and non-empty)
        2. var.kms_key_arn                (used if present and non-empty)
        3. ""                             (empty string if neither is set)

  Notes / Implications:
    - The resulting value is an empty string when no custom KMS key is specified.
      Consumers should interpret that as "no custom key provided" (typically
      meaning the AWS-managed key or resource default will be used).
    - This expression does not validate ARN format; if you need strict ARN
      validation, add explicit checks or input validation elsewhere.
    - To explicitly unset a KMS ARN, provide an empty string (or whitespace-only)
      for the module output or variable; it will be treated as absent.
  */
  ecr_kms_key_arn = length(trimspace(coalesce(module.ado_eks_cluster.kms_key_arn, ""))) > 0 ? module.ado_eks_cluster.kms_key_arn : (length(trimspace(coalesce(var.kms_key_arn, ""))) > 0 ? var.kms_key_arn : "")

  # Create a default ECR repository configuration if the legacy create_ecr_repository flag is true
  # This maintains backward compatibility while supporting the new modular approach
  default_ecr_config = var.create_ecr_repository ? {
    default = {
      repository_name         = length(trimspace(var.ecr_repository_name)) > 0 ? var.ecr_repository_name : "${var.cluster_name}-ado-agents"
      image_tag_mutability    = "MUTABLE"
      encryption_type         = length(trimspace(local.ecr_kms_key_arn)) > 0 ? "KMS" : "AES256"
      kms_key_arn             = local.ecr_kms_key_arn
      scan_on_push            = true
      lifecycle_untagged_days = var.ecr_lifecycle_untagged_days
      keep_tagged_count       = var.ecr_keep_tagged_count
    }
  } : {}

  # Merge explicit ecr_repositories with default configuration for backward compatibility
  all_ecr_repositories = merge(local.default_ecr_config, var.ecr_repositories)

  # Extract bastion role name from ARN for IAM attachments
  bastion_role_name = var.bastion_role_arn != "" ? element(split("/", var.bastion_role_arn), length(split("/", var.bastion_role_arn)) - 1) : ""
}