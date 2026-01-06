# Terragrunt Quick Start Guide

## Prerequisites

1. **Install Required Tools**

```bash
# Terraform
brew install terraform

# Terragrunt
brew install terragrunt

# AWS CLI
brew install awscli

# kubectl
brew install kubectl

# Helm
brew install helm
```

2. **Configure AWS Credentials**

```bash
aws configure
# or
export AWS_PROFILE=your-profile
```

3. **Create S3 State Bucket**

```bash
# Create bucket for Terraform state
export TF_STATE_BUCKET="my-terraform-state-$(uuidgen | tr '[:upper:]' '[:lower:]')"
aws s3 mb "s3://${TF_STATE_BUCKET}" --region us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "${TF_STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "${TF_STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

## 5-Minute Deployment

### Step 1: Configure Environment

```bash
cd infrastructure-layered

# Copy sample configuration
cp env.sample.hcl env.hcl

# Edit configuration (required values)
vim env.hcl
```

**Minimum required changes in `env.hcl`:**

```hcl
locals {
  # Change these values
  aws_region   = "us-west-2"              # Your AWS region
  cluster_name = "my-ado-agent-cluster"   # Unique cluster name
  
  vpc_id = "vpc-xxxxx"                    # Your VPC ID
  subnet_ids = [                          # Your private subnet IDs
    "subnet-xxxxx",
    "subnet-yyyyy"
  ]
  
  # ADO Configuration
  ado_org = "your-org"                    # Your ADO organization
  ado_url = "https://dev.azure.com/your-org"
}
```

### Step 2: Set Environment Variables

```bash
# Required
export TF_STATE_BUCKET='your-state-bucket-name'
export TF_STATE_REGION='us-west-2'

# For ADO agents (required later)
export TF_VAR_ado_pat_value='your-ado-personal-access-token'

# Optional
export AWS_REGION='us-west-2'
```

Or use direnv:

```bash
# Create .envrc
cat > .envrc << 'EOF'
export TF_STATE_BUCKET='your-state-bucket-name'
export TF_STATE_REGION='us-west-2'
export AWS_REGION='us-west-2'
export TF_VAR_ado_pat_value='your-ado-pat'
EOF

# Allow direnv
direnv allow
```

### Step 3: Deploy Infrastructure

```bash
# Validate configuration
./deploy-tg.sh validate

# Show deployment plan
./deploy-tg.sh plan

# Deploy all layers (Terraform + Config)
./deploy-tg.sh deploy

# Or deploy step-by-step:
./deploy-tg.sh deploy --layer base
./deploy-tg.sh deploy --layer middleware
./deploy-tg.sh deploy --layer application
./deploy-tg.sh deploy --layer config        # Post-deployment kubectl setup
```

That's it! ✅

## What Gets Deployed

### Base Layer (~5 minutes)
- EKS Cluster (Kubernetes 1.33)
- EC2 node groups (system-nodes, buildkit-nodes, agent-nodes)
- VPC endpoints for private networking
- KMS encryption key
- IAM roles and policies

### Middleware Layer (~3 minutes)
- KEDA (Kubernetes Event-Driven Autoscaling)
- External Secrets Operator
- Buildkitd (optional, for image building)
- Required namespaces

### Application Layer (~2 minutes)
- ECR repositories for custom agent images
- AWS Secrets Manager integration
- ADO agent deployments
- KEDA autoscaling configuration

### Config Layer (~1 minute) - **Required for ADO agents to work**
- kubectl configuration for cluster access
- ClusterSecretStore creation (enables secret sync from AWS Secrets Manager)
- Waits for ClusterSecretStore to become ready
- Optional: Update ADO PAT in AWS Secrets Manager

**Total deployment time: ~11 minutes**

> **Important**: The config layer is **required** for External Secrets Operator to sync secrets from AWS Secrets Manager. Without it, ADO agents cannot authenticate.
>
> See [CONFIG_LAYER_IN_TERRAGRUNT.md](./CONFIG_LAYER_IN_TERRAGRUNT.md) for detailed information.

## Post-Deployment

### Configure kubectl

```bash
# Automatically configured by config layer, or manually:
aws eks update-kubeconfig \
  --region us-west-2 \
  --name my-ado-agent-cluster
```

### Verify Deployment

```bash
# Check cluster
kubectl cluster-info

# Check nodes (Fargate)
kubectl get nodes

# Check KEDA
kubectl get pods -n keda-system

# Check ADO agents
kubectl get pods -n ado-agents

# Check scaling objects
kubectl get scaledobjects -n ado-agents
```

### Check Agent Status

```bash
# Watch agents scale
kubectl get pods -n ado-agents -w

