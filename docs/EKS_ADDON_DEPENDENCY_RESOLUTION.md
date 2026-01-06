# EKS Addon Dependency Resolution

## Problem: Circular Dependency

### Symptom
Nodes fail to join the EKS cluster with the error:
```
container runtime network not ready: NetworkReady=false 
reason:NetworkPluginNotReady 
message:Network plugin returns error: cni plugin not initialized
```

### Root Cause
The VPC CNI addon must be installed and running **before** nodes (EC2 or Fargate) can successfully join the cluster. This is a fundamental EKS architecture requirement.

### The Incorrect Assumption
Initially, the dependency logic was:
```
EKS Cluster → Addons → Compute Resources (Nodes/Fargate)
```

This seemed logical because:
- Addons run as pods
- Pods need compute resources to schedule

However, this is **backwards** for EKS!

### The Correct Dependency Order
```
EKS Cluster → VPC CNI Addon → Compute Resources → Other Addons
```

The VPC CNI addon:
1. Runs on the EKS control plane (not on worker nodes)
2. Configures networking for new nodes as they join
3. Must be ready **before** nodes attempt to join

Other addons (CoreDNS, kube-proxy, etc.):
1. Run as pods on worker nodes
2. Require compute resources to be available
3. Should be installed **after** nodes join the cluster

## Solution Implementation

### 1. VPC CNI Addon - Install First
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
- Separate resource for VPC CNI addon
- Only depends on the cluster
- No dependency on compute resources
- VPC CNI installs immediately after cluster creation

### 2. EC2 Node Groups - Wait for VPC CNI
```hcl
module "ec2_nodes" {
  source   = "../../infrastructure/modules/primitive/eks-node-group"
  for_each = var.ec2_node_group

  # ... node configuration ...

  # Wait for VPC CNI addon before creating nodes - it's required for nodes to join
  depends_on = [aws_eks_addon.vpc_cni]
}
```

### 3. Fargate Profiles - Wait for VPC CNI
```hcl
module "fargate_profile" {
  for_each = var.fargate_profiles
  source   = "../../infrastructure/modules/primitive/fargate-profile"

  # ... profile configuration ...

  # Wait for IAM roles, cluster, and VPC CNI addon before creating Fargate profiles
  depends_on = [
    module.eks_cluster,
    module.iam_roles,
    aws_eks_addon.vpc_cni
  ]
}
```

### 4. Other Addons - Install After Compute Resources

```hcl
# Other EKS Addons - Install after compute resources are available
# These addons run as pods on worker nodes and need compute capacity
resource "aws_eks_addon" "addons" {
  for_each = {
    for name, config in var.eks_addons : name => config
    if name != "vpc-cni"
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
- Filters out VPC CNI from the addon list
- Depends on compute resources (EC2 nodes and/or Fargate profiles)
- Addons like CoreDNS and kube-proxy run as pods and need worker nodes

## Dependency Flow Diagram

```
┌─────────────────┐
│   EKS Cluster   │
└────────┬────────┘
         │
         ├──────────────┬──────────────┬──────────────┐
         │              │              │              │
         v              v              v              v
┌────────────────┐ ┌─────────┐  ┌──────────┐  ┌─────────────┐
│   VPC Endpoints│ │IAM Roles│  │ VPC CNI  │  │             │
└────────────────┘ └─────┬───┘  └────┬─────┘  │   Other     │
                         │            │        │   Addons    │
                         v            │        │  (pending)  │
                    ┌─────────────────┴──────┐ │             │
                    │                        │ │             │
                    v                        v │             │
            ┌───────────────┐      ┌─────────────────┐      │
            │Fargate Profiles│      │ EC2 Node Groups │      │
            └───────┬───────┘      └─────────┬───────┘      │
                    │                        │              │
                    └────────────┬───────────┘              │
                                 │                          │
                                 v                          │
                           ┌───────────┐                    │
                           │  Compute  ├────────────────────┘
                           │ Resources │
                           │ Available │
                           └─────┬─────┘
                                 │
                                 v
                      ┌────────────────────┐
                      │   Other Addons     │
                      │  (CoreDNS, etc.)   │
                      │     Deployed       │
                      └────────────────────┘
```

## Why This Works

### VPC CNI Addon Behavior
1. **Runs on Control Plane**: The VPC CNI addon installs on the EKS control plane, not on worker nodes
2. **Configures Node Networking**: When a new node joins, the control plane uses VPC CNI to:
   - Assign IP addresses from the VPC subnet
   - Configure the container network interface (CNI) on the node
   - Enable pod-to-pod networking
3. **Required for Node Join**: Without VPC CNI ready, nodes cannot complete their join process

### No Circular Dependency
- **VPC CNI** doesn't need compute resources (runs on control plane)
- **Nodes** DO need VPC CNI to join successfully
- **Other addons** (CoreDNS, kube-proxy) need compute resources (run as pods)
- Therefore: Cluster → VPC CNI → Compute → Other Addons is the correct order

## Other EKS Addons

While VPC CNI is the critical one for node join, other common addons follow the same pattern:

| Addon | Purpose | Runs On | Required Before Nodes? |
|-------|---------|---------|------------------------|
| vpc-cni | Pod networking | Control plane | ✅ YES |
| kube-proxy | Service networking | Each node | ⚠️ Recommended |
| coredns | DNS resolution | Worker pods | ❌ No (but should be early) |
| aws-ebs-csi-driver | EBS volume provisioning | Worker pods | ❌ No |

**Best Practice**: Install ALL addons before compute resources to ensure a clean, deterministic deployment order.

## Testing the Fix

After implementing these dependency changes:

1. Deploy the base layer:
   ```bash
   cd infrastructure-layered/base
   ../../deploy.sh --layer base deploy
   ```

2. Monitor node join status:
   ```bash
   kubectl get nodes -w
   ```

3. Verify VPC CNI is running:
   ```bash
   kubectl get pods -n kube-system | grep aws-node
   ```

4. Check node network readiness:
   ```bash
   kubectl describe nodes | grep -A5 "Network"
   ```

## Lessons Learned

1. **EKS Addons Run on Control Plane**: Not all Kubernetes components run on worker nodes. EKS addons are special.

2. **Terraform Static Dependencies**: The `depends_on` meta-argument requires a static list. Dynamic logic (like `concat()` or conditional statements) is not supported.

3. **Non-Existent Resources Are OK**: Terraform handles `depends_on` gracefully when resources don't exist. For example:
   ```hcl
   depends_on = [module.ec2_nodes, module.fargate_profile]
   ```
   Works even if one of those modules creates zero resources (due to empty `for_each`).

4. **Read AWS Documentation**: The EKS addon architecture is specific to AWS. Always verify assumptions against official AWS documentation.

## References

- [EKS Add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [VPC CNI Plugin](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)
- [Terraform depends_on](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)
