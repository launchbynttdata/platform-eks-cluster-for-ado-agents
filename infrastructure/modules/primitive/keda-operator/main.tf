# Create namespace for KEDA
resource "kubernetes_namespace" "keda" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      name = var.namespace
    }
  }
}

# Create namespace for ADO agents
resource "kubernetes_namespace" "ado_agents" {
  count = var.create_ado_namespace ? 1 : 0

  metadata {
    name = var.ado_namespace
    labels = {
      name = var.ado_namespace
    }
  }
}

# Install KEDA using Helm
resource "helm_release" "keda" {
  name       = var.release_name
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_version
  namespace  = var.namespace

  # Wait for CRDs to be established
  wait            = true
  timeout         = 600
  cleanup_on_fail = true

  values = [
    yamlencode({
      image = {
        keda = {
          repository = var.keda_image_repository
          tag        = var.keda_image_tag
        }
        metricsApiServer = {
          repository = var.metrics_server_image_repository
          tag        = var.metrics_server_image_tag
        }
        webhooks = {
          repository = var.webhooks_image_repository
          tag        = var.webhooks_image_tag
        }
      }

      crds = {
        install = true
      }

      serviceAccount = {
        create      = true
        name        = var.service_account_name
        annotations = var.service_account_annotations
      }

      podSecurityContext = {
        runAsNonRoot = true
        runAsUser    = 1001
        fsGroup      = 1001
      }

      securityContext = {
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = true
        capabilities = {
          drop = ["ALL"]
        }
      }

      resources = var.resources

      nodeSelector = var.node_selector
      tolerations  = var.tolerations
      affinity     = var.affinity
    })
  ]

  depends_on = [
    kubernetes_namespace.keda
  ]
}

# Create secret for ADO PAT (empty secret that will be populated externally)
# Only create if not managed by External Secrets Operator
resource "kubernetes_secret" "ado_pat" {
  count = var.create_ado_secret && !var.eso_managed_secret ? 1 : 0

  metadata {
    name      = var.ado_secret_name
    namespace = var.ado_namespace
  }

  type = "Opaque"

  data = {
    # Empty secret - will be populated by external secret manager or manually
    personalAccessToken = ""
  }

  depends_on = [
    kubernetes_namespace.ado_agents
  ]

  lifecycle {
    ignore_changes = [
      data,
      metadata[0].annotations,
      metadata[0].labels
    ]
  }
}

# Create KEDA ScaledObject for ADO agents
resource "kubernetes_manifest" "ado_scaledobject" {
  count = var.create_scaled_object ? 1 : 0

  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "${var.cluster_name}-ado-agents"
      namespace = var.ado_namespace
    }
    spec = {
      scaleTargetRef = {
        name = var.deployment_name
      }
      minReplicaCount = var.min_replica_count
      maxReplicaCount = var.max_replica_count
      triggers = [
        {
          type = "azure-pipelines"
          metadata = {
            organizationURLFromEnv     = "AZP_URL"
            personalAccessTokenFromEnv = "AZP_TOKEN"
            poolName                   = var.agent_pool_name
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.keda,
    kubernetes_namespace.ado_agents
  ]
}
