# Middleware Layer

This layer deploys cluster operators and middleware services on the EKS cluster. It depends on the base infrastructure layer and provides services needed by the application layer.

## Components

### KEDA Operator
- **Purpose**: Event-driven autoscaling for Kubernetes workloads
- **Version**: Configurable (default: 2.15.1)
- **Namespace**: `keda-system` (configurable)
- **IAM Role**: Created with permissions for CloudWatch metrics, SQS, and logging

### External Secrets Operator (ESO)
- **Purpose**: Synchronizes secrets from AWS Secrets Manager to Kubernetes secrets
- **Version**: Configurable (default: 0.10.4)  
- **Namespace**: `external-secrets-system` (configurable)
- **IAM Role**: Created with basic Secrets Manager permissions
- **ClusterSecretStore**: Creates AWS Secrets Manager integration

### Buildkitd Service
- **Purpose**: Provides cluster-wide container build capabilities
- **Image**: `moby/buildkit:v0.12.5` (configurable)
- **Namespace**: `buildkit-system` (configurable)
- **Deployment**: Standalone service accessible cluster-wide
- **Storage**: Configurable ephemeral storage for builds

### Namespaces Created
- KEDA system namespace
- External Secrets system namespace  
- ADO agents namespace (for application layer)
- Buildkit system namespace (if enabled)

## Dependencies

This layer depends on the **base infrastructure layer** and reads its remote state for:
- Cluster connection information (endpoint, certificate)
- OIDC provider ARN (for IRSA roles)
- Cluster name and networking details

## Prerequisites

- Base infrastructure layer deployed successfully
- Access to base layer remote state in S3
- AWS CLI configured with appropriate permissions
- kubectl configured for the cluster
- Terraform >= 1.5

## Required IAM Permissions

The deploying user/role needs permissions for:
- IAM role and policy management
- Kubernetes resource creation via EKS
- Reading remote state from S3

## Usage

1. **Ensure base layer is deployed:**
   ```bash
   # Verify base layer outputs are available
   cd ../base
   terraform output
   ```

2. **Copy configuration file:**
   ```bash
   cp terraform.tfvars.sample terraform.tfvars
   ```

3. **Edit terraform.tfvars:**
   ```hcl
   remote_state_bucket = "your-terraform-state-bucket"
   # Other configuration...
   ```

4. **Set environment variable for remote state:**
   ```bash
   export TF_STATE_BUCKET='your-terraform-state-bucket'
   ```

5. **Deploy using orchestration script (recommended):**
   ```bash
   # From infrastructure-layered/ directory
   cd ..
   ./deploy.sh --layer middleware deploy
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

## Configuration Notes

### KEDA Configuration
- **Namespace**: KEDA creates both its own namespace and the ADO agents namespace
- **IAM Permissions**: Configured for Azure DevOps pipeline scaling
- **Service Account**: Automatically annotated with IRSA role ARN

### ESO Configuration
- **Webhook**: Disabled by default for Fargate compatibility
- **ClusterSecretStore**: Automatically configured for AWS Secrets Manager
- **IAM Permissions**: Basic Secrets Manager access (specific secrets added by application layer)

### Buildkitd Configuration
- **Privileged**: Runs in privileged mode for container builds
- **Node Selection**: Can be configured to run on specific EC2 nodes
- **Storage**: Uses ephemeral storage (configurable size)
- **Service**: Exposed as ClusterIP service for cluster-wide access

## Verification

After deployment, verify components are running:

```bash
# Check KEDA operator
kubectl get pods -n keda-system
kubectl get scaledobjects -A  # Should be empty until application layer

# Check External Secrets Operator
kubectl get pods -n external-secrets-system
kubectl get clustersecretstores

# Check Buildkitd (if enabled)
kubectl get pods -n buildkit-system
kubectl get svc -n buildkit-system

