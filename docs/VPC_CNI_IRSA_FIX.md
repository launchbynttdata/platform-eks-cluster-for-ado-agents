# VPC CNI IRSA Configuration Fix

## Problem

When EC2 nodes attempted to join the EKS cluster, they failed with:

```
container runtime network not ready: NetworkReady=false 
reason:NetworkPluginNotReady 
message:Network plugin returns error: cni plugin not initialized
```

## Root Cause

1. **Missing IRSA Configuration**: The VPC CNI addon requires IAM Roles for Service Accounts (IRSA) with the `AmazonEKS_CNI_Policy` managed policy when using EC2 nodes
2. **Incorrect Deployment Order**: The VPC CNI addon must be deployed BEFORE compute resources (EC2 nodes/Fargate profiles) attempt to join the cluster

The original Fargate-only implementation worked without IRSA because:
- Fargate has built-in VPC CNI support with automatic IAM handling
- EC2 nodes require explicit IRSA configuration for the VPC CNI service account

## Solution

### 1. IRSA Role for VPC CNI

Created a dedicated IAM role for the VPC CNI service account (`system:serviceaccount:kube-system:aws-node`):

```hcl
# IAM Role for VPC CNI using IRSA
resource "aws_iam_role" "vpc_cni_irsa" {
  count = var.create_iam_roles ? 1 : 0

  name = "${local.cluster_name}-vpc-cni-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for VPC CNI
resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  count = var.create_iam_roles ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_irsa[0].name
}
```

### 2. Separate VPC CNI Addon Deployment

Split the VPC CNI addon into its own resource that deploys BEFORE compute resources:

```hcl
# VPC CNI Addon (deployed before compute resources)
resource "aws_eks_addon" "vpc_cni" {
  count = contains(keys(var.eks_addons), "vpc-cni") ? 1 : 0

  cluster_name             = module.eks_cluster.cluster_name
  addon_name               = "vpc-cni"
  addon_version            = try(var.eks_addons["vpc-cni"].addon_version, null)
  service_account_role_arn = var.create_iam_roles ? aws_iam_role.vpc_cni_irsa[0].arn : null
  resolve_conflicts_on_create = try(var.eks_addons["vpc-cni"].resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(var.eks_addons["vpc-cni"].resolve_conflicts_on_update, "OVERWRITE")

  depends_on = [
    module.eks_cluster,
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.vpc_cni_policy
  ]

  tags = local.common_tags
}
```

### 3. Updated Deployment Order

The correct deployment sequence is now:

```
1. EKS Cluster + OIDC Provider
2. VPC CNI IRSA Role + Policy Attachment
3. VPC CNI Addon (with IRSA)
4. Compute Resources (EC2 Nodes / Fargate Profiles)
5. Other Addons (CoreDNS, kube-proxy, etc.)
```

### 4. Compute Resources Wait for VPC CNI

Both EC2 nodes and Fargate profiles now explicitly depend on the VPC CNI addon:

**EC2 Nodes:**
```hcl
module "ec2_nodes" {
  # ... configuration ...
  
  depends_on = [
    module.eks_cluster,
    aws_eks_addon.vpc_cni,
    aws_iam_role.ec2_node_group_role
  ]
}
```

**Fargate Profiles:**
```hcl
module "fargate_profile" {
  # ... configuration ...
  
  depends_on = [
    module.eks_cluster,
    module.iam_roles,
    aws_eks_addon.vpc_cni
  ]
}
```

### 5. Other Addons Filter Out VPC CNI

The remaining addons resource now excludes vpc-cni since it's handled separately:

```hcl
# EKS Addons (excluding VPC CNI which is installed earlier)
resource "aws_eks_addon" "addons" {
  for_each = { for k, v in var.eks_addons : k => v if k != "vpc-cni" }
  
  # ... configuration ...
  
  depends_on = [
    module.eks_cluster,
    module.ec2_nodes,
    module.fargate_profile
  ]
}
```

## Why This Fix Works

1. **IRSA Permissions**: The VPC CNI pods running on EC2 nodes now have the necessary IAM permissions to manage ENIs and IP addresses via the IRSA role
2. **Proper Initialization**: The VPC CNI is fully configured and ready before any nodes attempt to join
3. **Clean Dependencies**: The dependency chain ensures resources are created in the correct order
4. **Separation of Concerns**: VPC CNI (critical for node networking) is handled separately from application-level addons

## Comparison to Original Implementation

| Aspect | Original (Fargate-only) | Updated (EC2 + Fargate) |
|--------|------------------------|-------------------------|
| VPC CNI IRSA | Not required | **Required** with AmazonEKS_CNI_Policy |
| Addon Deployment | All addons after Fargate | VPC CNI before compute, others after |
| Dependency Order | Simple: Cluster → Fargate → Addons | Complex: Cluster → VPC CNI → Compute → Addons |
| Node Join Success | Automatic (Fargate managed) | Requires explicit VPC CNI with IRSA |

## Testing

To verify the fix:

1. Deploy the base layer:
   ```bash
   cd infrastructure-layered/base
   terraform init
   terraform plan
   terraform apply
   ```

2. Verify VPC CNI addon is active:
   ```bash
   aws eks describe-addon \
     --cluster-name <cluster-name> \
     --addon-name vpc-cni \
     --query 'addon.status'
   ```

3. Check that EC2 nodes join successfully:
   ```bash
   kubectl get nodes
   ```

4. Verify VPC CNI pods are running:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=aws-node
   ```

## References

- [AWS VPC CNI Plugin](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)
- [EKS IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AmazonEKS_CNI_Policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEKS_CNI_Policy.html)
