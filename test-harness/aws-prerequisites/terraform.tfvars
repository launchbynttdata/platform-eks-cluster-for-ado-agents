aws_region  = "us-west-1"
name_prefix = "ado-agent-harness"

# Leave null to generate a unique state bucket name.
state_bucket_name          = null
state_bucket_force_destroy = false

vpc_cidr           = "10.240.0.0/16"
az_count           = 2
single_nat_gateway = true

common_tags = {
  Environment = "test"
  Owner       = "platform-team"
  CostCenter  = "engineering"
}
