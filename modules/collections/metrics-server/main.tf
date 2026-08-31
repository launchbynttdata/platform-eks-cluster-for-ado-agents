resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace

    labels = {
      "name" = var.namespace
    }
  }
}

locals {
  # kubelet already binds 10250 on EC2 nodes; hostNetwork metrics-server needs another port.
  container_port = var.use_host_network_for_control_plane_reachability ? 4443 : 10250
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
      containerPort = local.container_port
      hostNetwork = {
        enabled = var.use_host_network_for_control_plane_reachability
      }
    })
  ]

  depends_on = [kubernetes_namespace.this]
}
