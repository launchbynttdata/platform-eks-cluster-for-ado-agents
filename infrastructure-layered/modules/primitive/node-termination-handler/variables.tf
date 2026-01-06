variable "namespace" {
  description = "Namespace where the AWS Node Termination Handler DaemonSet will run."
  type        = string
}

variable "create_namespace" {
  description = "Whether to create the namespace if it does not already exist."
  type        = bool
  default     = false
}

variable "release_name" {
  description = "Helm release name for the Node Termination Handler chart."
  type        = string
  default     = "aws-node-termination-handler"
}

variable "chart_version" {
  description = "Version of the aws-node-termination-handler Helm chart."
  type        = string
  default     = "0.27.3"
}

variable "queue_url" {
  description = "URL of the SQS queue that receives EC2/ASG lifecycle events."
  type        = string
}

variable "aws_region" {
  description = "AWS region used by the handler when polling SQS."
  type        = string
}

variable "service_account_name" {
  description = "ServiceAccount name for the DaemonSet (must match IRSA configuration)."
  type        = string
  default     = "aws-node-termination-handler"
}

variable "service_account_annotations" {
  description = "Annotations applied to the ServiceAccount (e.g., eks.amazonaws.com/role-arn)."
  type        = map(string)
  default     = {}
}

variable "node_selector" {
  description = "Node selector applied to the DaemonSet pods to keep them on EC2 nodes."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations so the DaemonSet runs on tainted infrastructure nodes."
  type = list(object({
    key               = optional(string)
    operator          = optional(string, "Exists")
    value             = optional(string)
    effect            = optional(string)
    tolerationSeconds = optional(number)
  }))
  default = []
}

variable "resources" {
  description = "Resource requests and limits for the DaemonSet containers."
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
      cpu    = "50m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "256Mi"
    }
  }
}

variable "priority_class_name" {
  description = "Priority class assigned to the DaemonSet pods."
  type        = string
  default     = "system-node-critical"
}

variable "pod_annotations" {
  description = "Additional annotations applied to the DaemonSet pods."
  type        = map(string)
  default = {
    "prometheus.io/scrape" = "true"
    "prometheus.io/port"   = "9092"
  }
}

variable "log_level" {
  description = "Log level for the Node Termination Handler (info|debug|error)."
  type        = string
  default     = "info"
}

variable "extra_env" {
  description = "Additional environment variables injected into the DaemonSet containers."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
