resource "aws_security_group" "this" {
  name        = join("-", [var.name, var.security_group_suffix])
  description = var.description
  vpc_id      = var.vpc_id

  # Legacy ingress/egress blocks for security groups that need them
  dynamic "ingress" {
    for_each = var.legacy_ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }

  dynamic "egress" {
    for_each = var.legacy_egress_rules
    content {
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
      description = egress.value.description
    }
  }

  tags = merge(
    {
      name = join("-", [var.name, var.security_group_suffix])
    },
    var.tags
  )
}

# Ingress rules using the newer aws_vpc_security_group_ingress_rule resource
resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for idx, rule in var.ingress_rules : idx => rule }

  security_group_id = aws_security_group.this.id
  description       = each.value.description

  # CIDR-based rules
  cidr_ipv4 = lookup(each.value, "cidr_ipv4", null)
  cidr_ipv6 = lookup(each.value, "cidr_ipv6", null)

  # Security group reference rules
  referenced_security_group_id = lookup(each.value, "referenced_security_group_id", null)

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  tags = merge(
    {
      name = join("-", [var.name, each.value.name])
    },
    var.tags
  )
}

# Egress rules using the newer aws_vpc_security_group_egress_rule resource
resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for idx, rule in var.egress_rules : idx => rule }

  security_group_id = aws_security_group.this.id
  description       = each.value.description

  # CIDR-based rules
  cidr_ipv4 = lookup(each.value, "cidr_ipv4", null)
  cidr_ipv6 = lookup(each.value, "cidr_ipv6", null)

  # Security group reference rules
  referenced_security_group_id = lookup(each.value, "referenced_security_group_id", null)

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  tags = merge(
    {
      name = join("-", [var.name, each.value.name])
    },
    var.tags
  )
}
