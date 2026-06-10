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

variable "remote_state_region" {
  description = "AWS region for the Terraform remote state bucket. This can differ from aws_region when the state bucket is centralized."
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

# CloudWatch Logging / Observability
variable "enable_cloudwatch_observability" {
  description = "Whether to create CloudWatch log resources and EKS logging integrations for platform pod logs."
  type        = bool
  default     = true
}

variable "enable_cloudwatch_observability_addon" {
  description = "Whether to install the Amazon CloudWatch Observability EKS add-on for EC2 node log collection."
  type        = bool
  default     = true
}

variable "cloudwatch_observability_addon_version" {
  description = "Version of the Amazon CloudWatch Observability EKS add-on. Null uses the EKS default version."
  type        = string
  default     = null
}

variable "enable_cloudwatch_application_signals_auto_monitor" {
  description = "Whether the CloudWatch Observability add-on should auto-instrument service workloads with Application Signals."
  type        = bool
  default     = true
}

variable "cloudwatch_application_signals_auto_monitor_excluded_namespaces" {
  description = "Additional namespaces to exclude from CloudWatch Application Signals auto-instrumentation. The ESO namespace is always excluded because injected ADOT init containers do not satisfy restricted Pod Security."
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "Retention in days for platform CloudWatch log groups."
  type        = number
  default     = 30
}

variable "enable_fargate_cloudwatch_logging" {
  description = "Whether to create the aws-observability/aws-logging ConfigMap for EKS Fargate pod log shipping."
  type        = bool
  default     = true
}

variable "fargate_fluentbit_log_level" {
  description = "Log level for the EKS Fargate Fluent Bit log router."
  type        = string
  default     = "info"
}

variable "fargate_fluentbit_include_process_logs" {
  description = "Whether Fargate Fluent Bit process logs are sent to CloudWatch."
  type        = bool
  default     = false
}

variable "platform_log_groups" {
  description = "Logical platform log groups to pre-create under /aws/containerinsights/<cluster_name>."
  type        = list(string)
  default     = ["application", "dataplane", "host", "performance", "ado-agents", "buildkit", "keda", "cluster-autoscaler"]
}

variable "application_crd_ready_wait_seconds" {
  description = "Seconds to wait after middleware CRD-owning Helm releases before application-layer custom resources are installed."
  type        = number
  default     = 60

  validation {
    condition     = var.application_crd_ready_wait_seconds >= 0 && var.application_crd_ready_wait_seconds <= 300
    error_message = "application_crd_ready_wait_seconds must be between 0 and 300."
  }
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
  default     = "2.20.0"
}

variable "keda_enable_cloudeventsource" {
  description = "Enable CloudEventSource controller in KEDA. Set to false if CloudEventSource CRDs are not needed to avoid CrashLoopBackOff issues in KEDA 2.15.x"
  type        = bool
  default     = false
}

# Metrics Server Configuration
variable "install_metrics_server" {
  description = "Whether to deploy metrics-server via Helm."
  type        = bool
  default     = true
}

variable "metrics_server_namespace" {
  description = "Namespace where metrics-server will run."
  type        = string
  default     = "kube-system"
}

variable "metrics_server_chart_version" {
  description = "Helm chart version for metrics-server."
  type        = string
  default     = "3.13.0"
}

variable "metrics_server_args" {
  description = "Extra command-line arguments for metrics-server."
  type        = list(string)
  default = [
    "--kubelet-insecure-tls",
    "--kubelet-preferred-address-types=InternalIP,Hostname"
  ]
}

variable "metrics_server_node_selector" {
  description = "Node selector for metrics-server pods."
  type        = map(string)
  default     = {}
}

variable "metrics_server_tolerations" {
  description = "Tolerations for metrics-server pods."
  type = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))
  default = []
}

variable "metrics_server_resources" {
  description = "Resource requests and limits for metrics-server."
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
      memory = "256Mi"
    }
    limits = {
      cpu    = "250m"
      memory = "512Mi"
    }
  }
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
  description = "Version of External Secrets Operator Helm chart to install."
  type        = string
  default     = "1.3.2"
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
  default     = "moby/buildkit:v0.30.0-rootless"
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
      key      = "eks.amazonaws.com/compute-type"
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

variable "buildkitd_hpa_enabled" {
  description = "Whether to manage a Horizontal Pod Autoscaler for buildkitd."
  type        = bool
  default     = true
}

variable "buildkitd_hpa_min_replicas" {
  description = "Minimum number of buildkitd replicas when HPA is enabled."
  type        = number
  default     = 2
}

variable "buildkitd_hpa_max_replicas" {
  description = "Maximum number of buildkitd replicas when HPA is enabled."
  type        = number
  default     = 5
}

variable "buildkitd_hpa_target_memory_utilization_percentage" {
  description = "Target average memory utilization percentage for buildkitd HPA."
  type        = number
  default     = 70
}

variable "buildkitd_ecr_registry_account_ids" {
  description = "AWS account IDs for ECR registries the BuildKit daemon uses (docker credHelpers + IAM). Empty = cluster account only."
  type        = list(string)
  default     = []
}

variable "buildkitd_ecr_repository_arns" {
  description = "ECR repository ARNs BuildKit may pull and push. Empty = arn:aws:ecr:<region>:<cluster_account>:repository/*"
  type        = list(string)
  default     = []
}

variable "buildkitd_kms_key_arn_patterns" {
  description = "KMS key ARN patterns for ECR customer-managed encryption. Empty = arn:aws:kms:<region>:<cluster_account>:key/*"
  type        = list(string)
  default     = []
}

variable "buildkitd_registry_mirrors" {
  description = "Additional or override registry mirror configuration rendered into buildkitd.toml. ECR pull-through cache mirrors are derived automatically from ecr_pull_through_cache_rules."
  type        = map(list(string))
  default     = {}
}

variable "buildkitd_topology_spread_enabled" {
  description = "Whether to spread BuildKit pods across zones when possible."
  type        = bool
  default     = true
}

variable "buildkitd_pdb_enabled" {
  description = "Whether to create a PodDisruptionBudget for BuildKit."
  type        = bool
  default     = true
}

variable "buildkitd_pdb_min_available" {
  description = "Minimum available BuildKit pods during voluntary disruptions."
  type        = number
  default     = 1
}

variable "buildkitd_tls_enabled" {
  description = "Whether BuildKit should require TLS on its TCP listener."
  type        = bool
  default     = false
}

variable "buildkitd_tls_secret_name" {
  description = "Kubernetes secret in the BuildKit namespace containing ca.pem, cert.pem, and key.pem for buildkitd TLS."
  type        = string
  default     = ""
}

variable "enable_ecr_pull_through_cache" {
  description = "Whether to create anonymous-compatible ECR pull-through cache rules."
  type        = bool
  default     = true
}

variable "ecr_pull_through_cache_rules" {
  description = "ECR pull-through cache rules keyed by ECR repository prefix."
  type = map(object({
    upstream_registry_url = string
  }))
  default = {
    ecr-public = {
      upstream_registry_url = "public.ecr.aws"
    }
    k8s = {
      upstream_registry_url = "registry.k8s.io"
    }
    quay = {
      upstream_registry_url = "quay.io"
    }
  }
}

variable "create_ecr_pull_through_cache_repository_templates" {
  description = "Whether to create ECR repository creation templates so pull-through cache repositories are auto-created with a lifecycle policy and repository policy."
  type        = bool
  default     = true
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
  default     = "0.27.6"
}

variable "node_auto_heal_log_level" {
  description = "Log level for the Node Termination Handler pods."
  type        = string
  default     = "info"
}
