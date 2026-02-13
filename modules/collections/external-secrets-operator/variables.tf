# External Secrets Operator Module Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets-system"
}

variable "create_namespace" {
  description = "Whether to create the External Secrets Operator namespace"
  type        = bool
  default     = true
}

variable "eso_version" {
  description = "Version of External Secrets Operator Helm chart to install (1.3.x = ESO app 1.3)"
  type        = string
  default     = "1.3.2"
}

variable "release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "external-secrets"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "service_account_annotations" {
  description = "Annotations for the External Secrets Operator service account"
  type        = map(string)
  default     = {}
}

# ClusterSecretStore Configuration
variable "create_cluster_secret_store" {
  description = "Whether to create a ClusterSecretStore for AWS Secrets Manager"
  type        = bool
  default     = false # Default to false to allow two-phase deployment
}

variable "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore"
  type        = string
  default     = "aws-secrets-manager"
}

variable "aws_region" {
  description = "AWS region for the ClusterSecretStore"
  type        = string
}

# ExternalSecret Configuration
variable "create_external_secrets" {
  description = "Whether to create ExternalSecret resources"
  type        = bool
  default     = false # Default to false to allow two-phase deployment
}

variable "external_secrets" {
  description = "Map of external secrets to create"
  type = map(object({
    namespace        = string
    secret_name      = string
    aws_secret_name  = string
    refresh_interval = optional(string, "1h")
    secret_type      = optional(string, "Opaque")
    data_key_mapping = optional(map(string), {})
  }))
  default = {}
}

# Resource Configuration
variable "resources" {
  description = "Resource limits and requests for External Secrets Operator pods"
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
      cpu    = "100m"
      memory = "128Mi"
    }
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
  }
}

variable "webhook_resources" {
  description = "Resource limits and requests for External Secrets Operator webhook pods"
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
      cpu    = "100m"
      memory = "128Mi"
    }
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
  }
}

variable "cert_controller_resources" {
  description = "Resource limits and requests for External Secrets Operator cert controller pods"
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
      cpu    = "100m"
      memory = "128Mi"
    }
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
  }
}

# Node scheduling
variable "node_selector" {
  description = "Node selector for External Secrets Operator pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for External Secrets Operator pods"
  type        = list(any)
  default     = []
}

variable "affinity" {
  description = "Affinity rules for External Secrets Operator pods"
  type        = any
  default     = {}
}

# Webhook configuration
variable "webhook_enabled" {
  description = "Whether to enable webhook validation (disable for Fargate to avoid certificate issues)"
  type        = bool
  default     = false
}

variable "webhook_failurePolicy" {
  description = "Webhook failure policy (Ignore or Fail)"
  type        = string
  default     = "Ignore"
  validation {
    condition     = contains(["Ignore", "Fail"], var.webhook_failurePolicy)
    error_message = "webhook_failurePolicy must be either 'Ignore' or 'Fail'."
  }
}
