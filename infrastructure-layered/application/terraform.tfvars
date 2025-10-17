# Sample Terraform Variables - Application Layer
# Copy this file to terraform.tfvars and customize for your environment

# =============================================================================
# General Configuration
# =============================================================================
aws_region = "us-west-2"

# Remote state configuration (required)
remote_state_bucket = "brv-eks-ado-cluster-rs-1935a"
remote_state_region = "us-west-2"

# Additional tags for all resources
additional_tags = {
  Environment = "development"
  Project     = "ADO-EKS-Agents"
  Owner       = "platform-team"
  CostCenter  = "engineering"
}

# =============================================================================
# ADO Configuration (SENSITIVE - Use environment variables or AWS Secrets)
# =============================================================================

# Azure DevOps Personal Access Token (SENSITIVE)
# ado_pat_value = "YOUR_ADO_PAT_HERE"  # Uncomment and set, or use TF_VAR_ado_pat_value

# Azure DevOps Organization
ado_org = "launch-dso"

# Azure DevOps URL
ado_url = "https://dev.azure.com/launch-dso"

# Secret configuration
ado_pat_secret_name = "ado-agent-pat"
secret_recovery_days = 7
secret_refresh_interval = "5m"

# =============================================================================
# ECR Repositories (Optional - will use public images if not specified)
# =============================================================================

# ECR repositories for custom ADO agent images
ecr_repositories = {
  ado-agent = {
    image_tag_mutability = "MUTABLE"
    image_scanning_configuration = {
      scan_on_push = true
    }
    encryption_configuration = {
      encryption_type = "KMS"
      kms_key        = ""  # Will use cluster KMS key
    }
    lifecycle_policy_text = jsonencode({
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
  }
  ado-agent-iac = {
    image_tag_mutability = "MUTABLE"
    image_scanning_configuration = {
      scan_on_push = true
    }
    encryption_configuration = {
      encryption_type = "KMS"
      kms_key        = ""  # Will use cluster KMS key
    }
    lifecycle_policy_text = jsonencode({
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
  }
}

# =============================================================================
# IAM Execution Roles Configuration
# =============================================================================

ado_execution_roles = {
  ado-agent = {
    namespace            = "ado-agents"
    service_account_name = "ado-agent"
    permissions = [
      {
        effect = "Allow"
        actions = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        resources = ["*"]
      }
    ]
  }
  ado-agent-iac = {
    namespace            = "ado-agents"
    service_account_name = "ado-agent-iac"
    permissions = [
      {
        effect = "Allow"
        actions = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        resources = ["*"]
      },
      {
        effect = "Allow"
        actions = [
          "sts:AssumeRole"
        ]
        resources = ["arn:aws:iam::*:role/*terraform*"]
      },
      {
        effect = "Allow"
        actions = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        resources = [
          "arn:aws:s3:::*terraform*",
          "arn:aws:s3:::*terraform*/*"
        ]
      },
      {
        effect = "Allow"
        actions = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        resources = ["arn:aws:dynamodb:*:*:table/*terraform*"]
      }
    ]
  }
}

# =============================================================================
# Agent Pool Configuration
# =============================================================================

agent_pools = {
  ado-agent = {
    enabled                = true
    ado_pool_name         = "EKS-Linux-Agents"
    ecr_repository_key    = "ado-agent"
    image_repository      = "mcr.microsoft.com/azure-pipelines/vsts-agent"  # Will use ECR if available
    image_tag            = "ubuntu-20.04"
    image_pull_policy    = "IfNotPresent"
    service_account_name = "ado-agent"
    resources = {
      requests = {
        cpu    = "100m"
        memory = "256Mi"
      }
      limits = {
        cpu    = "2000m"
        memory = "4Gi"
      }
    }
    autoscaling = {
      enabled              = true
      min_replicas        = 0
      max_replicas        = 10
      target_queue_length = 1
    }
    tolerations = [
      {
        key      = "aws.amazon.com/fargate"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }
    ]
    node_selector = {}
    affinity     = null
    additional_env_vars = {}
    volume_mounts = []
    volumes      = []
  }
  ado-agent-iac = {
    enabled                = true
    ado_pool_name         = "EKS-IaC-Agents"
    ecr_repository_key    = "ado-agent-iac"
    image_repository      = "mcr.microsoft.com/azure-pipelines/vsts-agent"  # Will use ECR if available
    image_tag            = "ubuntu-20.04"
    image_pull_policy    = "IfNotPresent"
    service_account_name = "ado-agent-iac"
    resources = {
      requests = {
        cpu    = "200m"
        memory = "512Mi"
      }
      limits = {
        cpu    = "4000m"
        memory = "8Gi"
      }
    }
    autoscaling = {
      enabled              = true
      min_replicas        = 0
      max_replicas        = 5
      target_queue_length = 1
    }
    tolerations = [
      {
        key      = "aws.amazon.com/fargate"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }
    ]
    node_selector = {}
    affinity     = null
    additional_env_vars = {
      TF_CLI_CONFIG_FILE = "/opt/terraform/.terraformrc"
      AWS_DEFAULT_REGION = "us-west-2"
    }
    volume_mounts = []
    volumes      = []
  }
}

# =============================================================================
# Security Configuration
# =============================================================================

pod_security_context = {
  runAsNonRoot = true
  runAsUser    = 1001
  runAsGroup   = 1001
  fsGroup      = 1001
  seccompProfile = {
    type = "RuntimeDefault"
  }
}

container_security_context = {
  allowPrivilegeEscalation = false
  runAsNonRoot            = true
  runAsUser              = 1001
  readOnlyRootFilesystem = false  # ADO agent needs write access
  capabilities = {
    drop = ["ALL"]
    add  = []
  }
  seccompProfile = {
    type = "RuntimeDefault"
  }
}

# =============================================================================
# Kubernetes Labels and Annotations
# =============================================================================

common_labels = {
  "app.kubernetes.io/managed-by" = "terraform"
  "app.kubernetes.io/component"  = "ado-agents"
  "app.kubernetes.io/part-of"    = "eks-ado-platform"
}

additional_labels = {
  "environment" = "development"
}

additional_annotations = {
  "deployment.kubernetes.io/revision" = "1"
}