# EKS ADO Agents - Layered Infrastructure Architecture

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Layer Structure](#layer-structure)
4. [Prerequisites](#prerequisites)
5. [Quick Start](#quick-start)
6. [Detailed Deployment](#detailed-deployment)
7. [Configuration](#configuration)
8. [Operations](#operations)
9. [Troubleshooting](#troubleshooting)
10. [Security](#security)
11. [Monitoring](#monitoring)
12. [Cost Optimization](#cost-optimization)
13. [Migration Guide](#migration-guide)
14. [FAQ](#faq)

## Overview

This project provides a comprehensive, production-ready infrastructure solution for running Azure DevOps (ADO) agents on Amazon EKS. The architecture has been completely refactored from a monolithic structure into a three-layer approach that enables:

- **Independent lifecycle management** of infrastructure components
- **Zero-downtime upgrades** of individual components
- **Elimination of circular dependencies**
- **Enhanced security** through proper separation of concerns
- **Improved scalability** and maintainability

### Key Features

- ✅ **Multi-layer architecture** (base → middleware → application)
- ✅ **KEDA-based autoscaling** (scale to zero when no work queued)
- ✅ **External Secrets integration** for secure credential management
- ✅ **Fargate-optimized deployment** for cost efficiency
- ✅ **Multi-agent pool support** with different resource profiles
- ✅ **Comprehensive monitoring** and observability
- ✅ **Infrastructure as Code** with Terraform and Helm
- ✅ **Turn-key deployment** with automated orchestration
- ✅ **Production security** with IRSA, KMS encryption, and network policies

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                Azure DevOps                                     │
│                           (Pipeline Queue Monitoring)                           │
└─────────────────────────────────┬───────────────────────────────────────────────┘
                                  │ API Calls for Queue Length
                                  │
┌─────────────────────────────────▼───────────────────────────────────────────────┐
│                            Amazon EKS Cluster                                  │
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐               │
│  │  Application    │  │   Middleware    │  │      Base       │               │
│  │     Layer       │  │     Layer       │  │     Layer       │               │
│  │                 │  │                 │  │                 │               │
│  │ • ADO Agents    │◄─┤ • KEDA          │◄─┤ • EKS Cluster   │               │
│  │ • ECR Repos     │  │ • Ext. Secrets  │  │ • VPC/Networking │               │
│  │ • Secrets Mgmt  │  │ • buildkitd     │  │ • IAM Roles     │               │
│  │ • IAM Roles     │  │ • Namespaces    │  │ • Security      │               │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘               │
└─────────────────────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────────────────────┐
│                              AWS Services                                       │
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐               │
│  │   S3 Bucket     │  │  Secrets Mgr    │  │      ECR        │               │
│  │ (Remote State)  │  │ (ADO PAT)       │  │ (Agent Images)  │               │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Layer Dependencies

```
Base Layer (Independent)
├── EKS Cluster with Fargate
├── VPC and Networking  
├── IAM Roles and Policies
├── KMS Keys for Encryption
└── Security Groups

Middleware Layer (depends on Base)
├── KEDA Operator (autoscaling)
├── External Secrets Operator (secret management)
├── buildkitd Service (container builds)
├── Kubernetes Namespaces
└── ClusterSecretStore

Application Layer (depends on Base + Middleware)  
├── ECR Repositories
├── AWS Secrets Manager Secrets
├── IAM Execution Roles (IRSA)
├── Helm Chart Deployment
└── ADO Agent Pods with Autoscaling
```

## Layer Structure

> 📖 **Configuration Guides**:
> - [Fargate Profile Configuration](./docs/FARGATE_CONFIGURATION.md) - Comprehensive guide for configuring Fargate profiles
> - [EKS Addon Split Solution](./docs/EKS_ADDON_SPLIT_SOLUTION.md) - **CRITICAL**: Split VPC CNI from other addons to prevent CoreDNS degraded state
> - [EKS Addon Dependency Resolution](./docs/EKS_ADDON_DEPENDENCY_RESOLUTION.md) - Understanding VPC CNI and compute resource dependencies
> - [Addons and Compute Resources](./docs/ADDONS_AND_COMPUTE.md) - Addon independence and dependency patterns
> - [Region Configuration](./check-region-config.sh) - Script to validate AWS region consistency

### Directory Structure

```
infrastructure-layered/
├── deploy.sh                           # Orchestration script
├── .env.example                        # Environment variable template
├── README.md                          # This documentation
│
├── base/                              # Layer 1: Foundation
│   ├── main.tf                        # EKS cluster, VPC, IAM
│   ├── variables.tf                   # Configuration variables
│   ├── outputs.tf                     # Outputs for other layers
│   ├── terraform.tfvars.sample        # Sample configuration
│   └── README.md                      # Base layer documentation
│
├── middleware/                        # Layer 2: Cluster Operators
│   ├── main.tf                        # KEDA, ESO, buildkitd
│   ├── variables.tf                   # Configuration variables  
│   ├── outputs.tf                     # Outputs for app layer
│   ├── remote_state.tf                # Base layer dependencies
│   ├── terraform.tfvars.sample        # Sample configuration
│   └── README.md                      # Middleware layer docs
│
├── application/                       # Layer 3: Applications
│   ├── main.tf                        # ECR, secrets, agents
│   ├── variables.tf                   # Configuration variables
│   ├── outputs.tf                     # Operational outputs
│   ├── remote_state.tf                # Layer dependencies
│   ├── terraform.tfvars.sample        # Sample configuration
│   └── README.md                      # Application layer docs
│
└── helm/                              # Helm Charts
    └── ado-agent-cluster/             # ADO agent deployment
        ├── Chart.yaml                 # Chart metadata
        ├── values.yaml               # Default values
        ├── values.schema.json        # Value validation
        ├── README.md                 # Chart documentation
        └── templates/                # Kubernetes manifests
            ├── _helpers.tpl          # Template helpers
            ├── serviceaccount.yaml   # IRSA service accounts
            ├── deployment.yaml       # Agent deployments
            ├── scaledobject.yaml     # KEDA scaling config
            ├── trigger-authentication.yaml  # ADO API auth
            └── external-secret.yaml  # Secret management
```

### Layer Responsibilities

#### Base Layer
- **Purpose**: Foundational infrastructure that rarely changes
- **Components**: EKS cluster, VPC, subnets, NAT gateways, security groups, IAM roles, KMS keys
- **Dependencies**: None (self-contained)
- **Update Frequency**: Quarterly or less

#### Middleware Layer
- **Purpose**: Cluster operators and services that enable applications
- **Components**: KEDA, External Secrets Operator, buildkitd, namespaces, RBAC
- **Dependencies**: Base layer remote state
- **Update Frequency**: Monthly or when operators need updates

#### Application Layer
- **Purpose**: Application-specific resources and deployments
- **Components**: ECR repositories, secrets, IAM execution roles, Helm deployments
- **Dependencies**: Base + middleware layer remote state
- **Update Frequency**: Weekly or with application changes

## Prerequisites

### Required Tools

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Install Terraform >= 1.5
brew install terraform

# Install Helm >= 3.10  
brew install helm

# Install kubectl
brew install kubectl

# Verify installations
aws --version      # aws-cli/2.x.x or later
terraform version  # Terraform v1.5.0 or later  
helm version       # version.BuildInfo{Version:"v3.10.x" or later}
kubectl version --client  # Client Version: v1.28.x or later
```

### AWS Prerequisites

1. **AWS Account with appropriate permissions**
   ```bash
   # Configure AWS credentials
   aws configure
   
   # Verify access
   aws sts get-caller-identity
   ```

2. **S3 bucket for remote state** (create manually)
   ```bash
   # Create state bucket (choose a unique name)
   aws s3 mb s3://my-terraform-state-bucket --region us-east-1
   
   # Enable versioning (recommended)
   aws s3api put-bucket-versioning \
     --bucket my-terraform-state-bucket \
     --versioning-configuration Status=Enabled
   
   # Note: DynamoDB table is NOT required for state locking
   # Terraform 1.10+ supports native S3 state locking with use_lockfile=true
   ```

3. **Azure DevOps Prerequisites**
   - ADO organization with administrative access
   - Personal Access Token (PAT) with Agent Pools (Read & Manage) permissions
   - Agent pool(s) created in ADO (matching configuration)

### Required IAM Permissions

The deploying user/role needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "ec2:*",
        "iam:*",
        "kms:*",
        "s3:*",
        "secretsmanager:*",
        "ecr:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd platform-eks-cluster-for-ado-agents/infrastructure-layered
```

### 2. Set Environment Variables

```bash
# Option 1: Use the provided template
cp .env.example .env
# Edit .env with your values, then load it
source .env

# Option 2: Set variables manually
export TF_STATE_BUCKET='my-terraform-state-bucket'
export TF_VAR_ado_pat_value='your-personal-access-token'  # Optional
export AWS_REGION='us-west-2'  # Important: Must match your VPC region
```

> **Important Region Configuration:**
> - The `AWS_REGION` environment variable should match the region where your VPC and subnets exist
> - Your AWS CLI default region (`aws configure get region`) should also match
> - All three layers use the same region - mixing regions will cause VPC lookup failures
> - Set `AWS_REGION` before running any deployment commands

> **Note**: The `TF_STATE_BUCKET` environment variable is **required**. See `.env.example` for all configuration options.

### 3. Configure Base Layer

```bash
# Copy sample configuration
cp base/terraform.tfvars.sample base/terraform.tfvars

# Edit configuration (required fields)
vi base/terraform.tfvars
```

**Minimum required configuration:**
```hcl
# base/terraform.tfvars
cluster_name = "my-ado-agents"
aws_region   = "us-east-1"

# Remote state
remote_state_bucket = "my-terraform-state-bucket"
remote_state_region = "us-east-1"

# Networking (adjust as needed)
vpc_cidr = "10.0.0.0/16"
```

### 3. Configure Application Layer

```bash
# Copy sample configuration  
cp application/terraform.tfvars.sample application/terraform.tfvars

# Edit configuration (required fields)
vi application/terraform.tfvars
```

**Minimum required configuration:**
```hcl
# application/terraform.tfvars
remote_state_bucket = "my-terraform-state-bucket"  # Same as base
remote_state_region = "us-east-1"                 # Same as base

# ADO configuration (set via environment variables for security)
ado_org = "your-ado-organization"
ado_url = "https://dev.azure.com/your-ado-organization"

# Set PAT via environment variable
export TF_VAR_ado_pat_value="your-personal-access-token"
```

### 4. Deploy Everything

```bash
# Deploy all layers with interactive prompts
export TF_STATE_BUCKET='my-terraform-state-bucket'
./deploy.sh deploy

# Or deploy with auto-approval
export TF_STATE_BUCKET='my-terraform-state-bucket'
./deploy.sh --auto-approve deploy

# Or deploy specific layer only
export TF_STATE_BUCKET='my-terraform-state-bucket'
./deploy.sh --layer base deploy
```

### 5. Verify Deployment

```bash
# Check deployment status
./deploy.sh status

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name my-ado-agents

# Verify cluster access
kubectl cluster-info
kubectl get nodes

# Check ADO agents
kubectl get pods -n ado-agents
kubectl get scaledobjects -n ado-agents

# Check agent scaling (should show 0 replicas when no work queued)
kubectl describe scaledobject ado-agent -n ado-agents
```

## Detailed Deployment

### Step-by-Step Deployment

#### Step 1: Validate Configuration

```bash
# Validate all layers without deploying
./deploy.sh validate

# Check what would be deployed  
./deploy.sh plan
```

#### Step 2: Deploy Base Layer

```bash
# Deploy base infrastructure
./deploy.sh --layer base deploy

# Verify base layer
./deploy.sh --layer base status
kubectl cluster-info
```

#### Step 3: Deploy Middleware Layer  

```bash
# Deploy cluster operators
./deploy.sh --layer middleware deploy

# Verify middleware
kubectl get pods -n keda-system
kubectl get pods -n external-secrets-system
kubectl get pods -n buildkit
```

#### Step 4: Deploy Application Layer

```bash
# Deploy applications
./deploy.sh --layer application deploy

# Verify applications
kubectl get pods -n ado-agents
helm list -n ado-agents
```

### Deployment Options

#### Backend Configuration

```bash
# Use custom backend configuration file
./deploy.sh --backend-config backend.hcl deploy

# backend.hcl example:
bucket         = "my-terraform-state-bucket"
key           = "base/terraform.tfstate"  # Will be overridden per layer
region        = "us-east-1"
dynamodb_table = "terraform-state-lock"
encrypt       = true
```

#### Variables File

```bash
# Use custom variables file
./deploy.sh --var-file production.tfvars deploy

# Use different files per layer
./deploy.sh --layer base --var-file base-prod.tfvars deploy
./deploy.sh --layer application --var-file app-prod.tfvars deploy
```

#### Dry Run

```bash
# See what would be done without making changes
./deploy.sh --dry-run deploy
./deploy.sh --dry-run destroy
```

## Configuration

### Environment-Specific Configuration

#### Development Environment

```hcl
# base/terraform.tfvars (development)
cluster_name = "ado-agents-dev"
environment  = "development"

# Smaller, cheaper configuration
fargate_profiles = {
  default = {
    instance_types = ["t3.small", "t3.medium"]
    capacity_type  = "SPOT"  # Use Spot for cost savings
  }
}

# Development-friendly settings
enable_cluster_logging = true
cluster_log_retention_days = 7  # Shorter retention for dev
```

```hcl
# application/terraform.tfvars (development)
agent_pools = {
  ado-agent = {
    enabled              = true
    ado_pool_name       = "EKS-Dev-Agents"
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }   # Smaller for dev
      limits   = { cpu = "1000m", memory = "2Gi" }
    }
    autoscaling = {
      min_replicas        = 0
      max_replicas        = 3  # Lower max for dev
      target_queue_length = 1
    }
  }
}
```

#### Production Environment

```hcl
# base/terraform.tfvars (production)
cluster_name = "ado-agents-prod"
environment  = "production"

# Production-optimized configuration
fargate_profiles = {
  default = {
    instance_types = ["m5.large", "m5.xlarge"]
    capacity_type  = "ON_DEMAND"  # On-Demand for reliability
  }
  compute_optimized = {
    instance_types = ["c5.large", "c5.xlarge", "c5.2xlarge"]
    capacity_type  = "ON_DEMAND"
  }
}

# Production settings
enable_cluster_logging = true
cluster_log_retention_days = 30
cluster_encryption_enabled = true

# Enhanced monitoring
enable_prometheus_monitoring = true
enable_grafana_dashboards = true
```

```hcl
# application/terraform.tfvars (production)
agent_pools = {
  ado-agent = {
    enabled              = true
    ado_pool_name       = "EKS-Prod-Linux-Agents"
    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { cpu = "2000m", memory = "4Gi" }
    }
    autoscaling = {
      min_replicas        = 0
      max_replicas        = 20  # Higher scale for production
      target_queue_length = 1
    }
    # Production-specific settings
    tolerations = [
      {
        key      = "production"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }
    ]
  }
  ado-iac-agent = {
    enabled              = true
    ado_pool_name       = "EKS-Prod-IaC-Agents"
    resources = {
      requests = { cpu = "200m", memory = "512Mi" }
      limits   = { cpu = "4000m", memory = "8Gi" }
    }
    autoscaling = {
      min_replicas        = 0
      max_replicas        = 10
      target_queue_length = 1
    }
    # IaC-specific settings
    additional_env_vars = {
      TF_CLI_CONFIG_FILE = "/opt/terraform/.terraformrc"
      TERRAFORM_VERSION  = "1.5.7"
    }
  }
}
```

### Agent Pool Customization

#### Resource Profiles

```hcl
# Light workloads (testing, simple builds)
light_agent = {
  resources = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "1Gi" }
  }
  autoscaling = {
    min_replicas = 0
    max_replicas = 10
    target_queue_length = 2  # Allow queue buildup for light workloads
  }
}

# Standard workloads (typical CI/CD)
standard_agent = {
  resources = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "2000m", memory = "4Gi" }
  }
  autoscaling = {
    min_replicas = 0
    max_replicas = 15
    target_queue_length = 1
  }
}

# Heavy workloads (large builds, integration tests)
heavy_agent = {
  resources = {
    requests = { cpu = "500m", memory = "1Gi" }
    limits   = { cpu = "4000m", memory = "8Gi" }
  }
  autoscaling = {
    min_replicas = 0
    max_replicas = 5
    target_queue_length = 1
  }
}

# Infrastructure/Terraform workloads
iac_agent = {
  resources = {
    requests = { cpu = "200m", memory = "512Mi" }
    limits   = { cpu = "4000m", memory = "8Gi" }
  }
  additional_env_vars = {
    TF_CLI_CONFIG_FILE = "/opt/terraform/.terraformrc"
    AWS_DEFAULT_REGION = "us-east-1"
    TERRAFORM_VERSION  = "1.5.7"
  }
  # Additional volumes for Terraform cache
  volumes = [
    {
      name = "terraform-cache"
      type = "emptyDir"
      spec = { sizeLimit = "1Gi" }
    }
  ]
  volume_mounts = [
    {
      name      = "terraform-cache"
      mountPath = "/opt/terraform/.terraform"
      readOnly  = false
    }
  ]
}
```

#### Scheduling Configuration

```hcl
# Node affinity for specific instance types
compute_optimized_agent = {
  affinity = {
    nodeAffinity = {
      preferredDuringSchedulingIgnoredDuringExecution = [
        {
          weight = 100
          preference = {
            matchExpressions = [
              {
                key      = "node.kubernetes.io/instance-type"
                operator = "In"
                values   = ["c5.large", "c5.xlarge", "c5.2xlarge"]
              }
            ]
          }
        }
      ]
    }
  }
  tolerations = [
    {
      key      = "compute-optimized"
      operator = "Equal" 
      value    = "true"
      effect   = "NoSchedule"
    }
  ]
}

# Memory-optimized for specific workloads
memory_optimized_agent = {
  node_selector = {
    "workload-type" = "memory-intensive"
  }
  resources = {
    requests = { cpu = "200m", memory = "2Gi" }
    limits   = { cpu = "2000m", memory = "16Gi" }
  }
}
```

### Security Configuration

#### RBAC and Service Accounts

```hcl
# Custom IAM permissions for specific use cases
custom_ado_execution_roles = {
  ado-agent-s3 = {
    namespace            = "ado-agents"
    service_account_name = "ado-agent-s3"
    permissions = [
      {
        effect = "Allow"
        actions = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        resources = [
          "arn:aws:s3:::my-deployment-bucket",
          "arn:aws:s3:::my-deployment-bucket/*"
        ]
      }
    ]
  }
  ado-agent-rds = {
    namespace            = "ado-agents"
    service_account_name = "ado-agent-rds"
    permissions = [
      {
        effect = "Allow"
        actions = [
          "rds:DescribeDBInstances",
          "rds:CreateDBSnapshot"
        ]
        resources = ["*"]
        condition = {
          test     = "StringEquals"
          variable = "rds:db-tag/Environment"
          values   = ["development", "staging"]
        }
      }
    ]
  }
}
```

#### Pod Security Standards

```hcl
# Strict pod security context
strict_pod_security = {
  runAsNonRoot = true
  runAsUser    = 1001
  runAsGroup   = 1001
  fsGroup      = 1001
  seccompProfile = {
    type = "RuntimeDefault"
  }
}

# Restricted container security context  
restricted_container_security = {
  allowPrivilegeEscalation = false
  runAsNonRoot            = true
  runAsUser              = 1001
  readOnlyRootFilesystem = true  # Requires proper volume mounts
  capabilities = {
    drop = ["ALL"]
    add  = []  # No additional capabilities
  }
  seccompProfile = {
    type = "RuntimeDefault"
  }
}
```

## Operations

### Day-to-Day Operations

#### Monitoring Agent Status

```bash
# Check agent pod status
kubectl get pods -n ado-agents -o wide

# Check scaling status
kubectl get scaledobjects -n ado-agents -o yaml

# View agent logs
kubectl logs -n ado-agents -l app.kubernetes.io/name=ado-agent --tail=100

# Check resource utilization
kubectl top pods -n ado-agents

# Monitor autoscaling events
kubectl get events -n ado-agents --field-selector reason=ScaleUp
kubectl get events -n ado-agents --field-selector reason=ScaleDown
```

#### Secret Management

```bash
# View current ADO PAT secret (requires permissions)
aws secretsmanager get-secret-value \
  --secret-id ado-agent-pat \
  --query SecretString --output text | jq

# Rotate ADO PAT
aws secretsmanager update-secret \
  --secret-id ado-agent-pat \
  --secret-string '{
    "personalAccessToken": "NEW_PAT_HERE",
    "organization": "your-org", 
    "adourl": "https://dev.azure.com/your-org"
  }'

# Verify External Secrets sync (should happen within 5 minutes)
kubectl describe externalsecret -n ado-agents ado-pat
kubectl get secret -n ado-agents ado-secret -o yaml
```

#### Scaling Operations

```bash
# Manually scale agent pool (temporary)
kubectl scale deployment ado-agent -n ado-agents --replicas=5

# Update KEDA scaling parameters
kubectl patch scaledobject ado-agent -n ado-agents --type='merge' -p='{
  "spec": {
    "minReplicaCount": 1,
    "maxReplicaCount": 20
  }
}'

# Pause autoscaling (for maintenance)
kubectl patch scaledobject ado-agent -n ado-agents --type='merge' -p='{
  "metadata": {
    "annotations": {
      "autoscaling.keda.sh/paused": "true"
    }
  }
}'

# Resume autoscaling
kubectl patch scaledobject ado-agent -n ado-agents --type='merge' -p='{
  "metadata": {
    "annotations": {
      "autoscaling.keda.sh/paused": "false"  
    }
  }
}'
```

#### Image Management

```bash
# List ECR repositories
aws ecr describe-repositories --query 'repositories[].repositoryName'

# Build and push new agent image
docker build -t ado-agent:latest app/ado-agent/
docker tag ado-agent:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/ado-agent:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# Push image
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/ado-agent:latest

# Update Helm deployment to use new image
helm upgrade ado-agents helm/ado-agent-cluster -n ado-agents \
  --set agentPools.ado-agent.image.tag=latest \
  --set agentPools.ado-agent.image.repository=123456789012.dkr.ecr.us-east-1.amazonaws.com/ado-agent
```

### Maintenance Operations

#### Updating Infrastructure

```bash
# Update single layer
./deploy.sh --layer base plan      # Review changes
./deploy.sh --layer base deploy    # Apply changes

# Update all layers
./deploy.sh plan                   # Review all changes  
./deploy.sh deploy                # Apply all changes

# Update with custom variables
./deploy.sh --var-file production.tfvars deploy
```

#### Upgrading Cluster Operators

```bash
# Update KEDA version in middleware layer
vi middleware/terraform.tfvars
# Change keda_chart_version = "2.12.0" to newer version

./deploy.sh --layer middleware deploy

# Verify upgrade
kubectl get pods -n keda-system
kubectl describe deployment keda-operator -n keda-system
```

#### Backup and Restore

```bash
# Backup Kubernetes configuration
kubectl get all -n ado-agents -o yaml > ado-agents-backup.yaml
kubectl get configmaps -n ado-agents -o yaml >> ado-agents-backup.yaml  
kubectl get secrets -n ado-agents -o yaml >> ado-agents-backup.yaml

# Backup Terraform state (automatic with S3 backend)
aws s3 ls s3://my-terraform-state-bucket/ --recursive

# Restore from backup (if needed)
kubectl apply -f ado-agents-backup.yaml
```

### Troubleshooting Common Issues

#### Agents Not Scaling

```bash
# Check KEDA operator logs
kubectl logs -n keda-system deployment/keda-operator

# Check ScaledObject status
kubectl describe scaledobject ado-agent -n ado-agents

# Check TriggerAuthentication
kubectl describe triggerauthentication ado-trigger-auth -n ado-agents

# Verify ADO API connectivity
kubectl exec -it -n ado-agents deployment/ado-agent -- \
  curl -u ":$AZP_TOKEN" \
  "https://dev.azure.com/YOUR_ORG/_apis/distributedtask/pools/YOUR_POOL_ID/jobrequests"
```

#### Pods Stuck in Pending

```bash
# Check pod events
kubectl describe pod -n ado-agents -l app.kubernetes.io/name=ado-agent

# Check Fargate profiles
aws eks describe-fargate-profile \
  --cluster-name my-ado-agents \
  --fargate-profile-name default

# Check node capacity
kubectl describe nodes
kubectl get nodes -o wide
```

#### Secret Access Issues

```bash
# Check External Secrets Operator
kubectl logs -n external-secrets-system deployment/external-secrets

# Check ClusterSecretStore
kubectl describe clustersecretstore aws-secrets-manager

# Check ExternalSecret status
kubectl describe externalsecret -n ado-agents ado-pat

# Verify ESO service account permissions
kubectl describe serviceaccount -n external-secrets-system external-secrets
```

## Security

### Security Architecture

The infrastructure implements defense-in-depth security principles:

#### Network Security
- **Private subnets** for all worker nodes and Fargate pods
- **VPC endpoints** for AWS services (no internet routing for AWS API calls)
- **Security groups** with least-privilege access rules
- **Network policies** for pod-to-pod communication control

#### Identity and Access Management
- **IRSA (IAM Roles for Service Accounts)** for workload identity
- **Least privilege IAM policies** for each service
- **No long-term credentials** stored in containers
- **Service account token projection** with short TTL

#### Encryption
- **EKS cluster encryption** with customer-managed KMS keys
- **EBS volume encryption** for persistent storage
- **Secrets encryption at rest** in AWS Secrets Manager
- **TLS in transit** for all API communications

#### Container Security
- **Non-root container execution** (UID 1001)
- **Read-only root filesystem** where possible
- **Security contexts** with seccomp profiles
- **Capability dropping** to minimum required set
- **Container image scanning** with ECR

#### Secrets Management
- **External Secrets Operator** for dynamic secret injection
- **AWS Secrets Manager** for centralized secret storage
- **No secrets in environment variables** or configuration files
- **Automatic secret rotation** capability

### Security Best Practices

#### Regular Security Updates

```bash
# Update base AMIs (Fargate handles this automatically)
# Update container images regularly
docker pull mcr.microsoft.com/azure-pipelines/vsts-agent:ubuntu-20.04

# Scan images for vulnerabilities  
aws ecr start-image-scan --repository-name ado-agent --image-id imageTag=latest
aws ecr describe-image-scan-findings --repository-name ado-agent --image-id imageTag=latest
```

#### Access Control

```bash
# Review IAM roles and policies
aws iam get-role --role-name eks-cluster-ado-agent-ado-agent-role
aws iam list-attached-role-policies --role-name eks-cluster-ado-agent-ado-agent-role

# Review Kubernetes RBAC
kubectl get rolebindings -n ado-agents -o yaml
kubectl get clusterrolebindings -o yaml | grep -A5 -B5 ado-agent

# Audit cluster access
kubectl auth can-i --list --as=system:serviceaccount:ado-agents:ado-agent
```

#### Security Monitoring

```bash
# Check AWS Config rules (if enabled)
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name eks-cluster-supported-version

# Review CloudTrail logs for EKS API calls
aws logs filter-log-events \
  --log-group-name CloudTrail/EKSClusterActivity \
  --start-time $(date -d '1 hour ago' +%s)000

# Monitor failed authentication attempts
kubectl get events --all-namespaces | grep -i forbidden
```

### Compliance Considerations

#### SOC 2 / ISO 27001
- Audit logging enabled for all API calls
- Encryption at rest and in transit
- Access control with principle of least privilege
- Regular security assessments and updates

#### HIPAA / PCI-DSS
- Network isolation and segmentation
- Encryption of sensitive data
- Access logging and monitoring
- Secure credential management

#### Documentation for Auditors
- Infrastructure as Code provides audit trail
- All changes tracked in version control
- Automated deployment reduces human error
- Security controls documented in this guide

## Monitoring

### Observability Stack

#### CloudWatch Integration

```bash
# View EKS control plane logs
aws logs describe-log-groups --log-group-name-prefix /aws/eks/

# Query recent authentication failures
aws logs filter-log-events \
  --log-group-name /aws/eks/my-ado-agents/cluster \
  --filter-pattern "{ $.verb = \"create\" && $.objectRef.resource = \"tokenreviews\" && $.responseStatus.code != 201 }" \
  --start-time $(date -d '1 hour ago' +%s)000

# Monitor Fargate pod metrics
aws logs filter-log-events \
  --log-group-name /aws/fargate/my-ado-agents \
  --filter-pattern '[timestamp, request_id, "ERROR"]' \
  --start-time $(date -d '24 hours ago' +%s)000
```

#### Prometheus Metrics

```bash
# Access KEDA metrics (if port-forwarded)
kubectl port-forward -n keda-system service/keda-operator-metrics-apiserver 8080:8080 &
curl http://localhost:8080/metrics | grep keda_scaled_object

# View built-in Kubernetes metrics
kubectl top nodes
kubectl top pods -n ado-agents --sort-by=cpu
kubectl top pods -n ado-agents --sort-by=memory
```

#### Application Metrics

Key metrics to monitor:

- **Agent Pool Queue Length**: Number of pending jobs in ADO
- **Agent Scaling Events**: Scale up/down frequency and timing  
- **Pod Resource Utilization**: CPU, memory, disk usage
- **Build Success Rate**: Percentage of successful pipeline executions
- **Agent Startup Time**: Time from pod creation to agent registration
- **Cost Metrics**: Fargate costs, ECR storage costs

### Alerting Setup

#### CloudWatch Alarms

```bash
# Create alarm for high queue length
aws cloudwatch put-metric-alarm \
  --alarm-name "ADO-Agent-Queue-High" \
  --alarm-description "ADO agent queue length is high" \
  --metric-name "QueueLength" \
  --namespace "KEDA/ScaledObject" \
  --statistic Average \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2

# Create alarm for pod failures
aws cloudwatch put-metric-alarm \
  --alarm-name "ADO-Agent-Pod-Failures" \
  --alarm-description "ADO agent pods are failing" \
  --metric-name "PodRestarts" \
  --namespace "Kubernetes" \
  --statistic Sum \
  --period 300 \
  --threshold 3 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1
```

#### Slack/Teams Integration

Example webhook integration for build notifications:

```bash
# Monitor for scaling events
kubectl get events -n ado-agents --watch | while read line; do
  if echo "$line" | grep -q "Scaled.*up\|Scaled.*down"; then
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"ADO Agent Scaling: $line\"}" \
      YOUR_WEBHOOK_URL
  fi
done
```

### Dashboards

#### Grafana Dashboard Components

1. **Cluster Overview**
   - Node count and capacity
   - Pod distribution across nodes
   - Resource utilization trends

2. **Agent Metrics**
   - Queue length over time
   - Agent count per pool  
   - Scaling events timeline
   - Success/failure rates

3. **Cost Tracking**
   - Fargate compute costs
   - ECR storage costs
   - Data transfer costs
   - Cost per build execution

4. **Security Metrics**
   - Failed authentication attempts
   - Privilege escalation attempts
   - Unauthorized API calls

## Cost Optimization

### Cost Analysis

#### Fargate Pricing Model

Fargate charges for CPU and memory resources:
- **CPU**: $0.04048 per vCPU per hour
- **Memory**: $0.004445 per GB per hour
- **Minimum charge**: 1 minute
- **Scale to zero**: No cost when no agents running

#### Cost Comparison: Fargate vs EC2

```bash
# Example cost calculation for typical usage
# Assumptions: 
# - 8 hours/day active building
# - 2 parallel agents average
# - ado-agent config: 2 vCPU, 4 GB RAM

# Fargate costs (per day):
CPU_COST_PER_HOUR=0.08096    # 2 vCPU * $0.04048
MEMORY_COST_PER_HOUR=0.01778  # 4 GB * $0.004445
TOTAL_PER_HOUR=0.09874
HOURS_PER_DAY=8
AGENTS=2

DAILY_COST=$(echo "$TOTAL_PER_HOUR * $HOURS_PER_DAY * $AGENTS" | bc -l)
echo "Daily Fargate cost: \$$(printf '%.2f' $DAILY_COST)"

# Monthly cost (22 working days)
MONTHLY_COST=$(echo "$DAILY_COST * 22" | bc -l)  
echo "Monthly Fargate cost: \$$(printf '%.2f' $MONTHLY_COST)"
```

#### Cost Optimization Strategies

1. **Right-size Resources**
   ```hcl
   # Use smaller requests for CPU-light workloads
   resources = {
     requests = { cpu = "50m", memory = "128Mi" }   # Very light
     limits   = { cpu = "500m", memory = "1Gi" }    # Allow bursting
   }
   ```

2. **Optimize Scaling Parameters**
   ```hcl
   # Allow slight queue buildup to reduce scaling frequency
   autoscaling = {
     target_queue_length = 2  # Instead of 1
     scale_down_delay    = "300s"  # Wait before scaling down
   }
   ```

3. **Use Spot Instances** (when available for Fargate)
   ```hcl
   fargate_profiles = {
     spot = {
       capacity_type = "SPOT"
       instance_types = ["m5.large", "m5.xlarge"]
     }
   }
   ```

### Cost Monitoring

#### CloudWatch Cost Metrics

```bash
# Create custom metrics for cost tracking
aws cloudwatch put-metric-data \
  --namespace "ADO/CostTracking" \
  --metric-data MetricName=FargateHours,Value=8.5,Unit=Count,Timestamp=$(date -u +%s)

# Query cost data
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Container Service for Kubernetes"]}}'
```

#### Cost Alerts

```bash
# Create budget alert for EKS costs
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName": "EKS-ADO-Agents-Monthly",
    "BudgetLimit": {
      "Amount": "500",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "Service": ["Amazon Elastic Container Service for Kubernetes"]
    }
  }'
```

## Migration Guide

### From Monolithic to Layered Architecture

#### Pre-Migration Checklist

1. **Backup Current State**
   ```bash
   # Backup existing Terraform state
   terraform state pull > backup-terraform.tfstate
   
   # Backup Kubernetes resources
   kubectl get all --all-namespaces -o yaml > backup-k8s.yaml
   
   # Document current configuration
   terraform show > current-infrastructure.txt
   ```

2. **Assess Current Resources**
   ```bash
   # List current resources
   terraform state list
   
   # Identify dependencies
   terraform show | grep -E "depends_on|data\."
   
   # Check for hardcoded values
   grep -r "arn:aws:" *.tf
   ```

#### Migration Strategy

##### Option 1: Blue-Green Migration (Recommended)

```bash
# 1. Deploy new layered infrastructure alongside existing
./deploy.sh --var-file migration.tfvars deploy

# 2. Test new infrastructure thoroughly
./test-migration.sh

# 3. Update Azure DevOps agent pools to point to new agents
# 4. Monitor pipeline executions
# 5. Destroy old infrastructure once validated
```

##### Option 2: In-Place Migration

```bash
# 1. Export current resources to new structure
./migrate-resources.sh export

# 2. Import resources into new layers
./migrate-resources.sh import

# 3. Validate imported state
./deploy.sh validate

# 4. Apply any necessary changes
./deploy.sh plan
./deploy.sh deploy
```

#### Migration Scripts

Create helper scripts for migration:

```bash
#!/bin/bash
# migrate-resources.sh

export_resources() {
    echo "Exporting current EKS cluster..."
    terraform state show aws_eks_cluster.main > exports/eks-cluster.tf
    
    echo "Exporting IAM roles..."
    terraform state show aws_iam_role.cluster > exports/iam-roles.tf
    
    echo "Exporting VPC resources..."
    terraform state show aws_vpc.main > exports/vpc.tf
}

import_resources() {
    echo "Importing to base layer..."
    cd infrastructure-layered/base
    terraform import aws_eks_cluster.main my-cluster-name
    
    echo "Importing to middleware layer..."
    cd ../middleware
    terraform import helm_release.keda keda/keda
    
    echo "Importing to application layer..."
    cd ../application
    terraform import aws_secretsmanager_secret.ado_pat ado-agent-pat
}

case "$1" in
    export) export_resources ;;
    import) import_resources ;;
    *) echo "Usage: $0 {export|import}" ;;
esac
```

#### Post-Migration Validation

```bash
# Validate all layers are working
./deploy.sh status

# Test agent functionality
kubectl run test-job --image=busybox --rm -it -- /bin/sh -c "echo 'Test completed'"

# Verify autoscaling
kubectl describe scaledobject -n ado-agents

# Check cost impact
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost
```

### Rollback Procedures

If migration fails, use these rollback steps:

```bash
# 1. Restore from backup state
terraform state push backup-terraform.tfstate

# 2. Restore Kubernetes resources
kubectl apply -f backup-k8s.yaml

# 3. Verify rollback
terraform plan  # Should show no changes
kubectl get all --all-namespaces
```

## FAQ

### General Questions

#### Q: Why use a layered architecture instead of monolithic?

**A:** Layered architecture provides several benefits:
- **Independent lifecycle management**: Update KEDA without touching the EKS cluster
- **Reduced blast radius**: Issues in one layer don't affect others
- **Better testing**: Each layer can be validated independently
- **Team autonomy**: Different teams can own different layers
- **Easier troubleshooting**: Problems isolated to specific layers

#### Q: Can I deploy only specific layers?

**A:** Yes, you can deploy individual layers:
```bash
./deploy.sh --layer base deploy        # Deploy only base layer
./deploy.sh --layer middleware deploy  # Deploy only middleware layer  
./deploy.sh --layer application deploy # Deploy only application layer
```

However, respect dependencies: middleware needs base, application needs base + middleware.

#### Q: How do I customize agent configurations?

**A:** Modify the `agent_pools` variable in `application/terraform.tfvars`:
```hcl
agent_pools = {
  my-custom-agent = {
    enabled              = true
    ado_pool_name       = "My-Custom-Pool"
    resources = {
      requests = { cpu = "200m", memory = "512Mi" }
      limits   = { cpu = "4000m", memory = "8Gi" }
    }
    autoscaling = {
      min_replicas        = 0
      max_replicas        = 10
      target_queue_length = 1
    }
    additional_env_vars = {
      CUSTOM_VAR = "custom_value"
    }
  }
}
```

### Technical Questions

#### Q: How does the autoscaling work?

**A:** KEDA monitors Azure DevOps job queues:
1. KEDA queries ADO API every 30 seconds for queue length
2. If queue length > target (default: 1), KEDA scales up pods
3. If queue empty for 5 minutes, KEDA scales down to zero
4. Scaling is per agent pool (can scale different pools independently)

#### Q: What happens if Azure DevOps is unreachable?

**A:** KEDA has built-in resilience:
- Retries failed API calls with exponential backoff
- Maintains last known good state during outages
- Falls back to minimum replica count if API unavailable > 10 minutes
- Logs errors to help diagnose connectivity issues

#### Q: Can I use custom container images?

**A:** Yes, in two ways:

1. **Use ECR repositories** (recommended):
   ```hcl
   ecr_repositories = {
     my-custom-agent = {
       image_tag_mutability = "MUTABLE"
       # ... configuration
     }
   }
   
   agent_pools = {
     my-agent = {
       ecr_repository_key = "my-custom-agent"
       image_tag         = "v1.0.0"
       # ...
     }
   }
   ```

2. **Use external repositories**:
   ```hcl
   agent_pools = {
     my-agent = {
       image_repository = "my-registry.com/my-agent"
       image_tag       = "latest"
       # ...
     }
   }
   ```

#### Q: How do I handle secrets other than ADO PAT?

**A:** Add additional secrets to AWS Secrets Manager and configure External Secrets:

1. Create secret in AWS:
   ```bash
   aws secretsmanager create-secret \
     --name my-custom-secret \
     --secret-string '{"key":"value"}'
   ```

2. Add to Helm values:
   ```yaml
   externalSecrets:
     secrets:
       my-custom-secret:
         aws:
           secretName: my-custom-secret
           region: us-east-1
         k8s:
           secretName: my-k8s-secret
           type: Opaque
   ```

### Operational Questions

#### Q: How do I update agent images?

**A:** Build, push, and update:
```bash
# Build new image
docker build -t my-agent:v2.0.0 .

# Push to ECR
docker tag my-agent:v2.0.0 123456789012.dkr.ecr.us-east-1.amazonaws.com/ado-agent:v2.0.0
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/ado-agent:v2.0.0

# Update Helm release
helm upgrade ado-agents helm/ado-agent-cluster -n ado-agents \
  --set agentPools.ado-agent.image.tag=v2.0.0
```

#### Q: How do I scale agents manually?

**A:** Temporarily override KEDA:
```bash
# Scale to specific replica count
kubectl scale deployment ado-agent -n ado-agents --replicas=5

# Disable autoscaling (maintenance mode)
kubectl annotate scaledobject ado-agent -n ado-agents autoscaling.keda.sh/paused=true

# Re-enable autoscaling
kubectl annotate scaledobject ado-agent -n ado-agents autoscaling.keda.sh/paused-
```

#### Q: What's the disaster recovery procedure?

**A:** Recovery steps depend on failure scope:

1. **Single pod failure**: Kubernetes automatically restarts
2. **Agent pool failure**: Delete deployment, Helm will recreate
3. **Namespace corruption**: Redeploy application layer
4. **Cluster failure**: Redeploy middleware + application layers
5. **Complete failure**: Redeploy all layers from state backup

```bash
# Complete recovery example
./deploy.sh destroy                    # Clean slate
./deploy.sh --auto-approve deploy      # Rebuild everything
```

### Security Questions

#### Q: How are ADO credentials secured?

**A:** Multi-layer security:
1. **AWS Secrets Manager**: Encrypted at rest with KMS
2. **External Secrets Operator**: Dynamic injection, no persistent storage
3. **Kubernetes secrets**: Encrypted at rest, limited RBAC access
4. **Environment variables**: Injected at runtime, not in container image

#### Q: What IAM permissions do agents have?

**A:** Minimal permissions via IRSA:
- **Basic agents**: ECR pull only
- **IaC agents**: ECR pull/push, S3 state access, limited cross-account assume role
- **Custom roles**: Defined per use case with principle of least privilege

#### Q: Is network traffic encrypted?

**A:** Yes, at multiple levels:
- **EKS API**: TLS 1.2+ 
- **ADO API calls**: HTTPS only
- **AWS API calls**: TLS via VPC endpoints
- **Inter-pod**: Can enable with network policies + service mesh

### Cost Questions

#### Q: What are typical monthly costs?

**A:** Costs vary by usage pattern. Example for moderate usage:
- **Base infrastructure**: $50-100/month (EKS control plane, NAT gateway, etc.)
- **Fargate compute**: $100-500/month (depends on build frequency and duration)
- **Storage/networking**: $20-50/month (ECR, data transfer, etc.)

Total: $170-650/month for typical small to medium team usage.

#### Q: How can I reduce costs?

**A:** Cost optimization strategies:
1. **Right-size resources**: Use smaller CPU/memory requests
2. **Optimize scaling**: Allow slight queue buildup to reduce churn
3. **Use Spot instances**: If available in your region
4. **Clean up old images**: ECR lifecycle policies remove unused images
5. **Monitor usage**: Set up billing alerts and regular cost reviews

#### Q: Do I pay when agents are idle?

**A:** No! That's the beauty of Fargate + KEDA:
- Agents scale to zero when no builds queued
- You only pay for compute time when agents are actually running
- No idle EC2 instances consuming resources

---

## Support and Contributing

### Getting Help

1. **Documentation**: Start with layer-specific README files
2. **Issues**: Check existing GitHub issues or create new ones
3. **Discussions**: Use GitHub Discussions for questions and ideas
4. **Enterprise Support**: Contact your platform team

### Contributing

1. **Fork the repository**
2. **Create feature branch**: `git checkout -b feature/my-improvement`
3. **Make changes and test**: `./deploy.sh validate`
4. **Update documentation**: Keep README files current
5. **Submit pull request**: Include testing results

### Reporting Issues

When reporting issues, include:
- Layer(s) affected
- Error messages and logs
- Configuration (sanitized)
- Steps to reproduce
- Expected vs actual behavior

### Roadmap

Future enhancements being considered:
- Multi-region deployment support
- Windows agent support
- GPU-enabled agent pools  
- Advanced security scanning integration
- Cost optimization recommendations
- Disaster recovery automation

---

*This documentation is maintained as part of the infrastructure code. Please keep it updated when making changes to the architecture or procedures.*