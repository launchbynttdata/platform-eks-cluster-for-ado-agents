# Cluster Autoscaler Deployment in Layered Infrastructure

## Overview

The Cluster Autoscaler is automatically deployed as part of the middleware layer in the layered infrastructure approach. It's deployed only if enabled in the base layer configuration.

## Configuration

### Base Layer (`infrastructure-layered/base/terraform.tfvars`)

Enable cluster autoscaler in the base layer:

```hcl
enable_cluster_autoscaler    = true
cluster_autoscaler_namespace = "kube-system"
```

This creates:
- IAM role for Cluster Autoscaler with IRSA
- IAM policy with autoscaling permissions
- Proper tags on EC2 node groups for discovery

### Automatic Deployment

When you run the layered deployment:

```bash
cd infrastructure-layered
./deploy.sh
```

The cluster autoscaler will be automatically deployed during the middleware layer deployment if:
1. `enable_cluster_autoscaler = true` in the base layer
2. The IAM role was successfully created
3. kubectl is configured and can access the cluster

## How It Works

1. **Base Layer**: Creates IAM role and tags node groups
2. **Middleware Layer Deployment**: After KEDA and ESO are deployed, the `deploy.sh` script:
   - Checks if cluster autoscaler IAM role exists
   - Substitutes placeholders in the manifest template
   - Applies the Kubernetes manifest
   - Waits for the deployment to be ready

## Manifest Template

The cluster autoscaler manifest is located at:
```
infrastructure-layered/middleware/cluster-autoscaler.yaml
```

It uses placeholders that are automatically replaced during deployment:
- `CLUSTER_AUTOSCALER_ROLE_ARN_PLACEHOLDER` - IAM role ARN from base layer
- `CLUSTER_NAME_PLACEHOLDER` - EKS cluster name
- `AWS_REGION_PLACEHOLDER` - AWS region
- `CLUSTER_AUTOSCALER_VERSION_PLACEHOLDER` - Autoscaler version (v1.30.0)

## Key Configuration

### Node Selector
The autoscaler runs on **Fargate** nodes to avoid chicken-and-egg problems:
```yaml
nodeSelector:
  eks.amazonaws.com/compute-type: fargate
```

### Auto-Discovery
The autoscaler automatically discovers node groups with proper tags:
```bash
--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<cluster-name>
```

### Scaling Parameters
```bash
--scale-down-enabled=true
--scale-down-delay-after-add=10m
--scale-down-unneeded-time=10m
--scale-down-utilization-threshold=0.5
--max-node-provision-time=15m
```

## Verification

After deployment, verify the cluster autoscaler:

```bash
# Check deployment status
kubectl get deployment -n kube-system cluster-autoscaler

# Check pod status
kubectl get pods -n kube-system -l app=cluster-autoscaler

# View logs
kubectl logs -n kube-system deployment/cluster-autoscaler

# Check discovered node groups
kubectl logs -n kube-system deployment/cluster-autoscaler | grep "Discovered node groups"
```

Expected output in logs:
```
I1020 12:00:00.000000       1 auto_scaling_groups.go:xxx] Discovered 3 ASGs
```

## Testing Autoscaling

### Test Scale Up

Create a deployment that requires more nodes:

```bash
# Create test deployment
kubectl create deployment autoscale-test --image=nginx --replicas=20

# Set resource requests to trigger node provisioning
kubectl set resources deployment autoscale-test --requests=cpu=1,memory=1Gi

# Watch nodes scale up
kubectl get nodes -w
```

### Test Scale Down

```bash
# Delete the test deployment
kubectl delete deployment autoscale-test

# After 10 minutes (scale-down-delay-after-add), unused nodes will be removed
# Watch the scale down
kubectl get nodes -w
```

## Troubleshooting

### Autoscaler Not Deployed

Check if it's enabled:
```bash
cd infrastructure-layered/base
terraform output cluster_autoscaler_role_arn
```

If it returns null, enable it in `base/terraform.tfvars` and re-run terraform apply.

### Pods Not Scheduling on New Nodes

Check autoscaler logs:
```bash
kubectl logs -n kube-system deployment/cluster-autoscaler | tail -50
```

Common issues:
- Node group at max capacity
- IAM permissions missing
- Node group tags incorrect

### Manual Redeployment

If you need to redeploy only the cluster autoscaler:

```bash
cd infrastructure-layered
./deploy.sh --layer middleware
```

Or manually:
```bash
cd infrastructure-layered/middleware

# Get values from Terraform
CLUSTER_NAME=$(cd ../base && terraform output -raw cluster_name)
ROLE_ARN=$(cd ../base && terraform output -raw cluster_autoscaler_role_arn)
AWS_REGION=${AWS_REGION:-us-west-2}

# Apply with substitutions
sed -e "s|CLUSTER_AUTOSCALER_ROLE_ARN_PLACEHOLDER|${ROLE_ARN}|g" \
    -e "s|CLUSTER_NAME_PLACEHOLDER|${CLUSTER_NAME}|g" \
    -e "s|AWS_REGION_PLACEHOLDER|${AWS_REGION}|g" \
    -e "s|CLUSTER_AUTOSCALER_VERSION_PLACEHOLDER|v1.30.0|g" \
    cluster-autoscaler.yaml | kubectl apply -f -
```

## Node Group Requirements

For cluster autoscaler to work, node groups must have:

1. **Proper Tags** (automatically added by base layer):
   ```
   k8s.io/cluster-autoscaler/enabled = "true"
   k8s.io/cluster-autoscaler/<cluster-name> = "owned"
   ```

2. **Min/Max Size Configuration**:
   ```hcl
   scaling_config = {
     desired_size = 1
     min_size     = 0    # Can scale to zero
     max_size     = 5    # Maximum nodes
   }
   ```

3. **IAM Instance Profile**: Automatically configured by EKS

## Version Compatibility

| EKS Version | Cluster Autoscaler Version |
|-------------|---------------------------|
| 1.30        | v1.30.x                   |
| 1.29        | v1.29.x                   |
| 1.28        | v1.28.x                   |

The deploy script uses v1.30.0 by default, which supports EKS 1.30+.

## References

- [AWS Cluster Autoscaler Documentation](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)
- [Cluster Autoscaler GitHub](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
