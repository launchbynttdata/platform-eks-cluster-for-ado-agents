# Terragrunt Configuration Reference

This document provides a complete reference for all configuration options available in `env.hcl`.

## Table of Contents

- [Global Settings](#global-settings)
- [Base Layer Configuration](#base-layer-configuration)
- [Networking Layer Configuration](#networking-layer-configuration)
- [Middleware Layer Configuration](#middleware-layer-configuration)
- [Application Layer Configuration](#application-layer-configuration)
- [Examples](#examples)

## Global Settings

```hcl
locals {
  environment  = "development"  # Environment name
  project_name = "eks-ado-agents"  # Project identifier
  aws_region   = "us-west-2"  # AWS region for all resources
  
  common_tags = {
    Environment = "development"
    Owner       = "platform-team"
    CostCenter  = "engineering"
  }
}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `environment` | string | Yes | Environment name (dev, staging, prod) |
| `project_name` | string | Yes | Project identifier used in resource naming |
| `aws_region` | string | Yes | AWS region where resources will be created |
| `common_tags` | map(string) | No | Tags applied to all resources |

## Base Layer Configuration

### EKS Cluster

```hcl
cluster_name                    = "ado-agent-cluster"
cluster_version                 = "1.35"
cluster_api_ready_wait_duration = "90s"
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `cluster_name` | string | Yes | Unique name for the EKS cluster |
| `cluster_version` | string | Yes | Kubernetes version |
| `cluster_api_ready_wait_duration` | string | No | Time to wait after EKS cluster creation before using Kubernetes/Helm providers |

### Networking

```hcl
vpc_id = "vpc-xxxxx"
subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
pod_networking_mode = "vpc-cni"

endpoint_public_access = true
public_access_cidrs    = ["203.0.113.0/24"]
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `vpc_id` | string | Yes | Existing VPC ID where EKS will be created |
| `subnet_ids` | list(string) | Yes | List of private subnet IDs (minimum 2) |
| `pod_networking_mode` | string | No | Pod CNI mode: `vpc-cni` or `cilium-overlay` |
| `endpoint_public_access` | bool | No | Enable public access to EKS API (default: false) |
| `public_access_cidrs` | list(string) | No | CIDR blocks allowed to access EKS API |

### IAM Configuration

```hcl
create_iam_roles = true
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `create_iam_roles` | bool | No | Create IAM roles for EKS (default: true) |

### KMS Encryption

```hcl
kms_key_description             = "EKS encryption key"
kms_key_deletion_window_in_days = 7
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `kms_key_description` | string | No | Description for KMS key |
| `kms_key_deletion_window_in_days` | number | No | Days before KMS key deletion (7-30) |

### Fargate Profiles

```hcl
fargate_profiles = {
  apps = {
    selectors = [
      {
        namespace = "keda-system"
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

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `fargate_profiles` | map(object) | No | Fargate profiles for pod scheduling |

Set to `{}` to disable Fargate entirely.

Fargate requires `pod_networking_mode = "vpc-cni"` and the `vpc-cni` EKS add-on.

### EKS Add-ons

```hcl
eks_addons = {
  "coredns" = {
    version = "v1.12.4-eksbuild.1"
  }
  "kube-proxy" = {
    version = "v1.33.3-eksbuild.6"
  }
  "vpc-cni" = {
    version = "v1.20.2-eksbuild.1"
  }
}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `eks_addons` | map(object) | Yes | EKS add-ons and versions |

**Available Add-ons:**

- `coredns` - DNS service
- `kube-proxy` - Network proxy
- `vpc-cni` - VPC networking
- `aws-ebs-csi-driver` - EBS volume support
- `aws-efs-csi-driver` - EFS volume support

When `pod_networking_mode = "cilium-overlay"`, remove `vpc-cni` from this map.

### VPC Endpoints

```hcl
create_vpc_endpoints = true
vpc_endpoint_services = [
  "s3",
  "ecr_dkr",
  "ecr_api",
  "ec2",
  "eks",
  "logs",
  "monitoring",
  "sts",
  "secretsmanager"
]
exclude_vpc_endpoint_services = []
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `create_vpc_endpoints` | bool | No | Create VPC endpoints (default: true) |
| `vpc_endpoint_services` | list(string) | No | List of AWS services for endpoints |
| `exclude_vpc_endpoint_services` | list(string) | No | Services to exclude |

### EC2 Node Groups

```hcl
ec2_node_groups = {
  "buildkit-nodes" = {
    instance_types = ["t3.medium", "t3.large"]
    disk_size      = 100
    ami_type       = "AL2023_x86_64_STANDARD"
    capacity_type  = "ON_DEMAND"
    desired_size   = 1
    max_size       = 5
    min_size       = 0
    labels = {
      "workload-type" = "buildkit"
    }
    taints = [
      {
        key    = "workload-type"
        value  = "buildkit"
        effect = "NoSchedule"
      }
    ]
  }
}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `ec2_node_groups` | map(object) | No | EC2 node groups for non-Fargate workloads |

Set to `{}` to use Fargate only.

Use `AL2023_x86_64_STANDARD` for Kubernetes 1.33 and newer node groups. `AL2_x86_64` is only valid for Kubernetes 1.32 and earlier.

## Networking Layer Configuration

The networking layer is a no-op when `pod_networking_mode = "vpc-cni"`. When `pod_networking_mode = "cilium-overlay"`, Cilium is bootstrapped by the base layer before EC2 managed node groups so kubelets have a CNI during startup. The networking layer validates that the configured mode matches the base layer output.

```hcl
pod_networking_mode = "cilium-overlay"

fargate_profiles = {}

eks_addons = {
  "coredns" = {
    version = "v1.14.2-eksbuild.4"
  }
  "kube-proxy" = {
    version = "v1.35.3-eksbuild.2"
  }
}

cilium_networking = {
  chart_version                   = "1.19.5"
  cluster_pool_ipv4_pod_cidr_list = ["100.64.0.0/10"]
  cluster_pool_ipv4_mask_size     = 24
  helm_values_override            = {}
}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `cilium_networking.chart_version` | string | No | Cilium Helm chart version |
| `cilium_networking.cluster_pool_ipv4_pod_cidr_list` | list(string) | No | Non-overlapping CIDR blocks Cilium uses for pod IPs |
| `cilium_networking.cluster_pool_ipv4_mask_size` | number | No | Per-node Cilium pod CIDR mask size |
| `cilium_networking.helm_values_override` | map/object | No | Advanced Helm values merged into the default Cilium overlay values |

`cilium-overlay` is EC2-only. It requires at least one EC2 node group and does not support Fargate profiles.

## Middleware Layer Configuration

### KEDA

```hcl
install_keda                         = true
keda_namespace                       = "keda-system"
keda_version                         = "2.17.2"
keda_enable_cloudeventsource         = false
keda_enable_cluster_cloudeventsource = false
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `install_keda` | bool | No | Install KEDA operator (default: true) |
| `keda_namespace` | string | No | Namespace for KEDA (default: keda-system) |
| `keda_version` | string | No | KEDA version to install |
| `keda_enable_cloudeventsource` | bool | No | Enable CloudEventSource controller |
| `keda_enable_cluster_cloudeventsource` | bool | No | Enable ClusterCloudEventSource controller |

### ADO Namespace

```hcl
ado_agents_namespace = "ado-agents"
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `ado_agents_namespace` | string | No | Namespace for ADO agents (default: ado-agents) |
| `ado_secret_name` | string | No | Name of ADO PAT Kubernetes secret (defaults to `ado_pat_secret_name` when omitted) |

### External Secrets Operator

```hcl
install_eso                = true
eso_namespace              = "external-secrets-system"
eso_version                = "1.3.2"
eso_webhook_enabled        = false
eso_webhook_failure_policy = "Ignore"
cluster_secret_store_name  = "aws-secrets-manager"
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `install_eso` | bool | No | Install External Secrets Operator (default: true) |
| `eso_namespace` | string | No | Namespace for ESO |
| `eso_version` | string | No | ESO version to install |
| `eso_webhook_enabled` | bool | No | Enable ESO webhook (incompatible with Fargate) |
| `eso_webhook_failure_policy` | string | No | Webhook failure policy (Ignore/Fail) |
| `cluster_secret_store_name` | string | No | Name for ClusterSecretStore resource |

### Buildkitd

```hcl
enable_buildkitd    = true
buildkitd_namespace = "buildkit-system"
buildkitd_image     = "moby/buildkit:v0.12.5"
buildkitd_replicas  = 2

buildkitd_node_selector = {
  "workload-type" = "buildkit"
}

buildkitd_tolerations = [
  {
    key      = "workload-type"
    operator = "Equal"
    value    = "buildkit"
    effect   = "NoSchedule"
  }
]

buildkitd_resources = {
  requests = {
    cpu    = "500m"
    memory = "1Gi"
  }
  limits = {
    cpu    = "2"
    memory = "4Gi"
  }
}

buildkitd_storage_size = "50Gi"
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `enable_buildkitd` | bool | No | Deploy buildkitd (default: true) |
| `buildkitd_namespace` | string | No | Namespace for buildkitd |
| `buildkitd_image` | string | No | Container image for buildkitd |
| `buildkitd_replicas` | number | No | Number of buildkitd replicas |
| `buildkitd_node_selector` | map(string) | No | Node selector for pod placement |
| `buildkitd_tolerations` | list(object) | No | Tolerations for pod scheduling |
| `buildkitd_resources` | object | No | Resource requests and limits |
| `buildkitd_storage_size` | string | No | Persistent volume size |

## Application Layer Configuration

### Azure DevOps

```hcl
ado_org             = "your-org"
ado_url             = "https://dev.azure.com/your-org"
ado_pat_secret_name = "ado-agent-pat"
secret_recovery_days = 7
secret_refresh_interval = "5m"
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `ado_org` | string | Yes | Azure DevOps organization name |
| `ado_url` | string | Yes | Azure DevOps organization URL |
| `ado_pat_secret_name` | string | No | AWS Secrets Manager secret name |
| `secret_recovery_days` | number | No | Days to recover deleted secret (7-30) |
| `secret_refresh_interval` | string | No | How often ESO syncs secret |

**Note:** ADO PAT value must be provided via environment variable:

```bash
export TF_VAR_ado_pat_value='your-personal-access-token'
```

### ECR Repositories

```hcl
ecr_repositories = {
  ado-agent = {
    image_tag_mutability = "IMMUTABLE"
    image_scanning_configuration = {
      scan_on_push = true
    }
    encryption_configuration = {
      encryption_type = "KMS"
      kms_key        = ""  # Uses cluster KMS key
    }
    lifecycle_policy_text = ""  # Uses default policy
  }
}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `ecr_repositories` | map(object) | No | ECR repositories for custom images |

### IAM Execution Roles

```hcl
ado_execution_roles = {
  ado-agent = {
    namespace            = "ado-agents"
    service_account_name = "ado-agent"
    permissions = [
      {
        effect = "Allow"
        actions = ["ecr:GetAuthorizationToken"]
        resources = ["*"]
      }
    ]
  }
}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `ado_execution_roles` | map(object) | No | IAM roles for agent service accounts |

### ADO Agent Pools

```hcl
ado_agent_pools = {
  default = {
    pool_name           = "EKS-ADO-Agents"
    service_account     = "ado-agent"
    image_repository    = ""  # Empty = public image
    image_tag           = "latest"
    min_replicas        = 1
    max_replicas        = 10
    polling_interval    = 30
    cooldown_period     = 300
    
    resources = {
      requests = {
        cpu    = "500m"
        memory = "2Gi"
      }
      limits = {
        cpu    = "2"
        memory = "4Gi"
      }
    }
    
    node_selector = {}
    tolerations   = []
  }
}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `ado_agent_pools` | map(object) | No | ADO agent pool configurations |

**Agent Pool Fields:**

- `pool_name` - ADO agent pool name
- `service_account` - Kubernetes service account
- `image_repository` - ECR repository URL (empty = use public image)
- `image_tag` - Container image tag
- `min_replicas` - Minimum number of agents
- `max_replicas` - Maximum number of agents
- `polling_interval` - KEDA polling interval (seconds)
- `cooldown_period` - Scale-down cooldown (seconds)
- `resources` - CPU/memory requests and limits
- `node_selector` - Node selection constraints
- `tolerations` - Pod tolerations

### Helm Configuration

```hcl
helm_chart_version = "0.1.0"
helm_values_override = {}
```

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `helm_chart_version` | string | No | Helm chart version |
| `helm_values_override` | map(any) | No | Additional Helm values |

## Examples

### Minimal Configuration

```hcl
locals {
  environment  = "dev"
  project_name = "eks-ado"
  aws_region   = "us-west-2"
  
  cluster_name = "dev-ado-cluster"
  cluster_version = "1.33"
  
  vpc_id = "vpc-xxxxx"
  subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
  
  ado_org = "my-org"
  ado_url = "https://dev.azure.com/my-org"
  
  fargate_profiles = {}  # No Fargate
  ec2_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      desired_size = 2
      max_size = 5
      min_size = 1
    }
  }
}
```

### Production Configuration

```hcl
locals {
  environment  = "production"
  project_name = "eks-ado-agents"
  aws_region   = "us-east-1"
  
  cluster_name = "prod-ado-agents"
  cluster_version = "1.33"
  
  vpc_id = "vpc-xxxxx"
  subnet_ids = ["subnet-xxxxx", "subnet-yyyyy", "subnet-zzzzz"]
  
  endpoint_public_access = false
  public_access_cidrs = ["10.0.0.0/8"]
  
  fargate_profiles = {
    apps = {
      selectors = [
        { namespace = "keda-system" },
        { namespace = "external-secrets-system" },
        { namespace = "ado-agents" }
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
  
  ado_agent_pools = {
    default = {
      pool_name = "Production-Agents"
      max_replicas = 20
      resources = {
        requests = { cpu = "1000m", memory = "4Gi" }
        limits = { cpu = "4", memory = "8Gi" }
      }
    }
    iac = {
      pool_name = "Production-IaC-Agents"
      max_replicas = 10
      resources = {
        requests = { cpu = "2000m", memory = "8Gi" }
        limits = { cpu = "8", memory = "16Gi" }
      }
    }
  }
  
  common_tags = {
    Environment = "production"
    Compliance = "PCI"
    DataClassification = "confidential"
  }
}
```

### Multi-Region Setup

```hcl
# env.us-east-1.hcl
locals {
  aws_region = "us-east-1"
  cluster_name = "ado-agents-us-east-1"
  vpc_id = "vpc-xxxxx"
  subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
  # ... rest of config
}

# env.us-west-2.hcl
locals {
  aws_region = "us-west-2"
  cluster_name = "ado-agents-us-west-2"
  vpc_id = "vpc-yyyyy"
  subnet_ids = ["subnet-zzzzz", "subnet-aaaaa"]
  # ... rest of config
}
```

### Cost-Optimized Configuration

```hcl
locals {
  fargate_profiles = {}  # Disable Fargate
  
  ec2_node_groups = {
    spot = {
      instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
      capacity_type = "SPOT"
      desired_size = 1
      max_size = 10
      min_size = 0
    }
  }
  
  buildkitd_replicas = 1
  buildkitd_resources = {
    requests = { cpu = "250m", memory = "512Mi" }
    limits = { cpu = "1", memory = "2Gi" }
  }
}
```
