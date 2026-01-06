# Middleware Layer Variables
#
# This file defines all input variables for the middleware infrastructure layer.
# This layer depends on the base layer via remote state.

# AWS Configuration
variable "aws_region" {
  description = "AWS region where resources exist"
  type        = string
  default     = "us-west-2"
}

# Remote State Configuration
variable "remote_state_bucket" {
  description = "S3 bucket name for Terraform remote state"
  type        = string
}

variable "remote_state_environment" {
  description = "Environment prefix for remote state keys (matches env.hcl environment)"
  type        = string
  default     = ""
}

variable "base_state_key" {
  description = "S3 key for base layer Terraform state"
  type        = string
  default     = "base/terraform.tfstate"
}

# KEDA Configuration
variable "install_keda" {
  description = "Whether to install KEDA operator"
  type        = bool
  default     = true
}

variable "keda_namespace" {
  description = "Kubernetes namespace for KEDA operator"
  type        = string
  default     = "keda-system"
}

variable "keda_version" {
  description = "Version of KEDA operator to install"
  type        = string
  default     = "2.17.2"
}

variable "keda_enable_cloudeventsource" {
  description = "Enable CloudEventSource controller in KEDA. Set to false if CloudEventSource CRDs are not needed to avoid CrashLoopBackOff issues in KEDA 2.15.x"
  type        = bool
  default     = false
}

variable "keda_enable_cluster_cloudeventsource" {
  description = "Enable ClusterCloudEventSource controller in KEDA. Set to false if ClusterCloudEventSource CRDs are not needed to avoid CrashLoopBackOff issues in KEDA 2.15.x"
  type        = bool
  default     = false
}

variable "ado_agents_namespace" {
  description = "Kubernetes namespace for ADO agents"
  type        = string
  default     = "ado-agents"
}

variable "ado_secret_name" {
  description = "Name of the Kubernetes secret for ADO PAT"
  type        = string
  default     = null
}

# External Secrets Operator Configuration
variable "install_eso" {
  description = "Whether to install External Secrets Operator"
  type        = bool
  default     = true
}

variable "eso_namespace" {
  description = "Kubernetes namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets-system"
}

variable "eso_version" {
  description = "Version of External Secrets Operator to install"
  type        = string
  default     = "0.10.4"
}

variable "eso_webhook_enabled" {
  description = "Whether to enable ESO webhook validation (disable for Fargate)"
  type        = bool
  default     = false
}

variable "eso_webhook_failure_policy" {
  description = "ESO webhook failure policy (Ignore or Fail)"
  type        = string
  default     = "Ignore"

  validation {
    condition     = contains(["Ignore", "Fail"], var.eso_webhook_failure_policy)
    error_message = "eso_webhook_failure_policy must be either 'Ignore' or 'Fail'."
  }
}

# NOTE: ClusterSecretStore is NOT created by Terraform due to CRD timing limitations.
# It must be created post-deployment using the post-deploy-middleware.sh script.
# See: docs/MIDDLEWARE_POST_DEPLOYMENT_STEPS.md

variable "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore (created by post-deploy script, used by application layer)"
  type        = string
  default     = "aws-secrets-manager"
}

# Buildkitd Configuration
variable "enable_buildkitd" {
  description = "Whether to deploy buildkitd service for container builds"
  type        = bool
  default     = true
}

variable "buildkitd_namespace" {
  description = "Kubernetes namespace for buildkitd service"
  type        = string
  default     = "buildkit-system"
}

variable "buildkitd_image" {
  description = "Docker image for buildkitd"
  type        = string
  default     = "moby/buildkit:v0.12.5"
}

variable "buildkitd_replicas" {
  description = "Number of buildkitd replicas"
  type        = number
  default     = 2
}

variable "buildkitd_node_selector" {
  description = "Node selector for buildkitd pods (use EC2 nodes if available)"
  type        = map(string)
  default = {
    # "workload-type" = "buildkit"
  }
}

variable "buildkitd_tolerations" {
  description = "Tolerations for buildkitd pods"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = [
    {
      key      = "ks.amazonaws.com/compute-type"
      operator = "Equal"
      value    = "fargate"
      effect   = "NoSchedule"
    }
  ]
}

variable "buildkitd_resources" {
  description = "Resource requests and limits for buildkitd"
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
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "2"
      memory = "4Gi"
    }
  }
}

variable "buildkitd_storage_size" {
  description = "Size of buildkitd storage volume"
  type        = string
  default     = "20Gi"
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources (merged with base layer tags)"
  type        = map(string)
  default     = {}
}

# Cluster Autoscaler Deployment (middleware managed)
variable "cluster_autoscaler_node_selector" {
  description = "Node selector applied to the Cluster Autoscaler pod to keep it on system nodes."
  type        = map(string)
  default = {
    "workload-type" = "system"
  }
}

variable "cluster_autoscaler_tolerations" {
  description = "Tolerations for the Cluster Autoscaler pod."
  type = list(object({
    key                = optional(string)
    operator           = optional(string, "Exists")
    value              = optional(string)
    effect             = optional(string)
    toleration_seconds = optional(number)
  }))
  default = [
    {
      key      = "node-role.kubernetes.io/system"
      operator = "Exists"
      effect   = "NoSchedule"
    }
  ]
}

variable "cluster_autoscaler_resources" {
  description = "Resource requests and limits for the Cluster Autoscaler deployment."
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

variable "cluster_autoscaler_priority_class_name" {
  description = "PriorityClass applied to the Cluster Autoscaler pods."
  type        = string
  default     = "system-cluster-critical"
}

variable "cluster_autoscaler_replicas" {
  description = "Number of Cluster Autoscaler replicas to run."
  type        = number
  default     = 1
}

variable "cluster_autoscaler_pod_annotations" {
  description = "Custom annotations added to the Cluster Autoscaler pod template."
  type        = map(string)
  default = {
    "prometheus.io/scrape"                           = "true"
    "prometheus.io/port"                             = "8085"
    "cluster-autoscaler.kubernetes.io/safe-to-evict" = "false"
  }
}

variable "cluster_autoscaler_additional_args" {
  description = "Extra CLI arguments appended after the base autoscaler flags."
  type        = map(string)
  default     = {}
}

# Node Auto-Heal / AWS Node Termination Handler
variable "node_auto_heal_daemonset_tolerations" {
  description = "Tolerations for the Node Termination Handler DaemonSet."
  type = list(object({
    key               = optional(string)
    operator          = optional(string, "Exists")
    value             = optional(string)
    effect            = optional(string)
    tolerationSeconds = optional(number)
  }))
  default = [
    {
      key      = "workload-type"
      operator = "Equal"
      value    = "system"
      effect   = "NoSchedule"
    }
  ]
}

variable "node_auto_heal_daemonset_node_selector" {
  description = "Node selector applied to the Node Termination Handler DaemonSet."
  type        = map(string)
  default = {
    "eks.amazonaws.com/compute-type" = "ec2"
  }
}

variable "node_auto_heal_daemonset_resources" {
  description = "Resource requests/limits for Node Termination Handler pods."
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
      memory = "128Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "256Mi"
    }
  }
}

variable "node_auto_heal_chart_version" {
  description = "Version of the aws-node-termination-handler Helm chart."
  type        = string
  default     = "0.27.3"
}

variable "node_auto_heal_log_level" {
  description = "Log level for the Node Termination Handler pods."
  type        = string
  default     = "info"
}