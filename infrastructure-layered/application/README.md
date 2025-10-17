# Application Layer - ADO Agents and Application Resources

This layer deploys application-specific resources for Azure DevOps (ADO) agents running on Amazon EKS. It includes ECR repositories for container images, AWS Secrets Manager for secure credential storage, IAM roles for agent execution, and Helm chart deployment for the agents themselves.

## Overview

The application layer is the third and final layer in the infrastructure stack:
- **Base Layer**: Core EKS cluster, networking, and foundational resources
- **Middleware Layer**: KEDA, External Secrets Operator, buildkitd, and cluster operators
- **Application Layer**: ECR repositories, secrets, IAM roles, and ADO agent deployments ← You are here

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                            Application Layer                                        │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                   │
│  │   ECR Repos     │  │  ADO Secrets    │  │   IAM Roles     │                   │
│  │                 │  │                 │  │   (IRSA)        │                   │
│  │ ado-agent       │  │ PersonalAccess  │  │                 │                   │
│  │ ado-agent-iac   │  │ Token           │  │ ado-agent       │                   │
│  └─────────────────┘  └─────────────────┘  │ ado-agent-iac   │                   │
│                                             └─────────────────┘                   │
│                                                                                     │
│  ┌───────────────────────────────────────────────────────────────────────────────┐ │
│  │                        Helm Chart Deployment                                 │ │
│  │                                                                               │ │
│  │  Agent Pools:                                                                │ │
│  │  • EKS-Linux-Agents (general workloads)                                     │ │
│  │  • EKS-IaC-Agents (infrastructure/Terraform)                               │ │
│  │                                                                               │ │
│  │  Features:                                                                    │ │
│  │  • KEDA-based autoscaling (0-N based on queue length)                      │ │
│  │  • External Secrets integration for secure credential access                │ │
│  │  • Fargate-optimized scheduling                                             │ │
│  │  • Multi-agent-pool support with different resource profiles                │ │
│  └───────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Resources Created

### ECR Repositories
- **ado-agent**: Repository for general-purpose ADO agent images
- **ado-agent-iac**: Repository for infrastructure/Terraform-focused agent images
- Includes lifecycle policies for image cleanup
- KMS encryption using cluster key
- Vulnerability scanning enabled

### AWS Secrets Manager
- **ADO PAT Secret**: Stores Personal Access Token, organization, and URL
- KMS encrypted with cluster key
- Configurable recovery window (default: 7 days)
- Integrated with External Secrets Operator

### IAM Roles (IRSA)
- **ado-agent**: Basic ECR pull permissions
- **ado-agent-iac**: Extended permissions for Terraform operations
  - ECR push/pull
  - S3 state bucket access
  - DynamoDB state locking
  - Cross-account role assumption

### Helm Deployment
- **ado-agents**: Multi-pool ADO agent deployment
- KEDA ScaledObjects for each pool
- TriggerAuthentication for ADO API integration
- ExternalSecrets for credential management
- ServiceAccounts with IRSA annotations

## Dependencies

This layer depends on both base and middleware layers:

```
Base Layer (Remote State)
├── cluster_endpoint
├── cluster_certificate_authority_data
├── cluster_name
├── cluster_oidc_issuer_url
├── oidc_provider_arn
├── fargate_role_name
├── kms_key_arn
└── common_tags

Middleware Layer (Remote State)
├── ado_agents_namespace
├── ado_secret_name
├── cluster_secret_store_name
├── eso_role_name
├── buildkitd_enabled
└── buildkitd_service_endpoint
```

## Configuration

### Required Variables

```hcl
# Remote state configuration
remote_state_bucket = "my-terraform-state-bucket"
remote_state_region = "us-east-1"

# ADO configuration
ado_pat_value = "your-ado-personal-access-token"  # SENSITIVE
ado_org       = "your-ado-organization"
ado_url       = "https://dev.azure.com/your-org"
```

### Optional Customization

