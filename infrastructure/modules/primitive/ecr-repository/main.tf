resource "aws_ecr_repository" "repository" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "policy" {
  repository = aws_ecr_repository.repository.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after a number of days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.lifecycle_untagged_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep latest tagged images and expire older ones"
        selection = {
          tagStatus = "tagged"
          # Use Docker-tag-safe wildcard patterns. AWS ECR's TagPattern accepts
          # '*' wildcards (not full regex) and only the Docker tag character set.
          # The list below approximates semver tags (e.g. 1.2.3, v1.2.3, 1.2.3-rc.1).
          tagPatternList = [
            "*.*.*",
            "v*.*.*",
            "*.*.*-*",
            "v*.*.*-*"
          ]
          countType   = "imageCountMoreThan"
          countNumber = var.keep_tagged_count
        }
        action = { type = "expire" }
      }
    ]
  })
}
