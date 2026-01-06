variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "create_cluster_role" {
  description = "Whether to create the EKS cluster service role"
  type        = bool
  default     = true
}

variable "create_fargate_role" {
  description = "Whether to create the Fargate pod execution role"
  type        = bool
  default     = true
}

variable "create_keda_role" {
  description = "Whether to create the KEDA operator role"
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA"
  type        = string
  default     = ""
}

variable "keda_namespace" {
  description = "Kubernetes namespace for KEDA operator"
  type        = string
  default     = "keda-system"
}

variable "ado_pat_secret_arn" {
  description = "ARN of the AWS Secret containing the ADO Personal Access Token"
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}
