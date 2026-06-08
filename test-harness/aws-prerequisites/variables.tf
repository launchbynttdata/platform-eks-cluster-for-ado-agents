variable "aws_region" {
  description = "AWS region for the optional test harness prerequisites."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z0-9-]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, for example us-west-2."
  }
}

variable "name_prefix" {
  description = "Prefix used for harness resource names."
  type        = string
  default     = "ado-agent-harness"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,31}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-33 lowercase alphanumeric or hyphen characters and cannot start or end with a hyphen."
  }
}

variable "state_bucket_name" {
  description = "Optional exact S3 bucket name for the layered cluster Terraform state. Leave null to generate a unique name."
  type        = string
  default     = null

  validation {
    condition = var.state_bucket_name == null || can(regex(
      "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$",
      var.state_bucket_name
    ))
    error_message = "state_bucket_name must be a valid S3 bucket name, or null."
  }
}

variable "state_bucket_force_destroy" {
  description = "Whether to force-delete the state bucket contents when destroying the harness. Keep false unless this is a disposable test."
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the test harness VPC."
  type        = string
  default     = "10.240.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones to use for public and private subnets."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "az_count must be between 2 and 6."
  }
}

variable "public_subnet_cidrs" {
  description = "Optional public subnet CIDRs. Leave empty to derive one /24 per AZ from vpc_cidr."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every public_subnet_cidrs entry must be a valid CIDR block."
  }

  validation {
    condition     = length(var.public_subnet_cidrs) == 0 || length(var.public_subnet_cidrs) == var.az_count
    error_message = "When provided, public_subnet_cidrs must contain exactly az_count entries."
  }
}

variable "private_subnet_cidrs" {
  description = "Optional private subnet CIDRs. Leave empty to derive one /24 per AZ from vpc_cidr."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every private_subnet_cidrs entry must be a valid CIDR block."
  }

  validation {
    condition     = length(var.private_subnet_cidrs) == 0 || length(var.private_subnet_cidrs) == var.az_count
    error_message = "When provided, private_subnet_cidrs must contain exactly az_count entries."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets. Set false for one NAT gateway per AZ."
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Additional tags applied to every harness resource."
  type        = map(string)
  default = {
    Environment = "test"
    Owner       = "platform-team"
  }
}
