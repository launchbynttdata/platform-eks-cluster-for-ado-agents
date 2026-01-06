resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace

    labels = {
      "name" = var.namespace
    }
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = var.repository
  chart      = "metrics-server"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = var.create_namespace
  wait             = true
  timeout          = 300
  cleanup_on_fail  = true

  values = [
    yamlencode({
      args         = var.args
      nodeSelector = var.node_selector
      tolerations  = var.tolerations
      resources    = var.resources
    })
  ]

  depends_on = [kubernetes_namespace.this]
}
