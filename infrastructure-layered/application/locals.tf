# Application Layer Local Values
#
# This file defines computed values for the application layer, including
# default ECR lifecycle policies and other derived configuration.

locals {
  # Default ECR lifecycle policy for ADO agent images
  default_ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod", "release", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 5 development images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev", "test", "staging"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  # ECR repositories with default lifecycle policy and repository_name applied where needed
  ecr_repositories_with_defaults = {
    for repo_name, repo_config in var.ecr_repositories : repo_name => {
      repository_name         = repo_name
      image_tag_mutability    = repo_config.image_tag_mutability
      encryption_type         = repo_config.encryption_configuration.encryption_type
      kms_key_arn             = repo_config.encryption_configuration.kms_key != "" ? repo_config.encryption_configuration.kms_key : data.terraform_remote_state.base.outputs.kms_key_arn
      scan_on_push            = repo_config.image_scanning_configuration.scan_on_push
      lifecycle_untagged_days = 7
      keep_tagged_count       = 10
    }
  }

  # Agent pools with dynamic AWS region injection
  # This ensures AWS_DEFAULT_REGION is always set to the current region
  agent_pools_with_region = {
    for pool_name, pool_config in var.agent_pools : pool_name => merge(
      pool_config,
      {
        additional_env_vars = merge(
          pool_config.additional_env_vars,
          {
            AWS_DEFAULT_REGION = data.aws_region.current.name
          }
        )
      }
    )
  }
}
