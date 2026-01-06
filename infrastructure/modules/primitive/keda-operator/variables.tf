variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for KEDA operator"
  type        = string
  default     = "keda-system"
}

variable "ado_namespace" {
  description = "Kubernetes namespace for ADO agents"
  type        = string
  default     = "ado-agents"
}

variable "create_namespace" {
  description = "Whether to create the KEDA namespace"
  type        = bool
  default     = true
}

variable "create_ado_namespace" {
  description = "Whether to create the ADO agents namespace"
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Name of the Helm release for KEDA"
  type        = string
  default     = "keda"
}

variable "keda_version" {
  description = "Version of KEDA Helm chart"
  type        = string
  default     = "2.17.2"
}

variable "keda_image_repository" {
  description = "Repository for KEDA image"
  type        = string
  default     = "ghcr.io/kedacore/keda"
}

variable "keda_image_tag" {
  description = "Tag for KEDA image"
  type        = string
  default     = "2.17.2"
}

variable "metrics_server_image_repository" {
  description = "Repository for KEDA metrics server image"
  type        = string
  default     = "ghcr.io/kedacore/keda-metrics-apiserver"
}

variable "metrics_server_image_tag" {
  description = "Tag for KEDA metrics server image"
  type        = string
  default     = "2.17.2"
}

variable "webhooks_image_repository" {
  description = "Repository for KEDA webhooks image"
  type        = string
  default     = "ghcr.io/kedacore/keda-admission-webhooks"
}

variable "webhooks_image_tag" {
  description = "Tag for KEDA webhooks image"
  type        = string
  default     = "2.17.2"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for KEDA"
  type        = string
  default     = "keda-operator"
}

variable "service_account_annotations" {
  description = "Annotations for the KEDA service account"
  type        = map(string)
  default     = {}
}

variable "resources" {
  description = "Resource limits and requests for KEDA pods"
  type = object({
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    requests = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
  })
  default = {
    limits = {
      cpu    = "1000m"
      memory = "1000Mi"
    }
    requests = {
      cpu    = "100m"
      memory = "100Mi"
    }
  }
}

variable "node_selector" {
  description = "Node selector for KEDA pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for KEDA pods"
  type = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))
  default = []
}

variable "affinity" {
  description = "Affinity for KEDA pods"
  type        = any
  default     = {}
}

variable "env" {
  description = "Additional environment variables for KEDA operator"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "create_ado_secret" {
  description = "Whether to create the ADO PAT secret"
  type        = bool
  default     = true
}

variable "eso_managed_secret" {
  description = "Whether the ADO PAT secret is managed by External Secrets Operator"
  type        = bool
  default     = false
}

variable "ado_secret_name" {
  description = "Name of the Kubernetes secret for ADO PAT"
  type        = string
  default     = "ado-agent-pat"
}

variable "create_scaled_object" {
  description = "Whether to create the KEDA ScaledObject for ADO agents"
  type        = bool
  default     = false
}

variable "deployment_name" {
  description = "Name of the ADO agent deployment to scale"
  type        = string
  default     = "ado-agent"
}

variable "min_replica_count" {
  description = "Minimum number of ADO agent replicas"
  type        = number
  default     = 0
}

variable "max_replica_count" {
  description = "Maximum number of ADO agent replicas"
  type        = number
  default     = 10
}

variable "agent_pool_name" {
  description = "Name of the ADO agent pool"
  type        = string
  default     = "default"
}
