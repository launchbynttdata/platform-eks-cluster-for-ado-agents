variable "cluster_name" {
  description = "Name of the EKS cluster (used for auto-discovery flags)."
  type        = string
}

variable "namespace" {
  description = "Namespace where Cluster Autoscaler resources will be created."
  type        = string
}

variable "service_account_name" {
  description = "Name of the ServiceAccount bound to the Cluster Autoscaler Deployment."
  type        = string
  default     = "cluster-autoscaler"
}

variable "service_account_annotations" {
  description = "Annotations to add to the Cluster Autoscaler ServiceAccount (e.g., eks.amazonaws.com/role-arn)."
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region where the cluster is running (used for AWS_REGION env var)."
  type        = string
}

variable "image_repository" {
  description = "Container registry for the Cluster Autoscaler image."
  type        = string
  default     = "registry.k8s.io/autoscaling/cluster-autoscaler"
}

variable "image_tag" {
  description = "Cluster Autoscaler image tag (usually matches the cluster minor version)."
  type        = string
}

variable "replicas" {
  description = "Number of Cluster Autoscaler replicas to run."
  type        = number
  default     = 1
}

variable "resources" {
  description = "Resource requests and limits for the Cluster Autoscaler pod."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "600Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "600Mi"
    }
  }
}

variable "node_selector" {
  description = "Node selector forcing the Cluster Autoscaler pod onto specific nodes."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "List of tolerations applied to the Cluster Autoscaler pod."
  type = list(object({
    key                = optional(string)
    operator           = optional(string, "Exists")
    value              = optional(string)
    effect             = optional(string)
    toleration_seconds = optional(number)
  }))
  default = []
}

variable "priority_class_name" {
  description = "Priority class assigned to the Cluster Autoscaler pod."
  type        = string
  default     = "system-cluster-critical"
}

variable "pod_annotations" {
  description = "Annotations applied to the Cluster Autoscaler pod template."
  type        = map(string)
  default = {
    "prometheus.io/scrape"                           = "true"
    "prometheus.io/port"                             = "8085"
    "cluster-autoscaler.kubernetes.io/safe-to-evict" = "false"
  }
}

variable "labels" {
  description = "Additional labels applied to Cluster Autoscaler resources."
  type        = map(string)
  default     = {}
}

variable "base_args" {
  description = "Base command-line arguments for the Cluster Autoscaler binary."
  type        = list(string)
}

variable "extra_args" {
  description = "Additional command-line arguments to append to the Cluster Autoscaler binary."
  type        = list(string)
  default     = []
}

variable "volume_host_ca_path" {
  description = "Host path that exposes CA certificates inside the Cluster Autoscaler pod."
  type        = string
  default     = "/etc/ssl/certs/ca-bundle.crt"
}
