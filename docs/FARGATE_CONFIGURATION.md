# Fargate Profile Configuration Guide

## Overview

The base infrastructure layer supports flexible Fargate profile configuration using a map-based approach. This allows you to:

- Create **zero or more** Fargate profiles
- Define **multiple namespace selectors** per profile
- Use **label-based selectors** for fine-grained pod placement
- Easily enable/disable Fargate entirely

## Configuration Structure

Fargate profiles are configured using the `fargate_profiles` variable in `terraform.tfvars`:

```hcl
fargate_profiles = {
  profile_name = {
    selectors = [
      {
        namespace = "namespace-name"
        labels    = {}  # Optional label selectors
      }
    ]
  }
}
```

### Key Points

- **Profile Name**: The map key becomes part of the Fargate profile name: `${cluster_name}-${profile_name}-fargate-profile`
- **Selectors**: Each profile can have multiple selectors targeting different namespaces or labels
- **Empty Map**: Set `fargate_profiles = {}` to disable Fargate entirely and use only EC2 node groups
- **Independent Addons**: EKS addons (CoreDNS, kube-proxy, VPC CNI) are **independent** of Fargate configuration. They will automatically schedule on whatever compute is available (Fargate or EC2)

### EKS Addons and Fargate

**Important**: EKS managed addons do **not** have a dependency on Fargate profiles. The addons are deployed as soon as the cluster is ready and will automatically:

- Schedule on **Fargate** if a matching Fargate profile exists
- Schedule on **EC2 nodes** if node groups are available
- Use **node selectors and tolerations** to find available compute

For CoreDNS specifically:
- If you want CoreDNS to run on Fargate, create a profile with `namespace: kube-system` and `labels: {k8s-app: kube-dns}`
- If you want CoreDNS to run on EC2, simply create node groups - no special addon configuration needed
- CoreDNS will automatically detect and use the available compute layer

## Common Configuration Examples

### Example 1: No Fargate (EC2 Node Groups Only)

```hcl
fargate_profiles = {}
```

This creates **no Fargate profiles**. All workloads will run on EC2 node groups.

### Example 2: Single Profile for All Application Workloads

```hcl
fargate_profiles = {
  apps = {
    selectors = [
      {
        namespace = "keda-system"
        labels    = {}
      },
      {
        namespace = "external-secrets"
        labels    = {}
      },
      {
        namespace = "ado-agents"
        labels    = {}
      }
    ]
  }
}
```

Creates **one Fargate profile** that handles three namespaces.

### Example 3: Separate Profiles for System and Apps

```hcl
fargate_profiles = {
  system = {
    selectors = [
      {
        namespace = "kube-system"
        labels = {
          "k8s-app" = "kube-dns"
        }
      }
    ]
  }
  apps = {
    selectors = [
      {
        namespace = "keda-system"
        labels    = {}
      },
      {
        namespace = "external-secrets"
        labels    = {}
      },
      {
        namespace = "ado-agents"
        labels    = {}
      }
    ]
  }
}
```

Creates **two Fargate profiles**:
1. `system` profile for CoreDNS (with label selector)
2. `apps` profile for application workloads

### Example 4: Per-Namespace Profiles

```hcl
fargate_profiles = {
  keda = {
    selectors = [
      {
        namespace = "keda-system"
        labels    = {}
      }
    ]
  }
  eso = {
    selectors = [
      {
        namespace = "external-secrets"
        labels    = {}
      }
    ]
  }
  agents = {
    selectors = [
      {
        namespace = "ado-agents"
        labels    = {}
      }
    ]
  }
}
```

Creates **three separate Fargate profiles**, one per namespace. This provides maximum isolation but creates more AWS resources.

## Label-Based Selectors

Use label selectors to target specific pods within a namespace:

```hcl
fargate_profiles = {
  critical = {
    selectors = [
      {
        namespace = "production"
        labels = {
          "tier"     = "critical"
          "fargate"  = "enabled"
        }
      }
    ]
  }
}
```

Pods in the `production` namespace will only run on Fargate if they have **all** the specified labels.

## Mixed Fargate and EC2 Architecture

You can run some workloads on Fargate and others on EC2 node groups. The EKS addons will automatically distribute across available compute.

### Example: System on Fargate, Apps on EC2

```hcl
# Fargate for system components (CoreDNS, KEDA, ESO)
fargate_profiles = {
  system = {
    selectors = [
      {
        namespace = "kube-system"
        labels = {
          "k8s-app" = "kube-dns"
        }
      }
    ]
  }
  operators = {
    selectors = [
      {
        namespace = "keda-system"
        labels    = {}
      },
      {
        namespace = "external-secrets"
        labels    = {}
      }
    ]
  }
}

# EC2 for buildkit and agents (requires privileged access)
ec2_node_group = {
  buildkit-nodes = {
    instance_types = ["t3.medium"]
    disk_size      = 100
    desired_size   = 1
    max_size       = 5
    min_size       = 0
    labels = {
      "workload-type" = "buildkit"
    }
    taints = [
      {
        key    = "dedicated"
        value  = "buildkit"
        effect = "NoSchedule"
      }
    ]
  }
  agent-nodes = {
    instance_types = ["t3.large"]
    desired_size   = 2
    max_size       = 10
    min_size       = 1
    labels = {
      "workload-type" = "ado-agents"
    }
  }
}

# EKS Addons - automatically schedule on available compute
# CoreDNS → Fargate (system profile matches kube-system)
# kube-proxy → Both Fargate and EC2 (runs as DaemonSet)
# vpc-cni → Both Fargate and EC2 (runs as DaemonSet)
eks_addons = {
  "coredns" = {
    version = "v1.11.1-eksbuild.9"
  }
  "kube-proxy" = {
    version = "v1.33.0-eksbuild.1"
  }
  "vpc-cni" = {
    version = "v1.18.3-eksbuild.1"
  }
}
```

