# EKS Addon Deployment: The Correct Approach

## TL;DR - The Solution

**Install ALL EKS addons (including VPC CNI) AFTER compute resources (Fargate/EC2) are created.**

This is the approach used in the original working implementation and matches AWS best practices.

## The Misunderstanding

Initially, we thought:
1. VPC CNI addon must be installed before nodes
2. Nodes need VPC CNI to join the cluster
3. Therefore: Cluster → VPC CNI → Nodes → Other Addons

**This was incorrect.**

## The Reality

### How EKS Addons Actually Work

When you create an EKS addon resource in Terraform:

```hcl
resource "aws_eks_addon" "addons" {
  cluster_name = module.eks_cluster.cluster_name
  addon_name   = "vpc-cni"
  # ...
}
```

This does TWO things:
1. **Registers the addon** with the EKS control plane
2. **Deploys the addon's Kubernetes resources** (DaemonSets, Deployments, etc.)

### The Key Insight

**Nodes don't need the VPC CNI addon to be registered before they're created.**

Instead:
- Nodes are created with AWS's **bootstrap VPC CNI** plugin (built into the AMI)
- They can join the cluster using this bootstrap CNI
- Once joined, the VPC CNI **DaemonSet** (deployed by the addon) takes over

### The Correct Order

```
1. EKS Cluster Created
   ↓
2. Compute Resources Created (Fargate Profiles / EC2 Node Groups)
   ↓
3. Nodes Join Using Bootstrap CNI
   ↓
4. EKS Addons Installed (including VPC CNI)
   ↓
5. VPC CNI DaemonSet Deploys to Nodes
   ↓
6. VPC CNI DaemonSet Takes Over Networking
```

## Why This Works

### For EC2 Nodes

EC2 nodes use the **Amazon EKS-optimized AMI** which includes:
- A bootstrap VPC CNI plugin
- Kubelet configuration
- Container runtime

The node can join the cluster with this bootstrap CNI, then the VPC CNI addon's DaemonSet replaces it.

### For Fargate Profiles

Fargate profiles can be created without any addons:
- Fargate uses a different networking model (AWS-managed)
- The VPC CNI addon is still needed for Fargate, but can be installed after profiles exist
- Fargate pods use the VPC CNI for IP allocation

## Original Implementation Reference

From `modules/collections/ado-eks-cluster/main.tf`:

```hcl
# Fargate profiles created first
module "fargate_profile" {
  source = "../../primitive/fargate-profile"
  # ...
  depends_on = [
    module.eks_cluster,
    module.iam_roles
  ]
}

# ALL addons (including VPC CNI) created AFTER Fargate
resource "aws_eks_addon" "addons" {
  for_each = var.eks_addons

  cluster_name = module.eks_cluster.cluster_name
  addon_name   = each.key
  # ...
  
  depends_on = [
    module.fargate_profile_system,
    module.fargate_profile,
    module.eks_cluster
  ]
}
```

**This worked perfectly in the original implementation.**

## Current Implementation

Following the original approach in the refactored code:

```hcl
# Fargate Profiles - No addon dependencies
module "fargate_profile" {
  for_each = var.fargate_profiles
  source   = "../../modules/primitive/fargate-profile"

  # ...
  
  depends_on = [
    module.eks_cluster,
    module.iam_roles
  ]
}

# EC2 Node Groups - No addon dependencies
module "ec2_nodes" {
  source   = "../../modules/primitive/eks-node-group"
  for_each = var.ec2_node_group

  # ...
  # No depends_on for addons
}

# ALL Addons - Depend on compute resources
resource "aws_eks_addon" "addons" {
  for_each = var.eks_addons

  cluster_name = module.eks_cluster.cluster_name
  addon_name   = each.key
  # ...

  depends_on = [
    module.eks_cluster,
    module.ec2_nodes,
    module.fargate_profile
  ]
}
```

## Why the "Nodes Need VPC CNI First" Misconception

The confusion came from AWS documentation that states:
> "Amazon VPC CNI plugin is required for pod networking"

This is true, but what they mean is:
- Pods need the VPC CNI **plugin** (present in the AMI)
- NOT that the VPC CNI **addon must be registered first**

The addon is an **enhancement/management layer** over the existing bootstrap CNI.

## Troubleshooting: "CNI Plugin Not Initialized"

If you see:
```
container runtime network not ready: NetworkReady=false 
reason:NetworkPluginNotReady message:Network plugin returns error: 
cni plugin not initialized
```

**This is NOT because addons were installed in the wrong order.**

Common causes:
1. **IAM Permissions**: Node IAM role missing `AmazonEKS_CNI_Policy`
2. **Security Groups**: Nodes can't communicate with control plane
3. **Subnet Configuration**: Nodes in wrong subnets
4. **VPC Endpoints**: Missing required VPC endpoints in private subnets
5. **AMI Issues**: Using incorrect or outdated AMI

## Verification

After deployment, verify the order actually used:

```bash
# Check when resources were created
aws eks describe-cluster --name <cluster-name> --query 'cluster.createdAt'
aws eks describe-nodegroup --cluster-name <cluster-name> --nodegroup-name <ng-name> --query 'nodegroup.createdAt'
aws eks describe-addon --cluster-name <cluster-name> --addon-name vpc-cni --query 'addon.createdAt'
```

You should see:
1. Cluster created first
2. Node groups created second
3. Addons created last

## References

- Original working implementation: `modules/collections/ado-eks-cluster/main.tf`
- AWS EKS Best Practices: https://aws.github.io/aws-eks-best-practices/
- Amazon EKS User Guide - Add-ons: https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html

## Key Takeaway

**Don't overthink the addon order. Create compute resources first, then install all addons. This is how the original implementation worked, and it's the correct approach.**
