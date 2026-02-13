# Cluster Autoscaler Implementation

This document explains the Cluster Autoscaler implementation that has been added to support EC2 node group autoscaling in your mixed Fargate + EC2 EKS environment.

## Overview

The implementation adds AWS Cluster Autoscaler support while maintaining clear separation between Fargate and EC2 workloads:

- **Fargate**: Handles ADO agents, KEDA, External Secrets Operator (auto-scaling built-in)
- **EC2 Nodes**: Handles BuildKit workloads with Cluster Autoscaler for node-level scaling

## Configuration Hierarchy

All configuration is properly parameterized from root to primitive modules:

### Root Level (`infrastructure/variables.tf`)
```hcl
enable_cluster_autoscaler = true
cluster_autoscaler_version = "v1.29.0"
cluster_autoscaler_settings = {
  scale_down_enabled = true
  scale_down_delay_after_add = "10m"
  # ... additional settings
}
```

### Collection Level (`modules/collections/ado-eks-cluster/`)
- Receives configuration from root module
- Creates IAM roles and policies for Cluster Autoscaler
- Passes configuration to primitive modules

### Primitive Level (`modules/primitive/eks-node-group/`)
- Accepts autoscaler configuration flags
- Conditionally applies autoscaler tags based on configuration
- No hardcoded values

## Implementation Details

### 1. IAM Resources
- **Service Account Role**: For IRSA (IAM Roles for Service Accounts)
- **Policy**: Grants necessary autoscaling permissions
- **Only created if**: `enable_cluster_autoscaler = true`

### 2. Node Group Tags
When autoscaler is enabled, node groups get these tags:
```hcl
"k8s.io/cluster-autoscaler/enabled" = "true"
"k8s.io/cluster-autoscaler/${cluster_name}" = "owned"
"k8s.io/cluster-autoscaler/node-template/label/eks.amazonaws.com/compute-type" = "ec2"
"k8s.io/cluster-autoscaler/node-template/label/node-role.kubernetes.io/buildkit" = "true"
```

### 3. VPC Endpoints
Added `autoscaling` VPC endpoint for private subnet communication.

### 4. Mixed Environment Compatibility
- BuildKit pods have explicit node selectors and tolerations
- Cluster Autoscaler scheduled on Fargate (avoids chicken-and-egg problem)
- Clear workload separation prevents scheduling conflicts

## Deployment Steps

### 1. Apply Terraform Changes
```bash
cd infrastructure
terraform plan -out=the.tfplan
terraform apply the.tfplan
```

### 2. Deploy Cluster Autoscaler
```bash
# Run the deployment script (it gets values from terraform outputs)
./deploy-cluster-autoscaler.sh
```

### 3. Verify Installation
```bash
# Check autoscaler logs
kubectl logs -n kube-system deployment/cluster-autoscaler

# Test scaling
kubectl scale deployment buildkitd --replicas=5 -n build
```

## Configuration Variables

### Root Module Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_cluster_autoscaler` | bool | `true` | Enable/disable cluster autoscaler |
| `cluster_autoscaler_version` | string | `"v1.29.0"` | Autoscaler image version |
| `cluster_autoscaler_namespace` | string | `"kube-system"` | Kubernetes namespace |
| `cluster_autoscaler_settings` | object | `{}` | Autoscaler behavior settings |

### Autoscaler Settings Object
```hcl
cluster_autoscaler_settings = {
  scale_down_enabled           = true
  scale_down_delay_after_add   = "10m"
  scale_down_unneeded_time     = "10m" 
  max_node_provision_time      = "15m"
  expander                     = "least-waste"
  skip_nodes_with_system_pods  = false
  skip_nodes_with_local_storage = false
  balance_similar_node_groups  = true
}
```

## Outputs

The implementation provides these outputs:

- `cluster_autoscaler_role_arn`: IAM role ARN for the service account
- `cluster_autoscaler_role_name`: IAM role name
- `cluster_autoscaler_enabled`: Boolean indicating if autoscaler is enabled

## Monitoring

### Check Autoscaler Status
```bash
kubectl get deployment cluster-autoscaler -n kube-system
kubectl logs -n kube-system deployment/cluster-autoscaler
```

### Monitor Node Scaling
```bash
kubectl get nodes --show-labels
kubectl top nodes
```

### Check Events
```bash
kubectl get events --sort-by='.lastTimestamp' -A | grep -i autoscal
```

## Troubleshooting

### Common Issues

1. **Role ARN not found**: Ensure `enable_cluster_autoscaler = true` and run `terraform apply`
2. **Pods not scaling**: Check that BuildKit pods have proper node selectors and tolerations
3. **Autoscaler not starting**: Verify IAM permissions and IRSA configuration

### Debug Commands
```bash
# Check IAM role
aws sts get-caller-identity

# Verify service account annotations
kubectl describe sa cluster-autoscaler -n kube-system

# Check autoscaler configuration
kubectl describe deployment cluster-autoscaler -n kube-system
```

## Best Practices

1. **Gradual Rollout**: Start with conservative settings and adjust based on workload patterns
2. **Monitoring**: Set up CloudWatch alarms for node utilization and scaling events
3. **Testing**: Use `kubectl scale` to test autoscaling behavior before production workloads
4. **Resource Requests**: Ensure pods have proper resource requests for accurate scaling decisions

## Files Modified

### Infrastructure Code
- `infrastructure/variables.tf` - Added autoscaler configuration variables
- `infrastructure/main.tf` - Pass variables to collection module
- `infrastructure/outputs.tf` - Added autoscaler outputs
- `infrastructure/terraform.tfvars` - Enabled autoscaler
- `modules/collections/ado-eks-cluster/main.tf` - Added IAM resources and variable passing
- `modules/collections/ado-eks-cluster/variables.tf` - Added autoscaler variables
- `modules/collections/ado-eks-cluster/outputs.tf` - Added autoscaler outputs
- `modules/primitive/eks-node-group/main.tf` - Added conditional autoscaler tags
- `modules/primitive/eks-node-group/variables.tf` - Added autoscaler configuration
- `modules/collections/vpc-endpoints/main.tf` - Added autoscaling VPC endpoint

### Kubernetes Manifests
- `app/k8s/cluster-autoscaler.yaml` - Cluster Autoscaler deployment template
- `deploy-cluster-autoscaler.sh` - Deployment script with value substitution

This implementation ensures proper configuration hierarchy, no hardcoded values, and compatibility with your mixed Fargate/EC2 environment.