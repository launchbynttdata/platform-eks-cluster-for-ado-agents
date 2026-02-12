variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "profile_name" {
  description = "Name of the Fargate profile"
  type        = string
}

variable "pod_execution_role_arn" {
  description = "ARN of the IAM role for Fargate pod execution"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Fargate profile"
  type        = list(string)
}

variable "selectors" {
  description = "List of selectors for the Fargate profile"
  type = list(object({
    namespace = string
    labels    = optional(map(string), {})
  }))
  default = [
    {
      namespace = "keda-system"
    },
    {
      namespace = "ado-agents"
    }
  ]
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
