variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where security groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "create_cluster_sg" {
  description = "Whether to create security group for EKS cluster"
  type        = bool
  default     = true
}

variable "create_fargate_sg" {
  description = "Whether to create security group for Fargate pods"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the EKS API server"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}