# Check KEDA metrics
kubectl get scaledobjects -n ado-agents -o yaml

# View agent logs
kubectl logs -n ado-agents -l app=ado-agent --tail=50
```

## Common Commands

### Deploy Specific Layer

```bash
# Base layer only
./deploy-tg.sh deploy --layer base

# Middleware layer only
./deploy-tg.sh deploy --layer middleware

# Application layer only
./deploy-tg.sh deploy --layer application
```

### Update Configuration

```bash
# 1. Edit configuration
vim env.hcl

# 2. Plan changes
./deploy-tg.sh plan

# 3. Apply changes
./deploy-tg.sh deploy
```

### Show Status

```bash
./deploy-tg.sh status
```

### Destroy Infrastructure

```bash
# Destroy all layers (in reverse order)
./deploy-tg.sh destroy

# Or destroy specific layer
./deploy-tg.sh destroy --layer application
```

## Using Terragrunt Directly

### Deploy All Layers

```bash
cd infrastructure-layered
terragrunt run-all apply --terragrunt-non-interactive

# Note: This deploys Terraform layers only
# For post-deployment config (ClusterSecretStore), use:
./deploy-tg.sh deploy --layer config
```

**Important**: The `run-all` command deploys only Terraform-managed layers (base, middleware, application). The **config layer** is kubectl-based and must be run separately. See [CONFIG_LAYER_IN_TERRAGRUNT.md](./CONFIG_LAYER_IN_TERRAGRUNT.md) for details.

### Deploy Single Layer

```bash
cd infrastructure-layered/base
terragrunt apply
```

### Show Outputs

```bash
cd infrastructure-layered/base
terragrunt output

# Get specific output
terragrunt output -raw cluster_name
```

### Graph Dependencies

```bash
cd infrastructure-layered
terragrunt graph-dependencies | dot -Tpng > dependencies.png
```

## Multi-Environment Setup

### Quick Method

```bash
# Create environment configs
cp env.sample.hcl env.dev.hcl
cp env.sample.hcl env.prod.hcl

# Edit each
vim env.dev.hcl
vim env.prod.hcl

# Switch to development
ln -sf env.dev.hcl env.hcl
./deploy-tg.sh deploy

# Switch to production
ln -sf env.prod.hcl env.hcl
./deploy-tg.sh deploy
```

## Troubleshooting

### Check Prerequisites

```bash
./deploy-tg.sh --help
```

### Verbose Output

```bash
./deploy-tg.sh deploy --verbose
```

### Clear Cache

```bash
find . -type d -name ".terragrunt-cache" -exec rm -rf {} +
```

### Check AWS Credentials

```bash
aws sts get-caller-identity
```

### Verify State Bucket

```bash
aws s3 ls "s3://${TF_STATE_BUCKET}/"
```

## Next Steps

1. **Customize Configuration**
   - Review `env.hcl` for additional options
   - Adjust resource sizing, scaling parameters
   - Configure additional agent pools

2. **Build Custom Images**
   - Follow instructions in `app/README.md`
   - Push images to ECR repositories
   - Update `env.hcl` with ECR image URLs

3. **Configure ADO Pipelines**
   - Point pipelines to your new agent pools
   - Test autoscaling behavior
   - Monitor agent performance

4. **Production Hardening**
   - Review security configurations
   - Enable additional logging
   - Configure backup/disaster recovery
   - Set up monitoring and alerting

## Getting Help

- **Documentation**: See [TERRAGRUNT_MIGRATION.md](./docs/TERRAGRUNT_MIGRATION.md)
- **Main README**: [README.md](./README.md)
- **Terragrunt Docs**: <https://terragrunt.gruntwork.io/docs/>

## Comparison: Old vs New

| Task | Old (Terraform) | New (Terragrunt) |
|------|----------------|------------------|
| **Configure** | Edit 3 tfvars files | Edit 1 env.hcl file |
| **Deploy** | `./deploy.sh deploy` | `./deploy-tg.sh deploy` |
| **Dependencies** | Manual remote_state | Automatic |
| **Multi-env** | Copy/edit tfvars | Switch env.hcl |
| **Backend config** | 3 separate configs | 1 generated config |

## Tips

- 💡 Use `--dry-run` to see what would happen
- 💡 Always run `plan` before `apply`
- 💡 Use `--verbose` for debugging
- 💡 Keep `env.hcl` out of version control for secrets
- 💡 Use environment variables for sensitive data
- 💡 Leverage `terragrunt run-all` for efficiency
