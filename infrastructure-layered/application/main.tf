# Application Layer - ADO Agents and Application Resources
#
# This layer deploys application-specific resources:
# - ECR repositories for agent container images
# - AWS Secrets Manager secrets for ADO integration
# - Helm chart deployment for ADO agents
# - IAM roles for agent execution (IRSA)
#
# This layer depends on both base infrastructure and middleware layers.

terraform {
  required_version = "~> 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
  
  # Remote state configuration - S3 backend with native state locking
  # Note: Terraform 1.10+ supports native S3 state locking without DynamoDB
  # The bucket name and region will be substituted by the deployment script from env vars
  backend "s3" {
    bucket = "TF_STATE_BUCKET_PLACEHOLDER"
    key    = "application/terraform.tfstate"
    region = "TF_STATE_REGION_PLACEHOLDER"
    
    # Enable native S3 state locking (Terraform 1.10+)
    # No DynamoDB table required
    encrypt        = true
    use_lockfile   = true
  }
}

# Configure AWS Provider
# Uses AWS_REGION environment variable if set, otherwise falls back to var.aws_region
provider "aws" {
  region = coalesce(
    try(var.aws_region, null),
    "us-west-2"  # Explicit fallback
  )
}

# Configure Kubernetes Provider using base layer cluster information
provider "kubernetes" {
  host                   = data.terraform_remote_state.base.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.base.outputs.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.base.outputs.cluster_name]
  }
}

# Configure Helm Provider
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.base.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.base.outputs.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.base.outputs.cluster_name]
    }
  }
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Local values
locals {
  cluster_name = data.terraform_remote_state.base.outputs.cluster_name
  common_tags = merge(
    data.terraform_remote_state.base.outputs.common_tags,
    {
      Layer = "application"
    },
    var.additional_tags
  )
}

# ECR Repositories for ADO agent images
module "ecr" {
  count  = length(var.ecr_repositories) > 0 ? 1 : 0
  source = "../../infrastructure/modules/collections/ecr"

  ecr_repositories       = var.ecr_repositories
  cluster_name           = local.cluster_name
  create_iam_policies    = true
  attach_pull_to_fargate = true
  fargate_role_name      = data.terraform_remote_state.base.outputs.fargate_role_name
  attach_bastion_policy  = false  # No bastion in this architecture
  bastion_role_name      = ""

  tags = local.common_tags
}

# AWS Secrets Manager secret for ADO PAT
resource "aws_secretsmanager_secret" "ado_pat" {
  name                    = var.ado_pat_secret_name
  description             = "Personal Access Token for Azure DevOps integration"
  recovery_window_in_days = var.secret_recovery_days
  kms_key_id              = data.terraform_remote_state.base.outputs.kms_key_arn

  tags = merge(
    local.common_tags,
    {
      Purpose     = "ADO-Integration"
      ManagedBy   = "terraform"
      SecretType  = "ado-pat"
    }
  )
}

resource "aws_secretsmanager_secret_version" "ado_pat" {
  secret_id = aws_secretsmanager_secret.ado_pat.id
  secret_string = jsonencode({
    personalAccessToken = var.ado_pat_value
    organization        = var.ado_org
    adourl             = var.ado_url
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ADO Agent Execution Roles (IRSA)
resource "aws_iam_role" "ado_agent_execution_roles" {
  for_each = var.ado_execution_roles

  name = "${local.cluster_name}-ado-agent-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.terraform_remote_state.base.outputs.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(data.terraform_remote_state.base.outputs.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"
            "${replace(data.terraform_remote_state.base.outputs.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Role      = "ADO-Agent-${title(each.key)}"
    Component = "ado-agent"
  })
}

# ADO Agent Execution Role Policies
resource "aws_iam_role_policy" "ado_agent_execution_policies" {
  for_each = var.ado_execution_roles

  name = "${local.cluster_name}-ado-agent-${each.key}-policy"
  role = aws_iam_role.ado_agent_execution_roles[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for permission in each.value.permissions : merge(
        {
          Effect   = permission.effect
          Action   = permission.actions
          Resource = permission.resources
        },
        permission.condition != null ? {
          Condition = {
            "${permission.condition.test}" = {
              "${permission.condition.variable}" = permission.condition.values
            }
          }
        } : {}
      )
    ]
  })
}

