# Cluster Configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Networking Configuration
variable "vpc_id" {
  description = "ID of the VPC where the cluster will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs where the cluster will be created (should be private subnets)"
  type        = list(string)
}

# IAM Configuration
variable "create_iam_roles" {
  description = "Whether to create IAM roles or use existing ones"
  type        = bool
  default     = true
}

variable "existing_cluster_role_arn" {
  description = "ARN of existing IAM role for EKS cluster (if create_iam_roles is false)"
  type        = string
  default     = null
}

variable "existing_fargate_role_arn" {
  description = "ARN of existing IAM role for Fargate profile (if create_iam_roles is false)"
  type        = string
  default     = null
}

# Security Configuration
variable "create_kms_key" {
  description = "Whether to create a KMS key for EKS cluster encryption"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key for encryption (only used if create_kms_key = false)"
  type        = string
  default     = null
}

variable "kms_key_description" {
  description = "Description for the created KMS key"
  type        = string
  default     = "KMS key for EKS cluster encryption"
}

variable "kms_key_deletion_window_in_days" {
  description = "Number of days to wait before deleting the KMS key"
  type        = number
  default     = 7
}

variable "enabled_cluster_log_types" {
  description = "List of control plane logging to enable"
  type        = list(string)
  default     = []
}

# EKS Add-ons
variable "eks_addons" {
  description = "Map of EKS add-ons to install"
  type = map(object({
    version                     = string
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    service_account_role_arn    = optional(string)
    configuration_values        = optional(string) # will be JSON encoded
  }))
  default = {}
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
  description = "Version of KEDA to install"
  type        = string
  default     = "2.17.2"
}

variable "ado_agents_namespace" {
  description = "Kubernetes namespace for ADO agents"
  type        = string
  default     = "ado-agents"
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
  default     = "0.19.2"
}

variable "eso_create_ado_external_secret" {
  description = "Whether to create an ExternalSecret for the ADO PAT"
  type        = bool
  default     = true
}

# ADO Configuration
variable "ado_org" {
  description = "Azure DevOps organization name"
  type        = string
}

variable "ado_pat_value" {
  description = "Azure DevOps Personal Access Token"
  type        = string
  sensitive   = true
  default     = "REPLACE_ME"
}

variable "ado_pat_secret_name" {
  description = "Name of the AWS Secret containing the ADO Personal Access Token"
  type        = string
  default     = "ado-agent-pat"
}

variable "secret_recovery_days" {
  description = "Number of days to retain secret after deletion"
  type        = number
  default     = 7
}

variable "create_ado_secret" {
  description = "Whether to create Kubernetes secret for ADO PAT"
  type        = bool
  default     = true
}

variable "ado_secret_name" {
  description = "Name of the Kubernetes secret for ADO PAT"
  type        = string
  default     = null
}

# VPC Endpoints Configuration
variable "create_vpc_endpoints" {
  description = "Whether to create VPC endpoints for AWS services"
  type        = bool
  default     = true
}

variable "vpc_endpoint_services" {
  description = "List of AWS services to create VPC endpoints for"
  type        = list(string)
  default     = []
}

variable "exclude_vpc_endpoint_services" {
  description = "List of AWS services to EXCLUDE from VPC endpoint creation (useful for avoiding conflicts with existing endpoints)"
  type        = list(string)
  default     = []
  # Example: ["s3", "ecr_api"] would exclude S3 and ECR API endpoints from being created
}

# Tagging
variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name for resource tagging"
  type        = string
  default     = "ado-agent-cluster"
}

# External Secrets Operator Custom Resource Controls
variable "create_cluster_secret_store" {
  description = "Whether to create ClusterSecretStore resource for AWS Secrets Manager"
  type        = bool
  default     = false
}

variable "create_external_secrets" {
  description = "Whether to create ExternalSecret resources"
  type        = bool
  default     = false
}

# ESO Webhook Configuration
variable "eso_webhook_enabled" {
  description = "Whether to enable ESO webhook validation (disable for Fargate to avoid certificate issues)"
  type        = bool
  default     = false
}

variable "eso_webhook_failure_policy" {
  description = "ESO webhook failure policy (Ignore or Fail)"
  type        = string
  default     = "Ignore"
}

# ADO Agent Execution Roles Configuration
variable "create_ado_execution_roles" {
  description = "Whether to create IAM execution roles for ADO agents"
  type        = bool
  default     = true
}

variable "ado_execution_roles" {
  description = "Configuration for ADO agent execution roles"
  type = map(object({
    service_account_name = string
    namespace            = string
    permissions = list(object({
      effect    = string
      actions   = list(string)
      resources = list(string)
      condition = optional(object({
        test     = string
        variable = string
        values   = list(string)
      }))
    }))
  }))
  default = {}
}

variable "ec2_node_group_policies" {
  description = "Additional IAM policies to attach to the EC2 node group role"
  type        = list(string)
  default     = []
}

variable "ec2_node_group" {
  description = "Configuration for the EC2 node group"
  type = map(object({
    cluster_name                      = optional(string)
    node_role_arn                     = optional(string)
    subnet_ids                        = list(string)
    desired_capacity                  = number
    max_capacity                      = number
    min_capacity                      = number
    instance_types                    = list(string)
    disk_size                         = optional(number, 20)
    taints                            = optional(list(object({ key = string, value = string, effect = string })))
    labels                            = optional(map(string))
    cluster_autoscaler_node_resources = optional(map(string), {})
  }))
  default = {}
}

# Cluster Autoscaler Configuration
variable "enable_cluster_autoscaler" {
  description = "Whether to enable cluster autoscaler for EC2 node groups"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_version" {
  description = "Version of cluster autoscaler to deploy"
  type        = string
  default     = "v1.29.0"
}

variable "cluster_autoscaler_namespace" {
  description = "Kubernetes namespace for cluster autoscaler"
  type        = string
  default     = "kube-system"
}

variable "cluster_autoscaler_settings" {
  description = "Configuration settings for cluster autoscaler"
  type = object({
    scale_down_enabled            = optional(bool, true)
    scale_down_delay_after_add    = optional(string, "10m")
    scale_down_unneeded_time      = optional(string, "10m")
    max_node_provision_time       = optional(string, "15m")
    expander                      = optional(string, "least-waste")
    skip_nodes_with_system_pods   = optional(bool, false)
    skip_nodes_with_local_storage = optional(bool, false)
    balance_similar_node_groups   = optional(bool, true)
  })
  default = {}
}

variable "fargate_profile_selectors" {
  description = "List of maps defining Fargate profile selectors"
  type        = list(object({ namespace = string, labels = optional(map(string), {}) }))
  default     = []
}

variable "fargate_system_profile_selectors" {
  description = "List of maps defining Fargate profile selectors"
  type        = list(object({ namespace = string, labels = optional(map(string), {}) }))
  default     = []
}