# Check namespaces
kubectl get namespaces | grep -E "(keda|external-secrets|ado-agents|buildkit)"
```

## Outputs

This layer provides outputs for the application layer:

### Essential Outputs
- `keda_operator_role_arn` - IAM role for KEDA service account
- `eso_role_arn` - IAM role for ESO service account  
- `ado_agents_namespace` - Namespace for application deployments
- `cluster_secret_store_name` - Name of AWS Secrets Manager ClusterSecretStore
- `buildkitd_service_endpoint` - Buildkitd service endpoint for builds

### Usage in Application Layer
```hcl
# Example: application layer reading middleware outputs
data "terraform_remote_state" "middleware" {
  backend = "s3"
  config = {
    bucket = "your-terraform-state-bucket"
    key    = "middleware/terraform.tfstate"
    region = "us-west-2"
  }
}

# Use middleware information
namespace = data.terraform_remote_state.middleware.outputs.ado_agents_namespace
```

## Upgrading

### KEDA Version Upgrades
1. Update `keda_version` in terraform.tfvars
2. Apply changes: `terraform plan && terraform apply`
3. Verify ScaledObjects continue working after upgrade

### ESO Version Upgrades  
1. Update `eso_version` in terraform.tfvars
2. Apply changes: `terraform plan && terraform apply`
3. Verify ExternalSecrets continue synchronizing

### Buildkitd Image Updates
1. Update `buildkitd_image` in terraform.tfvars
2. Apply changes (will restart buildkitd pods)
3. Test builds work with new version

## Troubleshooting

### Common Issues

**Issue: KEDA operator pods not starting**
- Check Fargate profile includes `keda-system` namespace
- Verify IAM role has correct trust policy for OIDC provider
- Check tolerations match node configuration

**Issue: ESO pods not starting**
- Verify webhook is disabled (`eso_webhook_enabled = false`) for Fargate
- Check namespace is included in Fargate profile selectors
- Verify IAM permissions for Secrets Manager

**Issue: Buildkitd pods failing**
- Check if privileged containers are allowed in the namespace
- Verify node selector and tolerations match available nodes
- Check resource requests don't exceed node capacity

**Issue: Remote state access denied**
- Verify S3 bucket exists and is accessible
- Check IAM permissions for state bucket access
- Ensure base layer state exists at expected key

### Logs and Debugging
```bash
# KEDA logs
kubectl logs -n keda-system -l app.kubernetes.io/name=keda-operator

# ESO logs  
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# Buildkitd logs
kubectl logs -n buildkit-system -l app=buildkitd

# Check IAM role annotations
kubectl get sa -n keda-system keda-operator -o yaml
kubectl get sa -n external-secrets-system external-secrets -o yaml
```

## Security Considerations

### IAM Roles
- KEDA role has minimal permissions for metrics and logging
- ESO role has basic Secrets Manager permissions (specific secrets added by app layer)
- Both roles use OIDC provider for secure IRSA authentication

### Buildkitd Security
- Runs in privileged mode (required for container builds)
- Consider using dedicated EC2 nodes with taints for isolation
- Storage is ephemeral and cleared between builds

### Network Security
- All services use ClusterIP (internal only)
- Communication secured by Kubernetes network policies (if configured)
- Buildkitd accessible only within cluster

## Cost Optimization

- Use Fargate for consistent workloads (KEDA, ESO)
- Consider EC2 nodes for buildkitd if builds are frequent
- Monitor buildkitd resource usage and adjust limits
- ESO reduces secret management overhead

## Next Steps

After deploying the middleware layer:
1. **Application Layer**: Deploy ADO agents, ECR repositories, and secrets
2. **Verification**: Test end-to-end pipeline functionality
3. **Monitoring**: Set up observability for the middleware components

## Dependencies Summary

**Reads from Base Layer:**
- Cluster connection details
- OIDC provider information  
- Network configuration
- Security groups

**Provides to Application Layer:**
- KEDA autoscaling capabilities
- Secret synchronization via ESO
- Container build services via buildkitd
- Application namespace