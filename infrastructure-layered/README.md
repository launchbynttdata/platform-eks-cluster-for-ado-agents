# EKS ADO Agents - Layered Infrastructure

This directory contains the canonical Terragrunt-based deployment for Azure DevOps agents on Amazon EKS.

## Architecture

Three independent Terraform layers, orchestrated by `deploy.sh`:

| Layer | Contents |
|-------|----------|
| **base** | EKS cluster, VPC endpoints, IAM, KMS, Fargate profiles, addons |
| **middleware** | KEDA, External Secrets Operator, cluster autoscaler, buildkitd |
| **application** | ECR repositories, Secrets Manager, Helm ADO agent deployment |

A **config layer** (kubectl-based, not Terraform) runs after all layers to create the ClusterSecretStore and optionally inject the ADO PAT.

## Prerequisites

- Tools pinned in [`.tool-versions`](../.tool-versions): Terraform, Terragrunt, Helm, kubectl
- AWS CLI and `jq` installed and configured
- S3 bucket for remote state (`TF_STATE_BUCKET`)
- Existing VPC with subnets (configured in `env.hcl`)
- Azure DevOps organization, PAT, and agent pool(s)

## Quick Start

```bash
cd infrastructure-layered

# 1. Configure environment
cp env.sample.hcl env.hcl
# Edit env.hcl: vpc_id, subnet_ids, cluster_name, ado_org, agent pools, etc.

# 2. Set state bucket
export TF_STATE_BUCKET='your-terraform-state-bucket'

# 3. Deploy all layers + config
./deploy.sh deploy --update-ado-secret
```

### Deploy individual layers

```bash
./deploy.sh --layer base deploy
./deploy.sh --layer middleware deploy
./deploy.sh --layer application deploy
./deploy.sh --layer config deploy
```

### Plan before apply

```bash
./deploy.sh --layer all plan
```

## Configuration

All environment-specific values live in `env.hcl` (copy from `env.sample.hcl`). See the [configuration reference](../docs/terragrunt/TERRAGRUNT_CONFIGURATION_REFERENCE.md) for every variable.

Backend state uses S3 with native lockfiles (Terraform 1.10+). The deploy script passes `-backend-config` for the bucket name; no DynamoDB table is required.

## Testing

```bash
make test    # ShellCheck + BATS + Checkov
```

See [testing guide](../docs/guides/TESTING.md).

## Documentation

For operations, IAM, secrets, troubleshooting, and layer details, see the [documentation hub](../docs/README.md).

Key guides:

- [Operations](../docs/deployment/OPERATIONS.md)
- [Terragrunt quickstart](../docs/terragrunt/TERRAGRUNT_QUICKSTART.md)
- [Config layer](../docs/terragrunt/CONFIG_LAYER_IN_TERRAGRUNT.md)
- [IAM for ADO agents](../docs/reference/IAM_ADO_AGENTS.md)
- [ADO secret management](../docs/reference/ADO_SECRET_MANAGEMENT.md)

## Directory Layout

```
infrastructure-layered/
├── deploy.sh          # Main orchestrator
├── env.sample.hcl     # Configuration template (copy to env.hcl)
├── root.hcl           # Terragrunt root config
├── common.hcl         # Shared locals and mocks
├── base/              # Base layer Terraform
├── middleware/        # Middleware layer Terraform
├── application/       # Application layer Terraform
├── helm/              # ADO agent Helm chart
└── tests/             # BATS unit tests for deploy.sh
```
