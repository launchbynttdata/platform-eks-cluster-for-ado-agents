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
  repository = "oci://public.ecr.aws/aws-ec2/helm"
  chart      = "aws-node-termination-handler"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = var.create_namespace
  wait             = true
  timeout          = 600
  cleanup_on_fail  = true

  values = [
    yamlencode({
      queueURL                       = var.queue_url
      awsRegion                      = var.aws_region
      enableSqsTerminationDraining   = true
      enableSpotInterruptionDraining = true
      enableRebalanceMonitoring      = true
      enableRebalanceDraining        = true
      enableScheduledEventDraining   = true
      enablePrometheusMetrics        = true
      logLevel                       = var.log_level
      priorityClassName              = var.priority_class_name
      nodeSelector                   = var.node_selector
      tolerations                    = var.tolerations
      resources                      = var.resources
      podAnnotations                 = var.pod_annotations
      serviceAccount = {
        create      = true
        name        = var.service_account_name
        annotations = var.service_account_annotations
      }
      env = concat(var.extra_env, [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ])
    })
  ]

}