**Result**: 
- CoreDNS pods run on Fargate (matches system profile)
- kube-proxy and vpc-cni DaemonSets run on both Fargate pods and EC2 nodes
- KEDA and External Secrets Operator run on Fargate (operators profile)
- Buildkit and ADO agents run on EC2 nodes (require privileged containers)

### Example: All EC2, No Fargate

```hcl
# No Fargate profiles
fargate_profiles = {}

# All workloads on EC2
ec2_node_group = {
  default = {
    instance_types = ["t3.medium"]
    desired_size   = 2
    max_size       = 10
    min_size       = 1
  }
}

# EKS Addons - all run on EC2 nodes
eks_addons = {
  "coredns" = {
    version = "v1.11.1-eksbuild.9"
  }
  "kube-proxy" = {
    version = "v1.33.0-eksbuild.1"
  }
  "vpc-cni" = {
    version = "v1.18.3-eksbuild.1"
  }
}
```

**Result**: Everything runs on EC2 nodes, including all system components.

## Best Practices

### 1. **Minimize Number of Profiles**

Each Fargate profile creates additional AWS resources and has quotas. Combine related workloads into a single profile when possible.

✅ **Good**: One `apps` profile with multiple namespace selectors
❌ **Avoid**: Separate profile for each namespace

### 2. **Use System Profile for CoreDNS**

CoreDNS requires specific label matching for Fargate:

```hcl
system = {
  selectors = [
    {
      namespace = "kube-system"
      labels = {
        "k8s-app" = "kube-dns"
      }
    }
  ]
}
```

### 3. **Consider Subnet Availability**

- Fargate profiles require subnets in **different availability zones**
- Verify your VPC has subnets across multiple AZs before enabling Fargate
- Check: `aws ec2 describe-subnets --subnet-ids <id1> <id2> --query 'Subnets[*].AvailabilityZone'`

### 4. **Disable Fargate for Single-AZ VPCs**

If your VPC only has subnets in one availability zone, you **must** use EC2 node groups:

```hcl
fargate_profiles = {}

ec2_node_group = {
  default = {
    instance_types = ["t3.medium"]
    desired_size   = 2
    max_size       = 5
    min_size       = 1
  }
}
```

## Troubleshooting

### Error: "Insufficient selector blocks"

**Cause**: A Fargate profile is defined with an empty `selectors` list.

**Solution**: Either remove the profile entirely or add at least one selector:

```hcl
# Wrong
fargate_profiles = {
  apps = {
    selectors = []  # ❌ Empty list causes error
  }
}

# Right
fargate_profiles = {}  # ✅ No profiles at all - OK
# OR
fargate_profiles = {
  apps = {
    selectors = [
      {
        namespace = "my-app"
        labels    = {}
      }
    ]
  }
}
```

### Error: "DuplicateSubnetsInSameZone"

**Cause**: Both subnets specified are in the same availability zone. Fargate requires subnets in different AZs.

**Solution**: Either:
1. Update `subnet_ids` to include subnets from different AZs
2. Disable Fargate and use EC2 node groups: `fargate_profiles = {}`

### CoreDNS Not Starting

**Cause**: CoreDNS pods require Fargate profile with specific label selector.

**Solution**: Ensure you have a profile matching CoreDNS:

```hcl
fargate_profiles = {
  system = {
    selectors = [
      {
        namespace = "kube-system"
        labels = {
          "k8s-app" = "kube-dns"  # Required for CoreDNS
        }
      }
    ]
  }
}
```

## Migration Guide

### From Old Variable Structure

The old structure used two separate list variables:

```hcl
# OLD (deprecated)
fargate_profile_selectors = [
  { namespace = "keda-system" },
  { namespace = "external-secrets" }
]

fargate_system_profile_selectors = [
  {
    namespace = "kube-system"
    labels = { "k8s-app" = "kube-dns" }
  }
]
```

Migrate to the new map-based structure:

```hcl
# NEW
fargate_profiles = {
  apps = {
    selectors = [
      { namespace = "keda-system", labels = {} },
      { namespace = "external-secrets", labels = {} }
    ]
  }
  system = {
    selectors = [
      {
        namespace = "kube-system"
        labels = { "k8s-app" = "kube-dns" }
      }
    ]
  }
}
```

## See Also

- [EKS Fargate Documentation](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
- [Fargate Pod Configuration](https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-configuration.html)
- [EC2 Node Groups Configuration](./EC2_NODE_GROUPS.md)
