# Create namespace for External Secrets Operator
resource "kubernetes_namespace" "external_secrets" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      name                                 = var.namespace
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# Install External Secrets Operator using Helm
resource "helm_release" "external_secrets" {
  name       = var.release_name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.eso_version
  namespace  = var.namespace

  # Wait for CRDs to be established
  wait            = true
  timeout         = 600
  cleanup_on_fail = true

  values = [
    yamlencode({
      installCRDs = true

      serviceAccount = {
        create      = true
        name        = var.service_account_name
        annotations = var.service_account_annotations
      }

      # Controller configuration
      resources = var.resources

      # Webhook configuration - disabled by default for Fargate compatibility
      webhook = {
        create        = var.webhook_enabled
        resources     = var.webhook_resources
        failurePolicy = var.webhook_failurePolicy
        # Disable cert-manager integration on Fargate to avoid certificate issues
        certManager = {
          enabled = false
        }
      }

      # Cert controller configuration
      certController = {
        create    = var.webhook_enabled # Only needed if webhooks are enabled
        resources = var.cert_controller_resources
      }

      # Security contexts
      podSecurityContext = {
        runAsNonRoot = true
        runAsUser    = 65534
        fsGroup      = 65534
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      securityContext = {
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = true
        runAsNonRoot             = true
        runAsUser                = 65534
        capabilities = {
          drop = ["ALL"]
        }
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      # Scheduling
      nodeSelector = var.node_selector
      tolerations  = var.tolerations
      affinity     = var.affinity

      # Concurrent reconciles - tune for performance
      concurrent = 1

      # Metrics
      metrics = {
        service = {
          enabled = true
        }
      }

      # Image pull policy
      image = {
        pullPolicy = "IfNotPresent"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.external_secrets
  ]
}

# Wait for CRDs to be established after helm release
resource "time_sleep" "wait_for_crds" {
  depends_on      = [helm_release.external_secrets]
  create_duration = "30s"
}

# Create ClusterSecretStore for AWS Secrets Manager
resource "kubernetes_manifest" "cluster_secret_store" {
  count = var.create_cluster_secret_store ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = var.cluster_secret_store_name
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = var.service_account_name
                namespace = var.namespace
              }
            }
          }
        }
      }
    }
  }

  # Wait for CRDs to be available before creating this resource
  computed_fields = ["metadata.resourceVersion"]

  depends_on = [
    time_sleep.wait_for_crds
  ]
}

# Create ExternalSecret resources
resource "kubernetes_manifest" "external_secrets" {
  for_each = var.create_external_secrets ? var.external_secrets : {}

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = each.key
      namespace = each.value.namespace
    }
    spec = {
      refreshInterval = each.value.refresh_interval
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = var.cluster_secret_store_name
      }
      target = {
        name           = each.value.secret_name
        creationPolicy = "Owner"
        template = {
          type = each.value.secret_type
        }
      }
      data = [
        for remote_key, local_key in each.value.data_key_mapping : {
          secretKey = local_key
          remoteRef = {
            key      = each.value.aws_secret_name
            property = remote_key
          }
        }
      ]
    }
  }

  # Wait for CRDs to be available before creating this resource
  computed_fields = ["metadata.resourceVersion"]

  depends_on = [
    kubernetes_manifest.cluster_secret_store,
    time_sleep.wait_for_crds
  ]
}
