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
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
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
variable "create_kms_key" {
  description = "Whether to create a KMS key for EKS cluster encryption"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of existing KMS key for EKS cluster encryption (if create_kms_key is false)"
  type        = string
  default     = null
}

variable "kms_key_description" {
  description = "Description for the KMS key"
  type        = string
  default     = "EKS Cluster encryption key"
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