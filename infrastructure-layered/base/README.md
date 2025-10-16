# Base Infrastructure Layer

This layer provides the foundational EKS cluster infrastructure for the ADO Agent platform. It includes all core AWS resources needed for a secure, production-ready Kubernetes cluster.

## Components

### Core Infrastructure
- **EKS Cluster**: Managed Kubernetes control plane
- **IAM Roles**: Service roles for cluster and Fargate
- **Security Groups**: Network security for cluster and pods
- **KMS Keys**: Encryption keys for cluster secrets and storage
- **OIDC Provider**: Identity provider for IRSA (IAM Roles for Service Accounts)

### Networking
- **VPC Endpoints**: Private endpoints for AWS services to reduce NAT gateway costs
- **Security Groups**: Ingress/egress rules for cluster communication

### Compute
- **Fargate Profiles**: Serverless compute for system and application workloads
- **EC2 Node Groups** (optional): Self-managed compute nodes for specialized workloads
- **Cluster Autoscaler** (optional): Automatic node scaling for EC2 node groups

### Add-ons
- **CoreDNS**: DNS resolution for the cluster
- **VPC CNI**: Container networking
- **kube-proxy**: Network proxy

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5
- Existing VPC with private subnets
- S3 bucket for remote state storage (configured separately)

## Required IAM Permissions

The deploying user/role needs the following AWS permissions:
- EKS cluster management
- IAM role creation and policy attachment
- VPC endpoint creation
- KMS key management
- EC2 security group management

## Usage

1. **Copy configuration file:**
   ```bash
   cp terraform.tfvars.sample terraform.tfvars
   ```

2. **Edit terraform.tfvars with your values:**
   ```hcl
   cluster_name = "your-cluster-name"
   vpc_id       = "vpc-xxxxxxxxx"
   subnet_ids   = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]
   ```

3. **Configure remote state backend:**
   ```bash
   terraform init \\
     -backend-config="bucket=your-terraform-state-bucket" \\
     -backend-config="key=base/terraform.tfstate" \\
     -backend-config="region=us-west-2"
   ```

4. **Deploy infrastructure:**
   ```bash
   terraform plan
   terraform apply
   ```

## Important Configuration Notes

### Fargate Profiles
The base layer creates Fargate profiles for:
- `kube-system` namespace (CoreDNS only)
- `keda-system` namespace (for middleware layer)
- `external-secrets-system` namespace (for middleware layer)
- `ado-agents` namespace (for application layer)

### VPC Endpoints
VPC endpoints reduce NAT gateway costs by providing private connectivity to AWS services:
- S3 (Gateway endpoint)
- ECR API/DKR (Interface endpoints)
- CloudWatch Logs, Secrets Manager, STS (Interface endpoints)

### Security Considerations
- Cluster endpoint is private by default (`endpoint_public_access = false`)
- All communication encrypted in transit
- Optional KMS encryption for cluster secrets
- Security groups restrict access to VPC CIDR blocks

## Outputs

This layer outputs key information needed by the middleware and application layers:

### Essential Outputs
- `cluster_name`, `cluster_arn`, `cluster_endpoint`
- `oidc_provider_arn` - Required for IRSA in subsequent layers
- `fargate_role_arn`, `cluster_role_arn` - IAM role references
- `kms_key_arn` - For encryption in other layers
- `vpc_id`, `subnet_ids` - Network configuration

### Usage in Other Layers
```hcl
# Example: middleware layer reading base layer outputs
data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = "your-terraform-state-bucket"
    key    = "base/terraform.tfstate"
    region = "us-west-2"
  }
}

# Access cluster information
cluster_name = data.terraform_remote_state.base.outputs.cluster_name
```

## Validation

After deployment, verify the cluster is working:

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name your-cluster-name

# Verify cluster access
kubectl get nodes
kubectl get pods -A

# Check Fargate profiles
aws eks describe-fargate-profile --cluster-name your-cluster-name --fargate-profile-name your-cluster-name-apps-fargate-profile
```

## Upgrading

### Kubernetes Version Upgrades
1. Update `cluster_version` in terraform.tfvars
2. Update `eks_addons` versions to match
3. Apply changes: `terraform plan && terraform apply`
4. Update worker node groups separately if using EC2 nodes

### Add-on Upgrades
Monitor AWS documentation for recommended add-on versions and update the `eks_addons` map accordingly.

## Troubleshooting

### Common Issues

**Issue: Cluster creation fails with insufficient permissions**
- Verify IAM permissions for EKS cluster creation
- Check VPC and subnet permissions

**Issue: Fargate pods stuck in pending state**
- Verify Fargate profile selectors match pod namespaces/labels
- Check subnet configuration (must be private subnets)

**Issue: CoreDNS pods not starting**
- Verify system Fargate profile is created
- Check that `fargate_system_profile_selectors` includes CoreDNS selector

### Logs and Debugging
```bash
# Check EKS cluster logs
aws logs describe-log-groups --log-group-name-prefix /aws/eks/your-cluster-name

# Describe cluster for detailed status
aws eks describe-cluster --name your-cluster-name
```

## Cost Optimization

- Use Fargate for consistent workloads (no idle node costs)
- Enable VPC endpoints to reduce NAT gateway data transfer costs
- Consider Spot instances for EC2 node groups if using them
- Enable cluster logging selectively (logs incur CloudWatch costs)

## Security Best Practices

- Keep cluster endpoint private (`endpoint_public_access = false`)
- Use KMS encryption for cluster secrets
- Regularly update Kubernetes version and add-ons
- Monitor access via CloudTrail
- Use least-privilege IAM policies

## Dependencies

This layer has no dependencies on other infrastructure layers. It creates all foundational resources needed for the middleware and application layers.

## Next Steps

After deploying the base layer, proceed to:
1. **Middleware Layer**: Deploy KEDA, ESO, and other cluster operators
2. **Application Layer**: Deploy ADO agents and application-specific resources