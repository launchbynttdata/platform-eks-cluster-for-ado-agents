output "gateway_endpoint_ids" {
  description = "Map of gateway VPC endpoint IDs"
  value = {
    for k, v in aws_vpc_endpoint.gateway : k => v.id
  }
}

output "interface_endpoint_ids" {
  description = "Map of interface VPC endpoint IDs"
  value = {
    for k, v in aws_vpc_endpoint.interface : k => v.id
  }
}

output "gateway_endpoint_arns" {
  description = "Map of gateway VPC endpoint ARNs"
  value = {
    for k, v in aws_vpc_endpoint.gateway : k => v.arn
  }
}

output "interface_endpoint_arns" {
  description = "Map of interface VPC endpoint ARNs"
  value = {
    for k, v in aws_vpc_endpoint.interface : k => v.arn
  }
}

output "all_endpoint_ids" {
  description = "List of all VPC endpoint IDs"
  value = concat(
    values(aws_vpc_endpoint.gateway)[*].id,
    values(aws_vpc_endpoint.interface)[*].id
  )
}
