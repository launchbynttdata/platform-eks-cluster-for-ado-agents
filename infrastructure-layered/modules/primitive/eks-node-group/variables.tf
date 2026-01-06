variable "node_group_name" {
  description = "The name of the EKS Node Group"
  type        = string
}

variable "cluster_name" {
  description = "The name of the EKS Cluster"
  type        = string
}

variable "node_role_arn" {
  description = "The ARN of the IAM role to associate with the EKS Node Group"
  type        = string
}

variable "subnet_ids" {
  description = "A list of subnet IDs to launch the EKS Node Group in"
  type        = list(string)
}

variable "instance_types" {
  description = "A list of instance types for the EKS Node Group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "disk_size" {
  description = "The disk size (in GiB) for the EKS Node Group instances"
  type        = number
  default     = 50
}

variable "ami_type" {
  description = "The AMI type for the EKS Node Group"
  type        = string
  default     = null
}

variable "capacity_type" {
  description = "The capacity type for the EKS Node Group (e.g., ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "labels" {
  description = "A map of labels to apply to the EKS Node Group"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "A map of tags to apply to the EKS Node Group"
  type        = map(string)
  default     = {}
}

variable "desired_size" {
  description = "The desired number of nodes in the EKS Node Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "The maximum number of nodes in the EKS Node Group"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "The minimum number of nodes in the EKS Node Group"
  type        = number
  default     = 0
}

variable "taints" {
  description = "A list of taints to apply to the EKS Node Group"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "max_unavailable" {
  description = "The maximum number of nodes that can be unavailable during a node group update"
  type        = number
  default     = 1
}

variable "max_unavailable_percentage" {
  description = "The maximum percentage of nodes that can be unavailable during a node group update"
  type        = number
  default     = null
}

variable "enable_cluster_autoscaler" {
  description = "Whether to enable cluster autoscaler tags for this node group"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_tags" {
  description = "Additional tags for cluster autoscaler discovery and configuration"
  type        = map(string)
  default     = {}
}