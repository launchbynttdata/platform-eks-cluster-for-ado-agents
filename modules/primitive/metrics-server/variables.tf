variable "namespace" {
  description = "Namespace where metrics-server will be installed."
  type        = string
}

variable "create_namespace" {
  description = "Whether to create the namespace if it does not exist."
  type        = bool
  default     = false
}

variable "release_name" {
  description = "Helm release name for metrics-server."
  type        = string
  default     = "metrics-server"
}

variable "repository" {
  description = "Helm repository hosting the metrics-server chart."
  type        = string
  default     = "https://kubernetes-sigs.github.io/metrics-server/"
}

variable "chart_version" {
  description = "Helm chart version to deploy."
  type        = string
}

variable "args" {
  description = "Additional container arguments for the metrics-server deployment."
  type        = list(string)
  default     = []
}

variable "node_selector" {
  description = "Node selector labels for metrics-server pods."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations applied to metrics-server pods."
  type = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))
  default = []
}

variable "resources" {
  description = "Resource requests and limits for metrics-server pods."
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
}
