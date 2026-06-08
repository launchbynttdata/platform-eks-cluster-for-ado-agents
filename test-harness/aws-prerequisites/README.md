# ADO Agent Cluster Test Harness Prerequisites

This optional Terraform root creates the AWS prerequisites needed to test the
layered ADO agent EKS cluster IaC in an isolated environment.

It is intentionally standalone. The cluster IaC does not depend on this root;
instead, apply this harness first and copy/export its outputs into
`infrastructure-layered`.

## Resources

- S3 bucket for the layered stack's Terraform state
- VPC with DNS support enabled
- Public subnets for NAT gateways
- Private subnets for EKS, node groups, Fargate profiles, and VPC endpoints
- Internet gateway, NAT gateway egress, and route tables

The layered base stack should still create the AWS VPC endpoints. This avoids
duplicate endpoint ownership and lets the cluster stack manage the endpoint
services it already expects.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
./harness.sh plan --var-file terraform.tfvars
./harness.sh deploy --var-file terraform.tfvars
```

After deploy, export the generated state bucket values:

```bash
terraform output -raw shell_exports
```

Then copy the `cluster_env_hcl_snippet` values into
`../../infrastructure-layered/env.hcl`.

## Destroy

Destroy is intentionally guarded:

```bash
./harness.sh destroy --var-file terraform.tfvars
```

Type `destroy test harness` when prompted. If the state bucket has objects,
destroy will fail unless `state_bucket_force_destroy = true`.
