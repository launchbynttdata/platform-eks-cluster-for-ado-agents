# =============================================================================
# Environment-Specific Configuration
# =============================================================================
# This file contains all environment-specific variables.
# To deploy to a different environment, copy this file and modify the values.
#
# Examples:
#   - env.hcl (symlink to env.dev.hcl for development)
#   - env.dev.hcl
#   - env.staging.hcl
#   - env.prod.hcl
#
# Usage:
#   ln -sf env.dev.hcl env.hcl

locals {
  # =============================================================================
  # Global Settings
  # =============================================================================
  
  environment  = "dev"
  project_name = "ado-agent-cluster"
  aws_region   = "us-west-2"
  
  # Common tags applied to all resources in this environment
  common_tags = {
    ProjectId   = "MVITMR"
    Environment = "dev"
    Owner       = "platform-team"
    CostCenter  = "engineering"
    ManagedBy   = "terraform"
  }
  
  # =============================================================================
  # Base Layer Configuration
  # =============================================================================
  
  # EKS Cluster Configuration
  cluster_name    = "dev-ado-agent-cluster"
  cluster_version = "1.34"
  
  # Networking Configuration
  vpc_id = "vpc-0b77ec74d3d593cd2"
  subnet_ids = [
    "subnet-0b233e11626d3ec0d",
    "subnet-0c15b96a28fc8be70"
  ]
  
  # Cluster Access Configuration
  endpoint_public_access = false
  public_access_cidrs    = ["136.226.0.0/16"]
  
  # IAM Configuration
  create_iam_roles = true
  
  # KMS Configuration
  kms_key_description             = "Shared encryption key for ado-agent-cluster (EKS, Secrets Manager, ECR)"
  kms_key_deletion_window_in_days = 7
  
  # Fargate Configuration
  # Set to {} to disable Fargate and use only EC2 node groups
  fargate_profiles = {}
  
  # EKS Add-ons Configuration
  eks_addons = {
    "coredns" = {
      version = "v1.12.4-eksbuild.1"
    }
    "kube-proxy" = {
      version = "v1.33.3-eksbuild.6"
    }
    "vpc-cni" = {
      version = "v1.20.2-eksbuild.1"
    }
  }
  
  # VPC Endpoints Configuration
  create_vpc_endpoints = false
  vpc_endpoint_services = [
    "s3",
    "ecr_dkr",
    "ecr_api",
    "ec2",
    "logs",
    "monitoring",
    "sts",
    "secretsmanager"
  ]
  exclude_vpc_endpoint_services = []
  
  # EC2 Node Groups - Using EC2 instead of Fargate
  ec2_node_groups = {
    "system-nodes" = {
      instance_types = ["t3a.medium"]
      disk_size      = 50
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      desired_size   = 1
      max_size       = 3
      min_size       = 0
      labels = {
        "workload-type" = "system"
      }
      taints = []
    }
    "buildkit-nodes" = {
      instance_types = ["c6a.xlarge"]
      disk_size      = 100
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      desired_size   = 1
      max_size       = 5
      min_size       = 0
      labels = {
        "workload-type" = "buildkit"
      }
      taints = [
        {
          key    = "node-role.kubernetes.io/buildkit"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
    "agent-nodes" = {
      instance_types = ["t3a.medium"]
      disk_size      = 50
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      desired_size   = 1
      max_size       = 10
      min_size       = 1
      labels = {
        "workload-type" = "agent"
      }
      taints = [
        {
          key    = "node-role.kubernetes.io/ado-agent"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }
  
  # Cluster Autoscaler (enabled for EC2 node groups)
  enable_cluster_autoscaler    = true
  cluster_autoscaler_namespace = "kube-system"
  
  # =============================================================================
  # Middleware Layer Configuration
  # =============================================================================
  
  # KEDA Configuration
  install_keda                         = true
  keda_namespace                       = "keda-system"
  keda_version                         = "2.17.2"
  keda_enable_cloudeventsource         = false
  keda_enable_cluster_cloudeventsource = false
  
  # ADO Configuration
  ado_agents_namespace = "ado-agents"
  
  # External Secrets Operator Configuration
  install_eso                = true
  eso_namespace              = "external-secrets-system"
  eso_version                = "0.10.4"
  eso_webhook_enabled        = false
  eso_webhook_failure_policy = "Ignore"
  # checkov:skip=CKV_SECRET_6: "False positive, this is not a hardcoded secret."
  cluster_secret_store_name  = "aws-secrets-manager"
  
  # Buildkitd Configuration
  enable_buildkitd    = true
  buildkitd_namespace = "buildkit-system"
  buildkitd_image     = "moby/buildkit:v0.25.1"
  buildkitd_replicas  = 2
  
  buildkitd_node_selector = {
    "workload-type" = "buildkit"
  }
  
  buildkitd_tolerations = [
    {
      key      = "workload-type"
      operator = "Equal"
      value    = "buildkit"
      effect   = "NoSchedule"
    },
    {
      key      = "node-role.kubernetes.io/buildkit"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
  ]
  
  buildkitd_resources = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2"
      memory = "4Gi"
    }
  }
  
  buildkitd_storage_size = "50Gi"
  
  # =============================================================================
  # Application Layer Configuration
  # =============================================================================
  
  # Azure DevOps Configuration
  ado_org             = "NVDMVDevOps"
  ado_url             = "https://dev.azure.com/NVDMVDevOps"
  ado_pat_secret_name = "ado-agent-pat"
  secret_recovery_days = 7
  secret_refresh_interval = "5m"
  
  # ECR Repositories Configuration
  ecr_repositories = {
    ado-agent = {
      image_tag_mutability = "IMMUTABLE"
      image_scanning_configuration = {
        scan_on_push = true
      }
      encryption_configuration = {
        encryption_type = "KMS"
        kms_key        = "" # Will use cluster KMS key
      }
      lifecycle_policy_text = "" # Empty string will use default policy
    }
    ado-agent-iac = {
      image_tag_mutability = "IMMUTABLE"
      image_scanning_configuration = {
        scan_on_push = true
      }
      encryption_configuration = {
        encryption_type = "KMS"
        kms_key        = "" # Will use cluster KMS key
      }
      lifecycle_policy_text = "" # Empty string will use default policy
    }
  }
  
  # ADO Agent Execution Roles
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
  
  # ADO Agent Pool Configuration
  agent_pools = {
    ado-agent = {
      enabled                = true
      ado_pool_name         = "dev-eks-agent-pool"
      ecr_repository_key    = "ado-agent"
      image_repository      = "887218969988.dkr.ecr.us-west-2.amazonaws.com"
      image_tag            = "v1"
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
        min_replicas        = 1
        max_replicas        = 10
        target_queue_length = 1
      }
      tolerations = []
      node_selector = {}
      affinity     = null
      additional_env_vars = {}
      volume_mounts = []
      volumes      = []
    }
    ado-agent-iac = {
      enabled                = true
      ado_pool_name         = "dev-eks-agent-iac-pool"
      ecr_repository_key    = "ado-agent-iac"
      image_repository      = "887218969988.dkr.ecr.us-west-2.amazonaws.com"
      image_tag            = "v1"
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
        min_replicas        = 1
        max_replicas        = 5
        target_queue_length = 1
      }
      tolerations = []
      node_selector = {}
      affinity     = null
      additional_env_vars = {
        AWS_DEFAULT_REGION = "us-west-2"
      }
      volume_mounts = []
      volumes      = []
    }
  }
  
  # Security Configuration
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
  
  # Kubernetes Labels and Annotations
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
}