```hcl
# ECR repositories (optional - will use public images if not specified)
ecr_repositories = {
  ado-agent = {
    image_tag_mutability = "MUTABLE"
    # ... additional configuration
  }
}

# Agent pool customization
agent_pools = {
  ado-agent = {
    enabled              = true
    ado_pool_name       = "EKS-Linux-Agents"
    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { cpu = "2000m", memory = "4Gi" }
    }
    autoscaling = {
      min_replicas        = 0
      max_replicas        = 10
      target_queue_length = 1
    }
  }
}

# IAM permissions customization
ado_execution_roles = {
  ado-agent = {
    namespace            = "ado-agents"
    service_account_name = "ado-agent"
    permissions = [
      # Custom IAM permissions
    ]
  }
}
```

## Deployment

### Prerequisites

1. Base layer deployed and healthy
2. Middleware layer deployed and healthy
3. S3 bucket for remote state exists
4. Azure DevOps organization and PAT available

### Step 1: Configure Variables

Copy the sample configuration:
```bash
cp terraform.tfvars.sample terraform.tfvars
```

Edit `terraform.tfvars` with your configuration:
```bash
# Required configuration
remote_state_bucket = "your-terraform-state-bucket"
remote_state_region = "us-east-1"
ado_org            = "your-ado-org"
ado_url            = "https://dev.azure.com/your-ado-org"

# Set PAT via environment variable (recommended)
export TF_VAR_ado_pat_value="your-personal-access-token"
```

### Step 2: Set Environment Variable

```bash
export TF_STATE_BUCKET='your-terraform-state-bucket'
```

### Step 3: Deploy Using Orchestration Script (Recommended)

```bash
# From infrastructure-layered/ directory
cd ..
./deploy.sh --layer application deploy
```

Or deploy manually with Terraform:

```bash
# The orchestration script handles bucket substitution automatically
# Manual deployment requires sed substitution first
terraform init
terraform plan
terraform apply
```

> **Note**: The orchestration script (`../deploy.sh`) handles S3 bucket name substitution automatically. If deploying manually, ensure the backend configuration in `main.tf` has the correct bucket name.

### Step 4: Verify Deployment

```bash
# Check Helm release status
helm status ado-agents -n ado-agents

# Check agent pods
kubectl get pods -n ado-agents -l app.kubernetes.io/name=ado-agent

# Check KEDA scaling objects
kubectl get scaledobjects -n ado-agents

# Check External Secrets
kubectl get externalsecrets -n ado-agents
```

## Operations

### Scaling Configuration

KEDA automatically scales agents based on Azure DevOps pipeline queue length:

```yaml
# Check current scaling status
kubectl get scaledobjects -n ado-agents -o wide

# View scaling events
kubectl describe scaledobject ado-agent -n ado-agents
```

### Secret Management

```bash
# View secret in AWS (requires appropriate permissions)
aws secretsmanager get-secret-value \
  --secret-id ado-agent-pat \
  --query SecretString --output text

# Update ADO PAT
aws secretsmanager update-secret \
  --secret-id ado-agent-pat \
  --secret-string '{"personalAccessToken":"new-pat","organization":"your-org","adourl":"https://dev.azure.com/your-org"}'

# External Secrets will automatically sync the update within 5 minutes
```

### Image Management

```bash
# List ECR repositories
aws ecr describe-repositories --query 'repositories[].repositoryName'

# Push new agent image
docker tag your-ado-agent:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/ado-agent:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/ado-agent:latest

# Update Helm values to use new image
helm upgrade ado-agents ../helm/ado-agent-cluster -n ado-agents \
  --set agentPools.ado-agent.image.tag=latest
```

### Troubleshooting

#### Agent Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n ado-agents -l app.kubernetes.io/name=ado-agent

# Check service account annotations
kubectl describe serviceaccount -n ado-agents ado-agent

# Verify IRSA role trust policy
aws iam get-role --role-name eks-cluster-ado-agent-ado-agent-role
```

#### Scaling Issues

```bash
# Check KEDA operator logs
kubectl logs -n keda-system deployment/keda-operator

# Check TriggerAuthentication
kubectl describe triggerauthentication -n ado-agents

# Verify ADO API connectivity
kubectl exec -it -n ado-agents deployment/ado-agent -- \
  curl -u ":$AZP_TOKEN" \
  "https://dev.azure.com/your-org/_apis/distributedtask/pools/YOUR_POOL_ID/jobrequests"
