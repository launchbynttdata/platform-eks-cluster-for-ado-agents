# Base Infrastructure Layer Configuration
#
# Copy this file to terraform.tfvars and customize the values for your environment.
# Required values are marked with comments.

# AWS Configuration
aws_region = "us-west-2"

# Cluster Configuration (REQUIRED)
cluster_name    = "poc-ado-agent-cluster" # Must be unique in your AWS account
cluster_version = "1.33"

# Networking Configuration (REQUIRED)
# These values must be provided - no defaults
vpc_id = "vpc-0555ff8949bb6bb4e" # Replace with your VPC ID
subnet_ids = [                   # Replace with your private subnet IDs (minimum 2)
  "subnet-08767b1e9b7e08959",
  "subnet-0eaf172a0157206f6"
]

# Security Configuration
endpoint_public_access = true               # Keep false for production
public_access_cidrs    = ["136.226.0.0/16"] # Restrict to your VPC CIDR

# IAM Configuration
create_iam_roles = true # Set to false if using existing roles

# KMS Configuration
create_kms_key                  = true
kms_key_description             = "EKS Cluster encryption key for ado-agent-cluster"
kms_key_deletion_window_in_days = 7

# Fargate Configuration
# Map of Fargate profiles to create
# Set to {} to disable Fargate entirely and use only EC2 node groups
fargate_profiles = {
  # Uncomment to enable Fargate for applications
  # apps = {
  #   selectors = [
  #     {
  #       namespace = "keda-system"
  #       labels    = {}
  #     },
  #     {
  #       namespace = "external-secrets"
  #       labels    = {}
  #     },
  #     {
  #       namespace = "ado-agents"
  #       labels    = {}
  #     }
  #   ]
  # }
  # Uncomment to enable Fargate for system components (CoreDNS)
  # system = {
  #   selectors = [
  #     {
  #       namespace = "kube-system"
  #       labels = {
  #         "k8s-app" = "kube-dns"
  #       }
  #     }
  #   ]
  # }
}

# EKS Add-ons
# These addons are independent of the compute configuration (Fargate or EC2)
# They will automatically schedule on available compute resources
#
# Note: If using Fargate for CoreDNS, you MUST create a Fargate profile
# with selector matching namespace=kube-system and labels={k8s-app=kube-dns}
# The addon itself doesn't need special configuration - it will detect
# and use Fargate automatically when the profile exists.
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

# VPC Endpoints
create_vpc_endpoints = true
vpc_endpoint_services = [
  "s3",
  "ecr_dkr",
  "ecr_api",
  "ec2",
  "logs",
  "monitoring",
  "sts",
  "secretsmanager"
]

# Exclude conflicting VPC endpoints if they already exist
exclude_vpc_endpoint_services = []

# EC2 Node Groups (optional - leave empty if using only Fargate)
ec2_node_group = {
  # Uncomment to enable EC2 nodes for workloads that can't run on Fargate
  # "buildkit-nodes" = {
  #   instance_types = ["t3.medium", "t3.large"]
  #   disk_size      = 100
  #   ami_type       = "AL2_x86_64"
  #   capacity_type  = "ON_DEMAND"
  #   desired_size   = 1
  #   max_size       = 5
  #   min_size       = 0
  #   labels = {
  #     "workload-type" = "buildkit"
  #   }
  #   taints = [
  #     {
  #       key    = "workload-type"
  #       value  = "buildkit"
  #       effect = "NO_SCHEDULE"
  #     }
  #   ]
  # }
  "system-nodes" = {
    instance_types = ["t3a.medium"]
    disk_size      = 50
    ami_type       = "AL2023_x86_64_STANDARD"
    capacity_type  = "ON_DEMAND"
    desired_size   = 1
    max_size       = 3
    min_size       = 0
    labels = {
      "workload-type" = "system"
    }
    taints = []
  },
  "buildkit-nodes" = {
    instance_types = ["c6a.xlarge"]
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
      { key = "node-role.kubernetes.io/buildkit", value = "true", effect = "NO_SCHEDULE" }
    ]
  },
  "agent-nodes" = {
    instance_types = ["t3a.medium"]
    disk_size      = 50
    ami_type       = "AL2023_x86_64_STANDARD"
    capacity_type  = "ON_DEMAND"
    desired_size   = 1
    max_size       = 10
    min_size       = 1
    labels = {
      "workload-type" = "agent"
    }
    taints = [
      { key = "node-role.kubernetes.io/ado-agent", value = "true", effect = "NO_SCHEDULE" }
    ]
  }
}

# Cluster Autoscaler (enable if using EC2 node groups)
enable_cluster_autoscaler    = true
cluster_autoscaler_namespace = "kube-system"

# Tagging
environment = "dev"
project     = "ado-agent-cluster"

tags = {
  "ProjectId"   = "MVITMR"
  "Environment" = "dev"
  "Owner"       = "platform-team"
  "CostCenter"  = "engineering"
  "ManagedBy"   = "terraform"
  "Layer"       = "base-infrastructure"
}