variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where endpoints will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for interface endpoints"
  type        = list(string)
}

variable "route_table_ids" {
  description = "List of route table IDs for gateway endpoints"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for interface endpoints"
  type        = list(string)
}

variable "endpoint_services" {
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

variable "exclude_endpoint_services" {
  description = "List of AWS services to EXCLUDE from VPC endpoint creation (useful for avoiding conflicts with existing endpoints)"
  type        = list(string)
  default     = []
  # Example: ["s3", "ecr_api"] would exclude S3 and ECR API endpoints from being created
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}
