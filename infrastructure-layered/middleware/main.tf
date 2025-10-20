# Middleware Layer - Cluster Operators and Services
#
# This layer deploys middleware components that operate on the EKS cluster:
# - KEDA Operator (autoscaling)
# - External Secrets Operator (secret management)
# - Buildkitd service (container builds)
# - Application namespaces
#
# This layer depends on the base infrastructure layer via remote state.

terraform {
  # Remote state configuration - S3 backend with native state locking
  # Note: Terraform 1.10+ supports native S3 state locking without DynamoDB
  # The bucket name and region will be substituted by the deployment script from env vars
  backend "s3" {
    bucket = "TF_STATE_BUCKET_PLACEHOLDER"
    key    = "middleware/terraform.tfstate"
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
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.base.outputs.cluster_name, "--region", data.aws_region.current.name]
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
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.base.outputs.cluster_name, "--region", data.aws_region.current.name]
    }
  }
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Base layer state is loaded from remote_state.tf

# Local values
locals {
  cluster_name = data.terraform_remote_state.base.outputs.cluster_name
  common_tags = merge(
    data.terraform_remote_state.base.outputs.common_tags,
    {
      Layer = "middleware"
    },
    var.additional_tags
  )
}

# KEDA Operator IAM Role
resource "aws_iam_role" "keda_operator_role" {
  name = "${local.cluster_name}-keda-operator-role"

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
            "${replace(data.terraform_remote_state.base.outputs.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.keda_namespace}:keda-operator"
            "${replace(data.terraform_remote_state.base.outputs.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# KEDA Role Policy for CloudWatch, SQS, and basic operations
resource "aws_iam_role_policy" "keda_operator_policy" {
  name = "${local.cluster_name}-keda-operator-policy"
  role = aws_iam_role.keda_operator_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.cluster_name}/*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:keda-operator-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ListQueues"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      }
    ]
  })
}

# External Secrets Operator IAM Role
resource "aws_iam_role" "eso_role" {
  name = "${local.cluster_name}-external-secrets-role"

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
            "${replace(data.terraform_remote_state.base.outputs.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.eso_namespace}:external-secrets"
            "${replace(data.terraform_remote_state.base.outputs.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# ESO Policy - Basic Secrets Manager permissions and KMS access
resource "aws_iam_role_policy" "eso_policy" {
  name = "${local.cluster_name}-external-secrets-policy"
  role = aws_iam_role.eso_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = data.terraform_remote_state.base.outputs.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
      # Note: Specific secret access will be granted by the application layer
      # via additional policies or resource-specific permissions
    ]
  })
}

# KEDA Operator Installation
module "keda_operator" {
  count  = var.install_keda ? 1 : 0
  source = "../../infrastructure/modules/primitive/keda-operator"

  cluster_name         = local.cluster_name
  namespace            = var.keda_namespace
  ado_namespace        = var.ado_agents_namespace
  create_namespace     = true
  create_ado_namespace = true
  keda_version         = var.keda_version

  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.keda_operator_role.arn
  }

  create_ado_secret    = false # ADO secret will be managed by application layer
  eso_managed_secret   = true  # ESO will manage the secret
  ado_secret_name      = var.ado_secret_name
  create_scaled_object = false # ScaledObjects will be created by application layer
  
  # Configure CloudEventSource controllers via environment variables
  # Disable by default to prevent CrashLoopBackOff in KEDA 2.15.x when CRDs are not installed
  # See: https://github.com/kedacore/keda/issues/5751
  env = [
    {
      name  = "KEDA_ENABLE_CLOUDEVENTSOURCE_CONTROLLER"
      value = tostring(var.keda_enable_cloudeventsource)
    },
    {
      name  = "KEDA_ENABLE_CLUSTERCLOUDEVENTSOURCE_CONTROLLER"
      value = tostring(var.keda_enable_cluster_cloudeventsource)
    }
  ]
  
  tolerations = [{
    key      = "ks.amazonaws.com/compute-type"
    operator = "Equal"
    value    = "fargate"
    effect   = "NoSchedule"
  }]
}

# External Secrets Operator Installation
module "external_secrets_operator" {
  count  = var.install_eso ? 1 : 0
  source = "../../infrastructure/modules/primitive/external-secrets-operator"

  cluster_name     = local.cluster_name
  namespace        = var.eso_namespace
  create_namespace = true
  eso_version      = var.eso_version
  aws_region       = data.aws_region.current.name

  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.eso_role.arn
  }

  # Webhook configuration - disabled by default for Fargate compatibility
  webhook_enabled       = var.eso_webhook_enabled
  webhook_failurePolicy = var.eso_webhook_failure_policy

  # ClusterSecretStore is NOT created by Terraform (CRD timing limitation)
  # Must be created post-deployment using post-deploy-middleware.sh script
  # See: docs/MIDDLEWARE_POST_DEPLOYMENT_STEPS.md
  create_cluster_secret_store = false

  # Don't create external secrets here - application layer will manage them
  create_external_secrets = false
  external_secrets        = {}

  depends_on = [
    module.keda_operator # Ensure KEDA creates the ADO namespace first
  ]
}

# Buildkitd Service (standalone deployment for cluster-wide availability)
resource "kubernetes_namespace" "buildkit" {
  count = var.enable_buildkitd ? 1 : 0
  
  metadata {
    name = var.buildkitd_namespace
    
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# privileged security context is required for buildkitd
# https://github.com/moby/buildkit/blob/main/docs/architecture.md#security-context
# Note: This may not be compatible with Fargate profiles
# checkov:skip=CKV_K8S_16:buildkit requires privileged security context
resource "kubernetes_deployment" "buildkitd" {
  count = var.enable_buildkitd ? 1 : 0
  
  metadata {
    name      = "buildkitd"
    namespace = kubernetes_namespace.buildkit[0].metadata[0].name
    
    labels = {
      app = "buildkitd"
    }
  }

  spec {
    replicas = var.buildkitd_replicas

    selector {
      match_labels = {
        app = "buildkitd"
      }
    }

    template {
      metadata {
        labels = {
          app = "buildkitd"
        }
      }

      spec {
        # Use node selector for EC2 nodes if available
        node_selector = var.buildkitd_node_selector

        # Tolerations for dedicated buildkit nodes
        dynamic "toleration" {
          for_each = var.buildkitd_tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        container {
          name  = "buildkitd"
          image = var.buildkitd_image

          port {
            container_port = 1234
            name          = "buildkitd"
            protocol      = "TCP"
          }

          # Use --debug for better logging, don't use --oci-worker-no-process-sandbox
          # as it requires rootless mode
          args = [
            "--debug",
            "--addr", "tcp://0.0.0.0:1234"
          ]

          # BuildKit requires elevated privileges for container image building
          # This includes privileged mode and allowing privilege escalation
          security_context {
            privileged                 = true
            allow_privilege_escalation = true
          }

          # Readiness probe to ensure buildkitd is ready before routing traffic
          readiness_probe {
            tcp_socket {
              port = 1234
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          # Liveness probe to restart unhealthy buildkitd pods
          liveness_probe {
            tcp_socket {
              port = 1234
            }
            initial_delay_seconds = 10
            period_seconds        = 20
          }

          resources {
            requests = {
              cpu    = var.buildkitd_resources.requests.cpu
              memory = var.buildkitd_resources.requests.memory
            }
            limits = {
              cpu    = var.buildkitd_resources.limits.cpu
              memory = var.buildkitd_resources.limits.memory
            }
          }

          volume_mount {
            mount_path = "/tmp"
            name       = "tmp"
          }

          volume_mount {
            mount_path = "/var/lib/buildkit"
            name       = "buildkit-storage"
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }

        volume {
          name = "buildkit-storage"
          empty_dir {
            size_limit = var.buildkitd_storage_size
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "buildkitd" {
  count = var.enable_buildkitd ? 1 : 0
  
  metadata {
    name      = "buildkitd"
    namespace = kubernetes_namespace.buildkit[0].metadata[0].name
    
    labels = {
      app = "buildkitd"
    }
  }

  spec {
    selector = {
      app = "buildkitd"
    }

    port {
      port        = 1234
      target_port = 1234
      protocol    = "TCP"
      name        = "buildkitd"
    }

    type = "ClusterIP"
  }
}

# Create an ExternalName service alias in the ado-agents namespace
# This allows ADO agents to reference buildkitd as:
# - buildkitd.ado-agents.svc.cluster.local
# - buildkitd (from within the ado-agents namespace)
# Instead of the full: buildkitd.buildkit-system.svc.cluster.local
resource "kubernetes_service" "buildkitd_alias" {
  count = var.enable_buildkitd ? 1 : 0
  
  metadata {
    name      = "buildkitd"
    namespace = var.ado_agents_namespace
    
    labels = {
      app = "buildkitd"
    }
    
    annotations = {
      "description" = "ExternalName service alias to buildkitd in buildkit-system namespace"
    }
  }

  spec {
    type          = "ExternalName"
    external_name = "buildkitd.${var.buildkitd_namespace}.svc.cluster.local"
  }

  depends_on = [
    kubernetes_service.buildkitd,
    module.keda_operator  # Ensures ado-agents namespace exists
  ]
}