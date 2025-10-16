terraform {
  backend "s3" {
    bucket       = "nvdmv-batch-poc-tfstate-002"
    key          = "poc/ado-agent-cluster/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true
  }
}