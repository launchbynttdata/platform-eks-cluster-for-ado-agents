locals {
  # Define the VPC endpoints that EKS and Fargate need
  vpc_endpoint_services = {
    s3 = {
      service_name    = "com.amazonaws.${data.aws_region.current.name}.s3"
      service_type    = "Gateway"
      route_table_ids = var.route_table_ids
    }
    ecr_dkr = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
    ecr_api = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
    ec2 = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.ec2"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
    logs = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.logs"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
    monitoring = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.monitoring"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
    sts = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.sts"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
    secretsmanager = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
    autoscaling = {
      service_name       = "com.amazonaws.${data.aws_region.current.name}.autoscaling"
      service_type       = "Interface"
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  # Filter endpoints based on requested services and exclusions
  filtered_endpoints = {
    for k, v in local.vpc_endpoint_services : k => v
    if contains(var.endpoint_services, k) && !contains(var.exclude_endpoint_services, k)
  }
}

data "aws_region" "current" {}

# Gateway VPC Endpoints (S3)
resource "aws_vpc_endpoint" "gateway" {
  for_each = {
    for k, v in local.filtered_endpoints : k => v
    if v.service_type == "Gateway"
  }

  vpc_id            = var.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = each.value.route_table_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${each.key}-gateway-endpoint"
      Type = "VPC-Endpoint-Gateway"
    }
  )
}

# Interface VPC Endpoints
resource "aws_vpc_endpoint" "interface" {
  for_each = {
    for k, v in local.filtered_endpoints : k => v
    if v.service_type == "Interface"
  }

  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = each.value.subnet_ids
  security_group_ids  = each.value.security_group_ids
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${each.key}-interface-endpoint"
      Type = "VPC-Endpoint-Interface"
    }
  )
}
