variable "name" {
  description = "The base name for the security group"
  type        = string
}

variable "security_group_suffix" {
  description = "The suffix for the security group name"
  type        = string
}

variable "description" {
  description = "Description for the security group"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC where the security group will be created"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "legacy_ingress_rules" {
  description = "Legacy ingress rules using inline ingress blocks (for compatibility)"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = optional(string)
  }))
  default = []
}

variable "legacy_egress_rules" {
  description = "Legacy egress rules using inline egress blocks (for compatibility)"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = optional(string)
  }))
  default = []
}

variable "ingress_rules" {
  description = "List of ingress rules for the security group"
  type = list(object({
    name                         = string
    description                  = optional(string)
    from_port                    = number
    to_port                      = number
    ip_protocol                  = string
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = []
}

variable "egress_rules" {
  description = "List of egress rules for the security group"
  type = list(object({
    name                         = string
    description                  = optional(string)
    from_port                    = number
    to_port                      = number
    ip_protocol                  = string
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = []
}
