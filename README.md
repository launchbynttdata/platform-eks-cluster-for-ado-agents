# Platform NTT ADO Cluster Infrastructure as Code

A Terraform-based Infrastructure as Code (IaC) solution for deploying an AWS EKS cluster with Azure DevOps (ADO) self-hosted agents. This repository provides a complete, production-ready platform for running containerized Azure DevOps agents in AWS using Kubernetes with KEDA autoscaling.

## High-Level Overview

This repository provides a comprehensive solution for deploying Azure DevOps build agents on AWS infrastructure using:

- **AWS EKS Cluster**: Managed Kubernetes cluster with Fargate and optional EC2 node groups
- **Azure DevOps Agents**: Containerized ADO agents with role-based access controls
- **KEDA Autoscaling**: Event-driven autoscaling based on Azure DevOps pipeline queue metrics
- **External Secrets**: Automatic secret synchronization from AWS Secrets Manager to Kubernetes
- **Multi-Role Architecture**: Separate IAM roles for different agent workloads (dev-build, iac, custom)
- **Secure Networking**: VPC endpoints, private subnets, encrypted communications
- **Layered Design**: Three-layer architecture (base → middleware → application) for independent lifecycle management

## Architecture

The canonical deployment uses the **infrastructure-layered** directory with a three-layer Terragrunt-based architecture:

- **Base Layer**: EKS cluster, VPC, IAM, KMS
- **Middleware Layer**: KEDA, External Secrets Operator, buildkitd
- **Application Layer**: ECR repositories, secrets, ADO agent deployments via Helm

All deployment is orchestrated by [infrastructure-layered/deploy.sh](infrastructure-layered/deploy.sh).

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| terraform | 1.12.2 | IaC |
| terragrunt | 0.81.7 | Layer orchestration |
| helm | 3.19.0 | Kubernetes charts |
| kubectl | 1.34.1 | Cluster access |
| aws (CLI) | v2 | AWS operations |
| jq | latest | JSON parsing (used by deploy.sh) |

Optional tools (in [.tool-versions](.tool-versions)): tflint, checkov, python, uv.

This repository uses [.tool-versions](.tool-versions) for version pinning. We recommend [mise](https://mise.jdx.dev/) for managing tool versions. See the [mise installation documentation](https://mise.jdx.dev/installing-mise.html) for setup. After installing mise, run `mise install` in the repository root to install tools from .tool-versions. Note: `aws` and `jq` are not in .tool-versions; install them via your system package manager or add them to .tool-versions if mise supports them for your platform.

### Additional Prerequisites

- **AWS account** with appropriate permissions (EKS, IAM, S3, Secrets Manager, ECR, KMS, etc.)
- **S3 bucket** for Terraform state (Terraform >= 1.10 uses native S3 lockfiles; no DynamoDB table required)
- **Azure DevOps** organization, Personal Access Token (PAT), and agent pool(s)
- **VPC and subnets** (or use defaults from configuration)

## Getting Started

1. **Clone and navigate** to the infrastructure directory:
   ```bash
   git clone <repository-url>
   cd platform-eks-cluster-for-ado-agents/infrastructure-layered
   ```

2. **Configure** by copying the sample config and setting environment variables:
   ```bash
   cp env.sample.hcl env.hcl
   # Edit env.hcl with your VPC, cluster, and ADO settings
   export TF_STATE_BUCKET='your-terraform-state-bucket'
   ```

3. **Deploy** using the orchestration script:
   ```bash
   ./deploy.sh deploy --update-ado-secret
   ```

For detailed configuration, IAM setup, troubleshooting, and operations, see the [infrastructure-layered README](infrastructure-layered/README.md).

## Known Issues

- Fargate profiles should be deployed as iterative list instead of singleton list
- Many IAM policies exist as "inline" that should be refactored to externally managed + attachments

## Contributing

1. Follow the existing modular architecture
2. Test changes in non-production environments
3. Run security scans with Checkov where applicable
4. Update documentation for any new features
5. Use semantic versioning for releases
