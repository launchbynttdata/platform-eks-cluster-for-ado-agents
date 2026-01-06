variable "ecr_repositories" {
  description = "Map of ECR repositories to create"
  type = map(object({
    repository_name         = string
    image_tag_mutability    = optional(string, "MUTABLE")
    encryption_type         = optional(string, "AES256")
    kms_key_arn             = optional(string, "")
    scan_on_push            = optional(bool, true)
    lifecycle_untagged_days = optional(number, 7)
    keep_tagged_count       = optional(number, 10)
  }))
  default = {}
}

variable "cluster_name" {
  description = "Name of the EKS cluster for policy naming"
  type        = string
}

variable "create_iam_policies" {
  description = "Whether to create IAM policies for ECR access"
  type        = bool
  default     = true
}

variable "attach_pull_to_fargate" {
  description = "Whether to attach pull policy to Fargate execution role"
  type        = bool
  default     = false
}

variable "fargate_role_name" {
  description = "Name of the Fargate execution role"
  type        = string
  default     = ""
}

variable "attach_bastion_policy" {
  description = "Whether to attach bastion policy to bastion role"
  type        = bool
  default     = false
}

variable "bastion_role_name" {
  description = "Name of the bastion role"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
