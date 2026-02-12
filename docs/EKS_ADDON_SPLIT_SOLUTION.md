# EKS Addon Split: VPC CNI vs Other Addons

## Problem Discovery

After implementing the initial circular dependency fix, we discovered that CoreDNS was showing as "degraded" even though the VPC CNI addon was installed correctly. This revealed a critical distinction between EKS addons:

### Two Types of EKS Addons

1. **Control Plane Addons** (VPC CNI)
   - Run on the EKS control plane
   - Do NOT require worker nodes
   - Required for nodes to join the cluster
   - Must be installed BEFORE compute resources

2. **Worker Node Addons** (CoreDNS, kube-proxy, etc.)
   - Run as pods on worker nodes
   - REQUIRE compute resources to be available
   - Must be installed AFTER compute resources

## Updated Solution

### The Correct Dependency Order

```
EKS Cluster → VPC CNI Addon → Compute Resources → Other Addons
```

### Implementation

#### 1. VPC CNI Addon (Separate Resource)

```hcl
# VPC CNI Addon - CRITICAL: Install first, required for nodes to join cluster
resource "aws_eks_addon" "vpc_cni" {
  count = contains(keys(var.eks_addons), "vpc-cni") ? 1 : 0

  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = try(var.eks_addons["vpc-cni"].version, null)
  resolve_conflicts_on_create = try(var.eks_addons["vpc-cni"].resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(var.eks_addons["vpc-cni"].resolve_conflicts_on_update, "OVERWRITE")
  
  depends_on = [module.eks_cluster]

  tags = local.common_tags
}
```

**Key Points:**
- Separate resource ensures it installs first
- Only depends on the cluster
- Uses `count` to handle optional VPC CNI configuration

#### 2. Compute Resources (EC2 and Fargate)

```hcl
module "ec2_nodes" {
  source   = "../../modules/primitive/eks-node-group"
  for_each = var.ec2_node_group

  # ... configuration ...

  # Wait for VPC CNI addon before creating nodes
  depends_on = [aws_eks_addon.vpc_cni]
}

module "fargate_profile" {
  for_each = var.fargate_profiles
  source   = "../../modules/primitive/fargate-profile"

  # ... configuration ...

  # Wait for IAM roles, cluster, and VPC CNI addon
  depends_on = [
    module.eks_cluster,
    module.iam_roles,
    aws_eks_addon.vpc_cni
  ]
}
```

#### 3. Other Addons (After Compute)

```hcl
# Other EKS Addons - Install after compute resources are available
resource "aws_eks_addon" "addons" {
  for_each = {
    for name, config in var.eks_addons : name => config
    if name != "vpc-cni"  # Exclude VPC CNI
  }

  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")

  # Wait for compute resources to be available
  depends_on = [
    module.eks_cluster,
    module.ec2_nodes,
    module.fargate_profile
  ]

  tags = local.common_tags
}
```

**Key Points:**
- Filters out VPC CNI from the loop
- Depends on BOTH EC2 and Fargate (Terraform handles empty for_each)
- Ensures addons have compute resources to schedule pods

## Visual Deployment Flow

```
Time →

1. EKS Cluster Created
   ├─ VPC Endpoints
   ├─ IAM Roles
   └─ VPC CNI Addon (pending, but available)
        ↓
2. Compute Resources Created
   ├─ EC2 Node Groups (join using VPC CNI)
   └─ Fargate Profiles (register using VPC CNI)
        ↓
3. Nodes Join Cluster (using VPC CNI)
        ↓
4. Other Addons Deployed
   ├─ CoreDNS (schedules on worker nodes)
   ├─ kube-proxy (schedules on worker nodes)
   └─ Others (schedule on worker nodes)
```

## Why This Fixes CoreDNS Degraded Status

### Before (Incorrect)

```
Cluster → All Addons (including CoreDNS) → Compute Resources
```

**Problem:** CoreDNS tries to schedule pods immediately but has no nodes available, resulting in "degraded" state.

### After (Correct)

```
Cluster → VPC CNI → Compute Resources → CoreDNS
```

**Solution:** CoreDNS waits for nodes to be available before attempting to schedule pods.

## Deployment Validation

After deployment, verify the order:

```bash
# 1. Check VPC CNI is running on control plane
kubectl get daemonset -n kube-system aws-node

# 2. Check nodes have joined successfully
kubectl get nodes

# 3. Check CoreDNS is healthy (not degraded)
kubectl get deployment -n kube-system coredns
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 4. Check all addons are active
aws eks describe-addon --cluster-name <cluster-name> --addon-name vpc-cni
aws eks describe-addon --cluster-name <cluster-name> --addon-name coredns
aws eks describe-addon --cluster-name <cluster-name> --addon-name kube-proxy
```

## Common Patterns by Addon Type

### Control Plane Addons (Install Before Compute)
- `vpc-cni` - Network plugin for node networking

### Worker Node Addons (Install After Compute)
- `coredns` - DNS service (runs as deployment)
- `kube-proxy` - Network proxy (runs as daemonset)
- `aws-ebs-csi-driver` - EBS volume provisioner (runs as deployment + daemonset)
- `aws-efs-csi-driver` - EFS volume provisioner (runs as daemonset)

### Special Case: EBS CSI Driver

The EBS CSI driver should be installed after compute resources since it runs as both a deployment (controller) and daemonset (node plugin) on worker nodes:

```hcl
eks_addons = {
  "vpc-cni" = {
    version = "v1.18.3-eksbuild.1"
  }
  "coredns" = {
    version = "v1.11.1-eksbuild.9"
  }
  "kube-proxy" = {
    version = "v1.33.0-eksbuild.1"
  }
  "aws-ebs-csi-driver" = {
    version = "v1.35.0-eksbuild.1"
    service_account_role_arn = "<IRSA_ROLE_ARN>"
  }
}
```

All addons except `vpc-cni` will be filtered and installed after compute resources.

## Benefits of This Approach

1. **No Degraded Addons**: CoreDNS and other addons wait for nodes before deploying
2. **Faster Node Join**: Nodes don't wait for addons that don't need to be ready
3. **Correct Dependency Order**: Matches EKS architecture requirements
4. **Flexible**: Handles both EC2 and Fargate compute types
5. **Maintainable**: Clear separation between control plane and worker addons

## Migration from Previous Approach

If you have the old approach where all addons depend on compute:

```hcl
# OLD - All addons together
resource "aws_eks_addon" "addons" {
  for_each = var.eks_addons
  # ...
  depends_on = [module.ec2_nodes, module.fargate_profile]
}
```

Change to the split approach:

```hcl
# NEW - VPC CNI separate
resource "aws_eks_addon" "vpc_cni" {
  count = contains(keys(var.eks_addons), "vpc-cni") ? 1 : 0
  # ...
  depends_on = [module.eks_cluster]
}

# NEW - Other addons after compute
resource "aws_eks_addon" "addons" {
  for_each = {
    for name, config in var.eks_addons : name => config
    if name != "vpc-cni"
  }
  # ...
  depends_on = [module.ec2_nodes, module.fargate_profile]
}
```

Then update compute resource dependencies:

```hcl
module "ec2_nodes" {
  # ...
  depends_on = [aws_eks_addon.vpc_cni]  # Changed from .addons
}
```

## Terraform Plan Changes

When you apply this change, expect to see:

1. **VPC CNI addon**: May show as replace (moving from one resource to another)
2. **Other addons**: May show as replace (filtering logic changed)
3. **Compute resources**: May show as replace (dependency changed)

This is expected and safe - Terraform will handle the recreation in the correct order.
