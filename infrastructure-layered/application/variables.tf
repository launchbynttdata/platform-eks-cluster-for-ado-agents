# Application Layer Variables
#
# These variables control application-specific resources including ECR repositories,
# ADO secrets, agent pools, and deployment configurations.

# =============================================================================
# General Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region for application resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1, eu-west-2)."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources in the application layer"
  type        = map(string)
  default     = {}
}

# =============================================================================
# ECR Configuration
# =============================================================================

variable "ecr_repositories" {
  description = "Map of ECR repositories to create for ADO agent images"
  type = map(object({
    image_tag_mutability = string
    image_scanning_configuration = object({
      scan_on_push = bool
    })
    encryption_configuration = object({
      encryption_type = string
      kms_key        = string
    })
    lifecycle_policy_text = string
  }))
  default = {
    ado-agent = {
      image_tag_mutability = "IMMUTABLE"
      image_scanning_configuration = {
        scan_on_push = true
      }
      encryption_configuration = {
        encryption_type = "KMS"
        kms_key        = ""  # Will use cluster KMS key
      }
      lifecycle_policy_text = ""  # Empty string will use default policy from locals
    }
    ado-agent-iac = {
      image_tag_mutability = "IMMUTABLE"
      image_scanning_configuration = {
        scan_on_push = true
      }
      encryption_configuration = {
        encryption_type = "KMS"
        kms_key        = ""  # Will use cluster KMS key
      }
      lifecycle_policy_text = ""  # Empty string will use default policy from locals
    }
  }
}

# =============================================================================
# ADO Secrets Configuration
# =============================================================================

variable "ado_pat_secret_name" {
  description = "Name for the AWS Secrets Manager secret containing ADO PAT"
  type        = string
  default     = "ado-agent-pat"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]+$", var.ado_pat_secret_name))
    error_message = "Secret name must contain only alphanumeric characters, hyphens, underscores, forward slashes, plus signs, equals signs, periods, and at signs."
  }
}

variable "ado_pat_value" {
  description = "Personal Access Token for Azure DevOps (sensitive)"
  type        = string
  sensitive   = true
  default     = ""
  
  validation {
    condition     = length(var.ado_pat_value) >= 52 || var.ado_pat_value == ""
    error_message = "ADO PAT must be at least 52 characters long or empty (for external configuration)."
  }
}

variable "ado_org" {
  description = "Azure DevOps organization name"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.ado_org)) || var.ado_org == ""
    error_message = "ADO organization name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "ado_url" {
  description = "Azure DevOps organization URL"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^https://dev\\.azure\\.com/[a-zA-Z0-9-_]+/?$", var.ado_url)) || var.ado_url == ""
    error_message = "ADO URL must be a valid Azure DevOps organization URL."
  }
}

variable "secret_recovery_days" {
  description = "Number of days to retain deleted secrets for recovery"
  type        = number
  default     = 7
  
  validation {
    condition     = var.secret_recovery_days >= 7 && var.secret_recovery_days <= 30
    error_message = "Secret recovery days must be between 7 and 30."
  }
}

variable "secret_refresh_interval" {
  description = "Interval for External Secrets Operator to refresh secrets"
  type        = string
  default     = "5m"
  
  validation {
    condition     = can(regex("^\\d+[smh]$", var.secret_refresh_interval))
    error_message = "Secret refresh interval must be in format like '5m', '30s', or '1h'."
  }
}

# =============================================================================
# IAM Execution Roles for ADO Agents (IRSA)
# =============================================================================

variable "ado_execution_roles" {
  description = "IAM roles for ADO agent execution with IRSA"
  type = map(object({
    namespace            = string
    service_account_name = string
    permissions = list(object({
      effect    = string
      actions   = list(string)
      resources = list(string)
      condition = optional(object({
        test     = string
        variable = string
        values   = list(string)
      }))
    }))
  }))
  default = {
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
}

# =============================================================================
# Agent Pool Configuration
# =============================================================================

variable "agent_pools" {
  description = "Configuration for ADO agent pools"
  type = map(object({
    enabled                = bool
    ado_pool_name         = string
    ecr_repository_key    = string
    image_repository      = string
    image_tag            = string
    image_pull_policy    = string
    service_account_name = string
    resources = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
    autoscaling = object({
      enabled              = bool
      min_replicas        = number
      max_replicas        = number
      target_queue_length = number
    })
    tolerations         = list(object({
      key      = string
      operator = string
      value    = string
      effect   = string
    }))
    node_selector       = map(string)
    affinity           = any
    additional_env_vars = map(string)
    volume_mounts      = list(object({
      name      = string
      mountPath = string
      readOnly  = bool
    }))
    volumes = list(object({
      name = string
      type = string
      spec = any
    }))
  }))
  default = {
    ado-agent = {
      enabled                = true
      ado_pool_name         = "EKS-Linux-Agents"
      ecr_repository_key    = "ado-agent"
      image_repository      = "mcr.microsoft.com/azure-pipelines/vsts-agent"
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
      image_repository      = "mcr.microsoft.com/azure-pipelines/vsts-agent"
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
        # AWS_DEFAULT_REGION is dynamically injected via locals based on data.aws_region.current.name
      }
      volume_mounts = []
      volumes      = []
    }
  }
}

# =============================================================================
# Kubernetes Configuration
# =============================================================================

variable "common_labels" {
  description = "Common labels to apply to all Kubernetes resources"
  type        = map(string)
  default = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/component"  = "ado-agents"
  }
}

variable "additional_labels" {
  description = "Additional labels to apply to Kubernetes resources"
  type        = map(string)
  default     = {}
}

variable "additional_annotations" {
  description = "Additional annotations to apply to Kubernetes resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "pod_security_context" {
  description = "Pod security context configuration"
  type = object({
    runAsNonRoot        = bool
    runAsUser          = number
    runAsGroup         = number
    fsGroup           = number
    seccompProfile = object({
      type = string
    })
  })
  default = {
    runAsNonRoot = true
    runAsUser    = 1001
    runAsGroup   = 1001
    fsGroup      = 1001
    seccompProfile = {
      type = "RuntimeDefault"
    }
  }
}

variable "container_security_context" {
  description = "Container security context configuration"
  type = object({
    allowPrivilegeEscalation = bool
    runAsNonRoot            = bool
    runAsUser              = number
    readOnlyRootFilesystem = bool
    capabilities = object({
      drop = list(string)
      add  = list(string)
    })
    seccompProfile = object({
      type = string
    })
  })
  default = {
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
}