# Grant ESO access to ADO PAT secret
resource "aws_iam_role_policy" "eso_ado_secret_access" {
  name = "${local.cluster_name}-eso-ado-secret-access"
  role = data.terraform_remote_state.middleware.outputs.eso_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.ado_pat.arn
      }
    ]
  })
}

# Prepare Helm values for ADO agent deployment
locals {
  helm_values = {
    global = {
      namespace   = data.terraform_remote_state.middleware.outputs.ado_agents_namespace
      clusterName = local.cluster_name
      region      = data.aws_region.current.name
    }

    agentPools = {
      for pool_name, pool_config in var.agent_pools : pool_name => {
        enabled = pool_config.enabled
        name    = pool_name
        
        ado = {
          poolName   = pool_config.ado_pool_name
          secretName = data.terraform_remote_state.middleware.outputs.ado_secret_name
        }
        
        image = {
          repository = length(var.ecr_repositories) > 0 ? module.ecr[0].repositories[pool_config.ecr_repository_key].repository_url : pool_config.image_repository
          tag        = pool_config.image_tag
          pullPolicy = pool_config.image_pull_policy
        }
        
        serviceAccount = {
          name    = pool_config.service_account_name
          roleArn = aws_iam_role.ado_agent_execution_roles[pool_name].arn
        }
        
        resources = pool_config.resources
        
        autoscaling = {
          enabled                     = pool_config.autoscaling.enabled
          minReplicas                = pool_config.autoscaling.min_replicas
          maxReplicas                = pool_config.autoscaling.max_replicas
          targetPipelinesQueueLength = pool_config.autoscaling.target_queue_length
        }
        
        tolerations   = pool_config.tolerations
        nodeSelector  = pool_config.node_selector
        affinity      = pool_config.affinity
        
        # Additional environment variables
        env = pool_config.additional_env_vars
        
        # Volume mounts and volumes
        volumeMounts = pool_config.volume_mounts
        volumes      = pool_config.volumes
      }
    }

    externalSecrets = {
      enabled                  = true
      clusterSecretStoreName  = data.terraform_remote_state.middleware.outputs.cluster_secret_store_name
      secrets = {
        ado-pat = {
          aws = {
            secretName = aws_secretsmanager_secret.ado_pat.name
            region     = data.aws_region.current.name
          }
          k8s = {
            secretName      = data.terraform_remote_state.middleware.outputs.ado_secret_name
            type           = "Opaque"
            refreshInterval = var.secret_refresh_interval
          }
          data = {
            personalAccessToken = "personalAccessToken"
            organization        = "organization"
            adourl             = "adourl"
          }
        }
      }
    }

    buildkit = {
      enabled  = data.terraform_remote_state.middleware.outputs.buildkitd_enabled
      endpoint = data.terraform_remote_state.middleware.outputs.buildkitd_service_endpoint
    }

    # Common labels and annotations
    commonLabels = var.common_labels
    labels       = var.additional_labels
    annotations  = var.additional_annotations

    # Security contexts
    podSecurityContext = var.pod_security_context
    securityContext    = var.container_security_context
  }
}

# Deploy ADO agents via Helm
resource "helm_release" "ado_agents" {
  name       = "ado-agents"
  repository = "${path.module}/../helm"
  chart      = "ado-agent-cluster"
  namespace  = data.terraform_remote_state.middleware.outputs.ado_agents_namespace

  values = [yamlencode(local.helm_values)]

  # Ensure dependencies are ready
  depends_on = [
    aws_secretsmanager_secret_version.ado_pat,
    aws_iam_role.ado_agent_execution_roles,
    aws_iam_role_policy.ado_agent_execution_policies,
    aws_iam_role_policy.eso_ado_secret_access
  ]

  # Wait for resources to be ready
  wait          = true
  wait_for_jobs = false
  timeout       = 600

  # Enable atomic operations for safe upgrades
  atomic                = true
  cleanup_on_fail      = true
  disable_crd_hooks    = false
  disable_webhooks     = false
  force_update         = false
  recreate_pods        = false
  reset_values         = false
  reuse_values         = false
  skip_crds            = false

  # Set resource limits for Helm operations
  max_history = 10
}