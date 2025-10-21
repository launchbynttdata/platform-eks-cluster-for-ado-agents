variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs to grant access to"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster for policy naming"
  type        = string
}

variable "create_pull_policy" {
  description = "Whether to create the ECR pull policy"
  type        = bool
  default     = true
}

variable "create_bastion_policy" {
  description = "Whether to create the ECR bastion policy"
  type        = bool
  default     = true
}

variable "attach_pull_to_fargate" {
  description = "Whether to attach pull policy to Fargate execution role"
  type        = bool
  default     = false
}

variable "fargate_role_name" {
  description = "Name of the Fargate execution role (if attaching pull policy)"
  type        = string
  default     = ""
}

variable "attach_bastion_policy" {
  description = "Whether to attach bastion policy to bastion role"
  type        = bool
  default     = false
}

variable "bastion_role_name" {
  description = "Name of the bastion role (if attaching bastion policy)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to IAM policies"
  type        = map(string)
  default     = {}
}
