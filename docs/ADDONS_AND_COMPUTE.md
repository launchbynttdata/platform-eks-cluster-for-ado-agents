# EKS Addons and Compute Independence

## Summary

EKS managed addons (CoreDNS, kube-proxy, VPC CNI) are **compute-agnostic** - they will schedule on whatever compute is available (Fargate or EC2). However, they **require at least one compute resource to exist** before installation.

## Architecture Decision

**Addons wait for compute resources to be available before installation**:
- If Fargate profiles are defined → addons wait for Fargate profiles
- If EC2 node groups are defined → addons wait for EC2 node groups  
- If both are defined → addons wait for both
- Addons always wait for the cluster itself

This ensures addons can schedule immediately upon installation rather than remaining in a pending state.

## How It Works

### Addon Deployment Flow

```
1. Create EKS Cluster
   ↓
2. Create Compute Resources (in parallel):
   - Fargate Profiles (if configured)
   - EC2 Node Groups (if configured)
   ↓
3. Install EKS Addons (after compute is ready)
   - CoreDNS
   - kube-proxy  
   - VPC CNI
   ↓
4. Addons Automatically Schedule on Available Compute
```

### Smart Dependencies

The addon installation uses **static dependencies** in Terraform that reference all potential compute resources:

```hcl
resource "aws_eks_addon" "addons" {
  # ... addon configuration ...
  
  # Static list of all potential dependencies
  # Terraform will only wait for the ones that actually get created
  depends_on = [
    module.eks_cluster,      # Always waits for cluster
    module.fargate_profile,  # Waits if Fargate profiles are created
    module.ec2_nodes         # Waits if EC2 node groups are created
  ]
}
```

**How It Works**:
- Terraform's `depends_on` requires a **static list** (no dynamic expressions)
- We list **all potential** compute resources (Fargate and EC2)
- Terraform automatically **skips dependencies** for resources that don't exist
- If you configure EC2 only → waits for EC2 only
- If you configure Fargate only → waits for Fargate only
- If you configure both → waits for both

**Benefits**:
- ✅ Addons install only after compute is available
- ✅ Avoids pods stuck in `Pending` state
- ✅ Faster deployment (no waiting for scheduler retries)
- ✅ Works with any compute configuration automatically
- ✅ Simple, maintainable code

### No Special Configuration Needed

The addons **do not require**:
- ❌ Explicit configuration for Fargate vs EC2
- ❌ Manual tolerations for Fargate taints
- ❌ Different versions for different compute types

The addons **automatically handle**:
- ✅ Detecting available compute (Fargate or EC2)
- ✅ Applying appropriate tolerations for Fargate taints
- ✅ Scheduling based on namespace and label selectors
- ✅ Running as DaemonSets on all available nodes

## Deployment Patterns

### Pattern 1: Fargate Only

```hcl
fargate_profiles = {
  system = {
    selectors = [
      { namespace = "kube-system", labels = {"k8s-app" = "kube-dns"} }
    ]
  }
}

ec2_node_group = {}  # No EC2 nodes
```

**Result**: All addons run on Fargate pods

### Pattern 2: EC2 Only

```hcl
fargate_profiles = {}  # No Fargate

ec2_node_group = {
  default = {
    instance_types = ["t3.medium"]
    desired_size   = 2
  }
}
```

**Result**: All addons run on EC2 nodes

### Pattern 3: Mixed (Recommended)

```hcl
fargate_profiles = {
  system = {
    selectors = [
      { namespace = "kube-system", labels = {"k8s-app" = "kube-dns"} }
    ]
  }
}

ec2_node_group = {
  apps = {
    instance_types = ["t3.large"]
    desired_size   = 2
  }
}
```

**Result**:
- CoreDNS runs on Fargate (matches system profile)
- kube-proxy runs on both Fargate and EC2 (DaemonSet)
- vpc-cni runs on both Fargate and EC2 (DaemonSet)
- Application workloads run on EC2 nodes

## Technical Details

### Fargate Scheduling

When a Fargate profile exists:

1. EKS applies a taint to Fargate pods: `eks.amazonaws.com/compute-type=fargate:NoSchedule`
2. EKS automatically adds tolerations to system addons
3. Pods matching the Fargate profile selectors schedule on Fargate
4. Other pods schedule on EC2 nodes (if available)

### DaemonSet Behavior

DaemonSets like kube-proxy and vpc-cni:
- Run on **all nodes** (both Fargate pods and EC2 instances)
- Automatically tolerate Fargate taints
- One pod per node/Fargate pod

### Deployment Behavior

Deployments like CoreDNS:
- Schedule based on namespace and label selectors
- Use standard Kubernetes scheduling logic
- Respect Fargate profile selectors when present

## Troubleshooting

### CoreDNS Pending

**Symptom**: CoreDNS pods stuck in `Pending` state

**Cause**: No compute resources match the scheduling requirements

**Solutions**:

1. **If using Fargate**: Create a system Fargate profile
   ```hcl
   fargate_profiles = {
     system = {
       selectors = [
         {
           namespace = "kube-system"
           labels = {"k8s-app" = "kube-dns"}
         }
       ]
     }
   }
   ```

2. **If using EC2**: Ensure node groups are running
   ```bash
   kubectl get nodes
   ```

3. **Check addon status**:
   ```bash
   aws eks describe-addon \
     --cluster-name <cluster-name> \
     --addon-name coredns
   ```

### Addons Not Scheduling on Fargate

**Symptom**: Addons running on EC2 nodes despite Fargate profile existing

**Cause**: Fargate profile selectors don't match the addon namespace/labels

**Solution**: Verify Fargate profile matches CoreDNS requirements:
```bash
# Check CoreDNS labels
kubectl get pods -n kube-system -l k8s-app=kube-dns --show-labels

# Check Fargate profile
aws eks describe-fargate-profile \
  --cluster-name <cluster-name> \
  --fargate-profile-name <profile-name>
```

## Best Practices

1. **Keep Addons Simple**: Don't add dependencies on compute resources
2. **Let Kubernetes Schedule**: Trust the scheduler to place addons correctly
3. **Test Both Patterns**: Verify addons work with Fargate-only, EC2-only, and mixed configurations
4. **Monitor Addon Health**: Use `kubectl get pods -n kube-system` to verify addon status
5. **Use Default Versions**: Unless you have specific requirements, use the default addon versions for your EKS version

## References

- [EKS Add-ons Documentation](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [Fargate Pod Configuration](https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-configuration.html)
- [EKS Fargate Considerations](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html#fargate-considerations)
