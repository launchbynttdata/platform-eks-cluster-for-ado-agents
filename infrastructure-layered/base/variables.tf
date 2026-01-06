# Base Infrastructure Layer Variables
#
# This file defines all input variables for the base infrastructure layer.
# All values should be provided via terraform.tfvars or environment variables.

# AWS Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only alphanumeric characters and hyphens."
  }
}

variable "cluster_version" {
  description = <<-EOT
    Kubernetes version for the EKS cluster.
    
    AWS EKS supports the 4 most recent minor versions. As of late 2024/early 2025:
    - 1.31 (supported until ~Nov 2025)
    - 1.32 (supported until ~Jan 2026) 
    - 1.33 (supported until ~Mar 2026)
    - 1.34 (supported until ~May 2026)
    
    Versions older than 1.30 should be avoided as they're near or past EOL.
    For latest support info: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  EOT
  type        = string
  default     = "1.33"

  validation {
    condition     = can(regex("^1\\.(3[1-9]|[4-9][0-9])$", var.cluster_version))
    error_message = <<-EOT
      EKS cluster version must be 1.31 or higher.
      Older versions are either unsupported or approaching end-of-life.
      
      Current AWS-supported versions (as of Oct 2024): 1.31, 1.32, 1.33, 1.34+
      Check current support: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
    EOT
  }
}

variable "endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled. When true, requires specific CIDRs in public_access_cidrs. Defaults to false (private-only access)."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint. If empty or contains 0.0.0.0/0, public access will be disabled regardless of endpoint_public_access setting."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.public_access_cidrs :
      can(cidrhost(cidr, 0))
    ])
    error_message = "All entries in public_access_cidrs must be valid CIDR blocks."
  }
}

variable "enabled_cluster_log_types" {
  description = "List of control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# Networking Configuration
variable "vpc_id" {
  description = "ID of the VPC where the cluster will be created"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs where the cluster will be created (should be private subnets)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets are required for high availability."
  }
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
# KMS key is now always created for shared cluster encryption
variable "kms_key_description" {
  description = "Description for the shared cluster KMS key (used for EKS, Secrets Manager, ECR)"
  type        = string
  default     = "Shared cluster encryption key for EKS, Secrets Manager, and ECR"
}

variable "kms_key_deletion_window_in_days" {
  description = "Number of days to wait before deleting the KMS key"
  type        = number
  default     = 7

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Fargate Configuration
variable "fargate_profiles" {
  description = "Map of Fargate profiles to create. Each profile can have multiple selectors."
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
  }))
  default = {
    apps = {
      selectors = [
        {
          namespace = "keda-system"
          labels    = {}
        },
        {
          namespace = "external-secrets"
          labels    = {}
        },
        {
          namespace = "ado-agents"
          labels    = {}
        }
      ]
    }
    system = {
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            "k8s-app" = "kube-dns"
          }
        }
      ]
    }
  }
}

# EKS Add-ons
variable "eks_addons" {
  description = "Map of EKS add-ons to install"
  type = map(object({
    version                     = string
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    service_account_role_arn    = optional(string, null)
    configuration_values        = optional(string, null)
  }))
  default = {
    "coredns" = {
      version = "v1.11.1-eksbuild.9"
    }
    "kube-proxy" = {
      version = "v1.33.0-eksbuild.1"
    }
    "vpc-cni" = {
      version = "v1.18.3-eksbuild.1"
    }
    "metrics-server" = {
      version = "v0.7.2-eksbuild.1"
        configuration_values = <<JSON
{
  "args": [
    "--kubelet-insecure-tls",
    "--kubelet-preferred-address-types=InternalIP,Hostname"
  ]
}
JSON
    }
  }
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
  default = [
    "s3",
    "ecr_dkr",
    "ecr_api",
    "ec2",
    "logs",
    "monitoring",
    "sts",
    "secretsmanager"
  ]
}

variable "exclude_vpc_endpoint_services" {
  description = "List of AWS services to EXCLUDE from VPC endpoint creation"
  type        = list(string)
  default     = []
}

# EC2 Node Groups (optional)
variable "ec2_node_group" {
  description = "Map of EC2 node group configurations"
  type = map(object({
    instance_types = optional(list(string), ["t3.medium"])
    disk_size      = optional(number, 50)
    ami_type       = optional(string, "AL2_x86_64")
    capacity_type  = optional(string, "ON_DEMAND")
    labels         = optional(map(string), {})
    desired_size   = optional(number, 1)
    max_size       = optional(number, 3)
    min_size       = optional(number, 0)
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "ec2_node_group_policies" {
  description = "List of IAM policy ARNs to attach to EC2 node group role"
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
}

# Cluster Autoscaler Configuration
variable "enable_cluster_autoscaler" {
  description = "Whether to enable cluster autoscaler IAM role and policies"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_namespace" {
  description = "Kubernetes namespace for cluster autoscaler"
  type        = string
  default     = "kube-system"
}

variable "cluster_autoscaler_version" {
  description = "Container image tag for the Kubernetes Cluster Autoscaler (must match the EKS control plane minor version)."
  type        = string
  default     = "v1.33.0"
}

variable "cluster_autoscaler_extra_args" {
  description = "Additional command-line arguments for the Cluster Autoscaler container (map of flag => value)."
  type        = map(string)
  default     = {}
}

# Node Auto-Heal / AWS Node Termination Handler
variable "enable_node_auto_heal" {
  description = "Whether to provision queue-based AWS Node Termination Handler infrastructure (EventBridge + SQS + IRSA)."
  type        = bool
  default     = false
}

variable "node_auto_heal_namespace" {
  description = "Namespace where the Node Termination Handler DaemonSet will run."
  type        = string
  default     = "kube-system"
}

variable "node_auto_heal_queue_retention_seconds" {
  description = "Message retention period for the Node Termination Handler SQS queue."
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.node_auto_heal_queue_retention_seconds >= 60 && var.node_auto_heal_queue_retention_seconds <= 1209600
    error_message = "Retention must be between 60 seconds and 14 days."
  }
}

variable "node_auto_heal_enable_dlq" {
  description = "Whether to create a dead-letter queue for undeliverable termination events."
  type        = bool
  default     = true
}

variable "node_auto_heal_dlq_max_receive_count" {
  description = "Number of times a message can be received before moving to the DLQ."
  type        = number
  default     = 5

  validation {
    condition     = var.node_auto_heal_dlq_max_receive_count >= 1 && var.node_auto_heal_dlq_max_receive_count <= 1000
    error_message = "DLQ max receive count must be between 1 and 1000."
  }
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