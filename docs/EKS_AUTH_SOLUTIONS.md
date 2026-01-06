# EKS Cluster Authentication Dependency Solutions

This document explains the EKS authentication dependency issue you're experiencing and provides two solutions.

## Problem Description

When deploying EKS clusters with Terraform, there's a common circular dependency issue:

1. The Kubernetes provider needs cluster information to authenticate
2. Kubernetes resources (like aws-auth ConfigMap) need the provider to be configured
3. But the provider configuration depends on the cluster existing first

The error you're seeing:
```
Error: reading EKS Cluster (ado-agent-cluster): couldn't find resource
Error: Get "http://localhost/api/v1/namespaces/kube-system/configmaps/aws-auth": dial tcp [::1]:80: connect: connection refused
```

This happens because Terraform tries to read the cluster and ConfigMap during the plan phase, before they exist.

## Solution 1: Single Terraform State with Staged Deployment (Recommended)

### How it works:
- Uses a variable `enable_kube_auth_management` to control aws-auth management
- First deployment creates cluster without managing aws-auth
- Second deployment enables aws-auth management

### Implementation:
1. **Updated Configuration**: The `kube_auth.tf` file now includes:
   - Conditional data sources with `count`
   - Proper `depends_on` relationships
   - Two different ConfigMap resources for different stages

2. **Deployment Process**:
   ```bash
   # Stage 1: Create cluster
   terraform apply -var="enable_kube_auth_management=false"
   
   # Stage 2: Configure authentication
   terraform apply -var="enable_kube_auth_management=true"
   ```

3. **Automated Script**: Use `./deploy.sh` for automated two-stage deployment

### Pros:
- Single Terraform state
- All resources managed together
- Easier to maintain and understand dependencies
- Good for development environments

### Cons:
- Requires two-stage deployment
- More complex initial setup

## Solution 2: Separate Terraform States

### Implementation:

Create a separate directory for cluster authentication:

```bash
mkdir infrastructure/cluster-auth
```

Move authentication-related resources to the separate state:

```hcl
# infrastructure/cluster-auth/main.tf
data "terraform_remote_state" "cluster" {
  backend = "s3" # or your backend
  config = {
    bucket = "your-terraform-state-bucket"
    key    = "eks-cluster/terraform.tfstate"
    region = "your-region"
  }
}

data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

# ... rest of your auth configuration
```

### Deployment Process:
```bash
# Deploy cluster first
cd infrastructure
terraform apply

# Deploy authentication
cd cluster-auth
terraform apply
```

### Pros:
- Clear separation of concerns
- No circular dependencies
- Can deploy cluster without authentication
- Good for production environments

### Cons:
- Multiple Terraform states to manage
- More complex CI/CD pipeline
- State dependencies to maintain

## Recommendation

For your use case, I recommend **Solution 1** (Single State with Staged Deployment) because:

1. **Simplicity**: Everything is in one place
2. **Development-friendly**: Easier to iterate and debug
3. **Automated process**: The `deploy.sh` script handles the staging automatically
4. **State management**: Only one Terraform state to manage

## Migration Steps

Your current configuration has been updated to support the staged approach. To migrate:

1. **First-time deployment**:
   ```bash
   cd infrastructure
   ./deploy.sh
   ```

2. **Subsequent updates**:
   ```bash
   terraform plan -var="enable_kube_auth_management=true"
   terraform apply
   ```

3. **Alternative manual approach**:
   ```bash
   # Create cluster without auth management
   terraform apply -var="enable_kube_auth_management=false"
   
   # Enable auth management
   terraform apply -var="enable_kube_auth_management=true"
   ```

## Variables to Set

Make sure to set in your `terraform.tfvars`:

```hcl
enable_kube_auth_management = false  # Set to true after first deployment
bastion_role_arn = "arn:aws:iam::ACCOUNT:role/your-bastion-role"
# ... other variables
```

## Troubleshooting

1. **Cluster not ready**: Wait 30-60 seconds between stages
2. **Authentication issues**: Update kubeconfig: `aws eks update-kubeconfig --region REGION --name CLUSTER_NAME`
3. **Provider errors**: Ensure your AWS credentials are configured correctly

This approach gives you the best balance of simplicity and reliability for managing EKS authentication in Terraform.
