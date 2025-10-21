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
  
  environment  = "development"
  project_name = "eks-ado-agents"
  aws_region   = "us-west-2"
  
  # Common tags applied to all resources in this environment
  common_tags = {
    Environment = "development"
    Owner       = "platform-team"
    CostCenter  = "engineering"
    Department  = "devops"
  }
  
  # =============================================================================
  # Base Layer Configuration
  # =============================================================================
  
  # EKS Cluster Configuration
  cluster_name    = "poc-ado-agent-cluster"
  cluster_version = "1.33"
  
  # Networking Configuration
  vpc_id = "vpc-0555ff8949bb6bb4e"
  subnet_ids = [
    "subnet-08767b1e9b7e08959",
    "subnet-0eaf172a0157206f6"
  ]
  
  # Cluster Access Configuration
  endpoint_public_access = true
  public_access_cidrs    = ["136.226.0.0/16"]
  
  # IAM Configuration
  create_iam_roles = true
  
  # KMS Configuration
  kms_key_description             = "Shared encryption key for ado-agent-cluster (EKS, Secrets Manager, ECR)"
  kms_key_deletion_window_in_days = 7
  
  # Fargate Configuration
  # Set to {} to disable Fargate and use only EC2 node groups
  fargate_profiles = {
    apps = {
      selectors = [
        {
          namespace = "keda-system"
          labels    = {}
        },
        {
          namespace = "external-secrets"
          labels    = {}
        },
        {
          namespace = "ado-agents"
          labels    = {}
        }
      ]
    }
    # Uncomment to enable Fargate for CoreDNS
    # system = {
    #   selectors = [
    #     {
    #       namespace = "kube-system"
    #       labels = {
    #         "k8s-app" = "kube-dns"
    #       }
    #     }
    #   ]
    # }
  }
  
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
  create_vpc_endpoints = true
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
  
  # EC2 Node Groups (optional - leave empty {} if using only Fargate)
  ec2_node_groups = {
    # Uncomment to enable EC2 nodes for buildkit or other workloads
    # "buildkit-nodes" = {
    #   instance_types = ["t3.medium", "t3.large"]
    #   disk_size      = 100
    #   ami_type       = "AL2_x86_64"
    #   capacity_type  = "ON_DEMAND"
    #   desired_size   = 1
    #   max_size       = 5
    #   min_size       = 0
    #   labels = {
    #     "workload-type" = "buildkit"
    #   }
    #   taints = [
    #     {
    #       key    = "workload-type"
    #       value  = "buildkit"
    #       effect = "NoSchedule"
    #     }
    #   ]
    # }
  }
  
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
  ado_secret_name      = "ado-pat"
  
  # External Secrets Operator Configuration
  install_eso                = true
  eso_namespace              = "external-secrets-system"
  eso_version                = "0.10.4"
  eso_webhook_enabled        = false
  eso_webhook_failure_policy = "Ignore"
  cluster_secret_store_name  = "aws-secrets-manager"
  
  # Buildkitd Configuration
  enable_buildkitd    = true
  buildkitd_namespace = "buildkit-system"
  buildkitd_image     = "moby/buildkit:v0.12.5"
  buildkitd_replicas  = 2
  
  buildkitd_node_selector = {
    # Uncomment if using EC2 nodes with this label
    # "workload-type" = "buildkit"
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
  ado_org             = "launch-dso"
  ado_url             = "https://dev.azure.com/launch-dso"
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
            "s3:GetObject",
            "s3:PutObject",
            "dynamodb:PutItem",
            "dynamodb:GetItem",
            "dynamodb:DeleteItem"
          ]
          resources = ["*"]
        }
      ]
    }
  }
  
  # ADO Agent Pool Configuration
  ado_agent_pools = {
    default = {
      pool_name           = "EKS-ADO-Agents"
      service_account     = "ado-agent"
      image_repository    = "" # Empty = use public image, otherwise use ECR URL
      image_tag           = "latest"
      min_replicas        = 0
      max_replicas        = 10
      polling_interval    = 30
      cooldown_period     = 300
      
      resources = {
        requests = {
          cpu    = "500m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }
      
      node_selector = {}
      tolerations   = []
    }
    
    iac = {
      pool_name           = "EKS-ADO-IaC-Agents"
      service_account     = "ado-agent-iac"
      image_repository    = "" # Empty = use public image, otherwise use ECR URL
      image_tag           = "latest"
      min_replicas        = 0
      max_replicas        = 5
      polling_interval    = 30
      cooldown_period     = 300
      
      resources = {
        requests = {
          cpu    = "1000m"
          memory = "4Gi"
        }
        limits = {
          cpu    = "4"
          memory = "8Gi"
        }
      }
      
      node_selector = {}
      tolerations   = []
    }
  }
  
  # Helm Chart Configuration
  helm_chart_version = "0.1.0"
  helm_values_override = {}
}
