# Networking Layer Variables
#
# This layer manages Kubernetes CNI components that must be installed after the
# EKS control plane exists and before middleware workloads are deployed.

variable "aws_region" {
  description = "AWS region where resources exist"
  type        = string
  default     = "us-west-2"
}

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

variable "pod_networking_mode" {
  description = "Pod networking implementation. Use vpc-cni for Amazon VPC CNI or cilium-overlay for EC2-only Cilium overlay networking."
  type        = string
  default     = "vpc-cni"

  validation {
    condition     = contains(["vpc-cni", "cilium-overlay"], var.pod_networking_mode)
    error_message = "pod_networking_mode must be either \"vpc-cni\" or \"cilium-overlay\"."
  }
}

variable "cilium_networking" {
  description = "Cilium Helm and cluster-pool IPAM configuration used when pod_networking_mode is cilium-overlay."
  type = object({
    chart_version                   = optional(string, "1.19.5")
    cluster_pool_ipv4_pod_cidr_list = optional(list(string), ["100.64.0.0/10"])
    cluster_pool_ipv4_mask_size     = optional(number, 24)
    helm_values_override            = optional(any, {})
  })
  default = {
    chart_version                   = "1.19.5"
    cluster_pool_ipv4_pod_cidr_list = ["100.64.0.0/10"]
    cluster_pool_ipv4_mask_size     = 24
    helm_values_override            = {}
  }

  validation {
    condition = alltrue([
      for cidr in var.cilium_networking.cluster_pool_ipv4_pod_cidr_list :
      can(cidrhost(cidr, 0))
    ])
    error_message = "Every cilium_networking.cluster_pool_ipv4_pod_cidr_list entry must be a valid CIDR block."
  }

  validation {
    condition     = var.cilium_networking.cluster_pool_ipv4_mask_size >= 16 && var.cilium_networking.cluster_pool_ipv4_mask_size <= 30
    error_message = "cilium_networking.cluster_pool_ipv4_mask_size must be between 16 and 30."
  }
}
