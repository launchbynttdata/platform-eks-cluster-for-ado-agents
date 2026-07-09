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
  cluster_name                    = "poc-ado-agent-cluster"
  cluster_version                 = "1.35"
  cluster_api_ready_wait_duration = "90s"

  # Networking Configuration
  vpc_id = "vpc-xxxxxxxx"
  subnet_ids = [
    "subnet-xxxxxxxx",
    "subnet-yyyyyyyy"
  ]
  # Pod networking mode:
  # - "vpc-cni": default Amazon VPC CNI mode; required when Fargate profiles are enabled
  # - "cilium-overlay": EC2-only Cilium overlay mode that allocates pod IPs from Cilium CIDRs
  pod_networking_mode = "vpc-cni"

  # Cluster Access Configuration
  endpoint_public_access = true
  public_access_cidrs    = ["203.0.113.0/24"]

  # External IAM roles granted EKS cluster-admin (ECS IaC agents, jumpboxes, etc.)
  # Set to false only when another explicit access entry grants the creator role the required access.
  bootstrap_cluster_creator_admin_permissions = true
  cluster_admin_access_principal_arns = [
    # "arn:aws:iam::375235800848:role/dmv-adoecsagent-shared-ecs_task-instance-role",
  ]

  # IAM Configuration
  create_iam_roles = true

  # KMS Configuration
  kms_key_description             = "Shared encryption key for ado-agent-cluster (EKS, Secrets Manager, ECR)"
  kms_key_deletion_window_in_days = 7

  # Fargate Configuration
  # Set to {} to disable Fargate and use only EC2 node groups
  fargate_profiles = {
    apps = {
      selectors = []
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
      version = "v1.14.2-eksbuild.4"
    }
    "kube-proxy" = {
      version = "v1.35.3-eksbuild.2"
    }
    "vpc-cni" = {
      version = "v1.21.1-eksbuild.8"
    }
  }

  # Cilium CNI Configuration
  # Used only when pod_networking_mode = "cilium-overlay".
  # In cilium-overlay mode, set fargate_profiles = {}, configure at least one
  # EC2 node group, and remove "vpc-cni" from eks_addons.
  cilium_networking = {
    chart_version                   = "1.19.5"
    cluster_pool_ipv4_pod_cidr_list = ["100.64.0.0/10"]
    cluster_pool_ipv4_mask_size     = 24
    # Private clusters without NAT must mirror Cilium images to a reachable registry
    # and override image.repository / operator.image.repository here.
    helm_values_override = {}
  }

  # VPC Endpoints Configuration
  create_vpc_endpoints = true
  vpc_endpoint_services = [
    "s3",
    "ecr_dkr",
    "ecr_api",
    "ec2",
    "eks",
    "logs",
    "monitoring",
    "sts",
    "secretsmanager"
  ]
  exclude_vpc_endpoint_services = []

  # EC2 Node Groups (optional - leave empty {} if using only Fargate)
  ec2_node_groups = {
    # Uncomment to enable EC2 nodes for buildkit or other workloads
    "buildkit-nodes" = {
      instance_types = ["t3a.xlarge"]
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
          key    = "workload-type"
          value  = "buildkit"
          effect = "NoSchedule"
        }
      ]
    },
    "agent-nodes" = {
      instance_types = ["t3a.xlarge"]
      disk_size      = 100
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      desired_size   = 1
      max_size       = 5
      min_size       = 0
      labels = {
        "workload-type" = "agent"
      }
      taints = [
        {
          key    = "node-role.kubernetes.io/ado-agent"
          value  = "true"
          effect = "NoSchedule"
        }
      ]
    },
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
  }

  # =============================================================================
  # Middleware Layer Configuration
  # =============================================================================

  # KEDA Configuration
  install_keda                         = true
  keda_namespace                       = "keda-system"
  keda_version                         = "2.20.0"
  keda_enable_cloudeventsource         = false
  keda_enable_cluster_cloudeventsource = false

  # Metrics Server Configuration (Helm-managed)
  install_metrics_server       = true
  metrics_server_namespace     = "kube-system"
  metrics_server_chart_version = "3.13.0"
  metrics_server_args = [
    "--kubelet-insecure-tls",
    "--kubelet-preferred-address-types=InternalIP,Hostname"
  ]
  metrics_server_node_selector = {
    # Uncomment to pin to system nodes
    # "workload-type" = "system"
  }
  metrics_server_tolerations = []
  metrics_server_resources = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "250m"
      memory = "512Mi"
    }
  }

  # ADO Configuration
  ado_agents_namespace = "ado-agents"

  # CloudWatch Logging / Observability
  enable_cloudwatch_observability        = true
  enable_cloudwatch_observability_addon  = true
  cloudwatch_observability_addon_version = null
  enable_cloudwatch_application_signals_auto_monitor              = true
  cloudwatch_application_signals_auto_monitor_excluded_namespaces = []
  cloudwatch_log_retention_days                                  = 30
  enable_fargate_cloudwatch_logging                              = true
  fargate_fluentbit_log_level                                    = "info"
  fargate_fluentbit_include_process_logs = false
  enable_ado_agent_cloudwatch_log_groups = true
  application_crd_ready_wait_seconds     = 60
  platform_log_groups = [
    "application",
    "dataplane",
    "host",
    "performance",
    "ado-agents",
    "buildkit",
    "keda",
    "cluster-autoscaler"
  ]

  # External Secrets Operator Configuration
  install_eso                = true
  eso_namespace              = "external-secrets-system"
  eso_version                = "1.3.2"
  eso_webhook_enabled        = false
  eso_webhook_failure_policy = "Ignore"
  cluster_secret_store_name  = "aws-secrets-manager"

  # Buildkitd Configuration
  enable_buildkitd                                   = true
  buildkitd_namespace                                = "buildkit-system"
  buildkitd_image                                    = "moby/buildkit:v0.30.0-rootless"
  buildkitd_replicas                                 = 2
  buildkitd_hpa_enabled                              = true
  buildkitd_hpa_min_replicas                         = 2
  buildkitd_hpa_max_replicas                         = 5
  buildkitd_hpa_target_memory_utilization_percentage = 70
  buildkitd_topology_spread_enabled                  = true
  buildkitd_pdb_enabled                              = true
  buildkitd_pdb_min_available                        = 1
  buildkitd_tls_enabled                              = false
  buildkitd_tls_secret_name                          = ""

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

  # Optional: ECR accounts / ARNs for BuildKit IRSA (empty in sample = cluster account only in Terraform)
  # buildkitd_ecr_registry_account_ids = ["111111111111", "222222222222"]
  # buildkitd_ecr_repository_arns      = ["arn:aws:ecr:us-west-2:222222222222:repository/*"]
  # buildkitd_kms_key_arn_patterns     = ["arn:aws:kms:us-west-2:222222222222:key/*"]
  enable_ecr_pull_through_cache                      = true
  create_ecr_pull_through_cache_repository_templates = true
  create_ecr_pull_through_cache_repository_policies  = true
  ecr_pull_through_cache_rules = {
    ecr-public = {
      upstream_registry_url = "public.ecr.aws"
    }
    k8s = {
      upstream_registry_url = "registry.k8s.io"
    }
    quay = {
      upstream_registry_url = "quay.io"
    }
  }
  buildkitd_registry_mirrors = {
    # Optional overrides only. ECR pull-through cache mirrors are derived automatically
    # from ecr_pull_through_cache_rules as <account>.dkr.ecr.<region>.amazonaws.com/<prefix>.
  }

  # =============================================================================
  # Application Layer Configuration
  # =============================================================================

  # Azure DevOps Configuration
  ado_org                 = "launch-dso"
  ado_url                 = "https://dev.azure.com/launch-dso"
  ado_pat_secret_name     = "ado-agent-pat"
  ado_agent_auth_mode     = "pat"
  ado_agent_spn_secret = {
    aws_secret_name  = ""
    k8s_secret_name  = "ado-agent-spn"
    refresh_interval = ""
  }
  ado_keda_proxy = {
    image_repository  = "ghcr.io/launchbynttdata/platform-eks-cluster-for-ado-agents/ado-keda-proxy"
    image_tag         = "v0.1.0"
    image_digest      = "" # Prefer pinning production deployments to sha256:<digest>.
    image_pull_policy = "IfNotPresent"
    resources = {
      requests = {
        cpu    = "25m"
        memory = "64Mi"
      }
      limits = {
        cpu    = "250m"
        memory = "256Mi"
      }
    }
  }
  secret_recovery_days    = 7
  secret_refresh_interval = "5m"

  # ECR Repositories Configuration
  create_ecr_iam_policies = true
  ecr_repositories = {
    ado-agent = {
      image_tag_mutability = "IMMUTABLE"
      image_scanning_configuration = {
        scan_on_push = true
      }
      encryption_configuration = {
        encryption_type = "KMS"
        kms_key         = "" # Will use cluster KMS key
      }
      lifecycle_policy_text = "" # Empty string will use default policy
    }
    ado-iac-agent = {
      image_tag_mutability = "IMMUTABLE"
      image_scanning_configuration = {
        scan_on_push = true
      }
      encryption_configuration = {
        encryption_type = "KMS"
        kms_key         = "" # Will use cluster KMS key
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
    ado-iac-agent = {
      namespace            = "ado-agents"
      service_account_name = "ado-iac-agent"
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
  agent_run_once                         = true
  agent_recycle_pod_after_run_once       = false
  agent_cleanup_timeout_seconds          = 300
  agent_termination_grace_period_seconds = 420
  agent_automount_service_account_token  = true
  ado_agents_helm_atomic                 = false
  ado_agents_helm_cleanup_on_fail        = false

  ado_agent_pools = {
    default = {
      pool_name        = "EKS-ADO-Agents"
      service_account  = "ado-agent"
      image_repository = "" # Empty = use public image, otherwise use ECR URL
      image_tag        = "latest"
      min_replicas     = 1
      max_replicas     = 10
      polling_interval = 30
      cooldown_period  = 300

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

      node_selector = {
        "workload-type" = "agent"
      }
      tolerations = [
        {
          key      = "workload-type"
          operator = "Equal"
          value    = "agent"
          effect   = "NoSchedule"
        },
        {
          key      = "node-role.kubernetes.io/ado-agent"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        },
        {
          key      = "aws.amazon.com/fargate"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]
    }

    iac = {
      pool_name        = "EKS-ADO-IaC-Agents"
      service_account  = "ado-iac-agent"
      image_repository = "" # Empty = use public image, otherwise use ECR URL
      image_tag        = "latest"
      min_replicas     = 1
      max_replicas     = 5
      polling_interval = 30
      cooldown_period  = 300

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

      node_selector = {
        "workload-type" = "agent"
      }
      tolerations = [
        {
          key      = "workload-type"
          operator = "Equal"
          value    = "agent"
          effect   = "NoSchedule"
        },
        {
          key      = "node-role.kubernetes.io/ado-agent"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        },
        {
          key      = "aws.amazon.com/fargate"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      ]
    }
  }

  # Helm Chart Configuration
  helm_chart_version   = "0.1.0"
  helm_values_override = {}
}
