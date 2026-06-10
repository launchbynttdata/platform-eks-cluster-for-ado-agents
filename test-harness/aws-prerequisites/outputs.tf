output "tf_state_bucket" {
  description = "S3 bucket to export as TF_STATE_BUCKET for infrastructure-layered."
  value       = aws_s3_bucket.state.bucket
}

output "tf_state_region" {
  description = "AWS region to export as TF_STATE_REGION for infrastructure-layered."
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID to set in infrastructure-layered/env.hcl."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs to set as subnet_ids in infrastructure-layered/env.hcl."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_subnet_ids" {
  description = "Public subnet IDs created for NAT gateways."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_route_table_ids" {
  description = "Private route table IDs used by the cluster base layer for gateway VPC endpoints."
  value       = [for route_table in aws_route_table.private : route_table.id]
}

output "shell_exports" {
  description = "Shell exports required before running infrastructure-layered/deploy.sh."
  value       = <<-EOT
    export TF_STATE_BUCKET='${aws_s3_bucket.state.bucket}'
    export TF_STATE_REGION='${var.aws_region}'
    export AWS_REGION='${var.aws_region}'
  EOT
}

output "cluster_env_hcl_snippet" {
  description = "Copy these values into infrastructure-layered/env.hcl for the optional harness environment."
  value       = <<-EOT
    aws_region = "${var.aws_region}"

    vpc_id = "${aws_vpc.this.id}"
    subnet_ids = ${jsonencode([for subnet in aws_subnet.private : subnet.id])}

    create_vpc_endpoints = true
    vpc_endpoint_services = [
      "s3",
      "ecr_dkr",
      "ecr_api",
      "ec2",
      "logs",
      "monitoring",
      "sts",
      "secretsmanager",
      "autoscaling"
    ]
    exclude_vpc_endpoint_services = []
  EOT
}