```

#### Secret Access Issues

```bash
# Check External Secrets Operator logs
kubectl logs -n external-secrets-system deployment/external-secrets

# Check ClusterSecretStore status
kubectl describe clustersecretstore aws-secrets-manager

# Verify IAM permissions for ESO
kubectl describe serviceaccount -n external-secrets-system external-secrets
```

## Security Considerations

### IAM Permissions
- Agent roles follow principle of least privilege
- Terraform execution role has restricted resource patterns
- ECR permissions are scoped to specific repositories

### Container Security
- Non-root user execution (UID 1001)
- seccomp runtime/default profile
- Capabilities dropped to minimum required
- Network policies can be implemented via middleware layer

### Secret Management
- ADO PAT stored in AWS Secrets Manager with KMS encryption
- Automatic rotation support via External Secrets Operator
- No secrets in environment variables or config files

## Monitoring and Observability

### CloudWatch Integration
- EKS control plane logs: `/aws/eks/CLUSTER_NAME/cluster`
- Fargate pod logs: `/aws/fargate/CLUSTER_NAME`

### Prometheus Metrics
- KEDA metrics: `keda-operator-metrics.keda-system:8080/metrics`
- Agent pool scaling metrics
- Queue length and scaling decisions

### ADO Integration
- Agent pool status visible in Azure DevOps
- Pipeline execution logs and artifacts
- Build/deployment success rates

## Cost Optimization

### Fargate Pricing
- Agents scale to zero when no work is queued
- Pay-per-pod pricing model optimizes costs
- Resource requests tuned for typical workloads

### ECR Lifecycle Policies
- Automatic cleanup of old development images
- Production image retention policies
- Untagged image cleanup after 1 day

### Resource Right-Sizing
- Different resource profiles for different agent types
- Monitoring and adjustment recommendations in outputs

## Cleanup

To remove the application layer:

```bash
# Remove Helm deployment first
helm uninstall ado-agents -n ado-agents

# Destroy Terraform resources
terraform destroy

# Clean up ECR repositories (if needed)
aws ecr delete-repository --repository-name ado-agent --force
aws ecr delete-repository --repository-name ado-agent-iac --force
```

## Integration with CI/CD

### Azure DevOps Pipeline Example

```yaml
# azure-pipelines.yml
pool:
  name: EKS-Linux-Agents  # Matches ado_pool_name

steps:
- task: Docker@2
  displayName: 'Build and Push to ECR'
  inputs:
    containerRegistry: 'AWS-ECR-Connection'
    repository: 'ado-agent'
    command: 'buildAndPush'
    Dockerfile: 'app/ado-agent/Dockerfile'
    tags: |
      $(Build.BuildNumber)
      latest
```

### Terraform Pipeline (IaC Agents)

```yaml
# infrastructure-pipeline.yml
pool:
  name: EKS-IaC-Agents  # Uses IaC-specific agent pool

steps:
- task: TerraformInstaller@0
  inputs:
    terraformVersion: 'latest'

- task: TerraformTaskV4@4
  inputs:
    provider: 'aws'
    command: 'init'
    workingDirectory: 'infrastructure-layered/application'
    
- task: TerraformTaskV4@4
  inputs:
    provider: 'aws'
    command: 'plan'
    workingDirectory: 'infrastructure-layered/application'
```

## Outputs

This layer provides comprehensive outputs for operational use:

- **ECR Repository URLs**: For CI/CD integration
- **IAM Role ARNs**: For cross-account access or external integrations
- **Helm Release Information**: For deployment status and management
- **Operational Commands**: Ready-to-use kubectl, helm, and AWS CLI commands
- **Monitoring Endpoints**: CloudWatch log groups and Prometheus metrics

## Next Steps

After successful deployment:

1. **Configure Azure DevOps**: Create agent pools matching the deployed configuration
2. **Set up Pipelines**: Use the deployed agents in your Azure DevOps pipelines
3. **Monitor Performance**: Use CloudWatch and Prometheus metrics for optimization
4. **Iterate and Improve**: Adjust resource allocations and scaling parameters based on usage patterns