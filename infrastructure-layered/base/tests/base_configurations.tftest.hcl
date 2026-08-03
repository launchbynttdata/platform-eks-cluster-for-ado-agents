# Credential-free base configuration plan tests.
# Run from the base layer root after copying ci/static-provider.tf:
#   terraform init -backend=false
#   terraform test -test-directory=tests

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:root"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-west-2"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      id         = "vpc-0123456789abcdef0"
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_data "aws_route_tables" {
    defaults = {
      ids = ["rtb-0123456789abcdef0", "rtb-0fedcba9876543210"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }
}

mock_provider "time" {}

override_module {
  target = module.cluster_security_group
  outputs = {
    id  = "sg-0123456789abcdef0"
    arn = "arn:aws:ec2:us-west-2:123456789012:security-group/sg-0123456789abcdef0"
  }
}

override_module {
  target = module.fargate_security_group
  outputs = {
    id  = "sg-0fedcba9876543210"
    arn = "arn:aws:ec2:us-west-2:123456789012:security-group/sg-0fedcba9876543210"
  }
}

variables {
  cluster_name                    = "mock-cluster"
  vpc_id                          = "vpc-0123456789abcdef0"
  subnet_ids                      = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  aws_region                      = "us-west-2"
  cluster_api_ready_wait_duration = "0s"
}

run "default_vpc_cni_platform" {
  command = plan

  variables {
    enable_cluster_autoscaler = true
    enable_node_auto_heal     = true
    node_auto_heal_enable_dlq = true
    ec2_node_group = {
      workers = {}
    }
  }

  assert {
    condition     = length(module.eks_cluster_role) == 1
    error_message = "Generated EKS cluster role should be planned when create_iam_roles is true"
  }

  assert {
    condition     = length(module.vpc_endpoints) == 1
    error_message = "VPC endpoints should be planned when create_vpc_endpoints is true"
  }

  assert {
    condition     = length(module.fargate_profile) == 2
    error_message = "Default Fargate profiles (apps and system) should be planned"
  }

  assert {
    condition     = length(module.ec2_nodes) == 1
    error_message = "EC2 node group should be planned when configured"
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 1
    error_message = "VPC-CNI addon should be planned in vpc-cni mode"
  }

  assert {
    condition     = length(module.cluster_autoscaler_role) == 1
    error_message = "Cluster autoscaler IAM role should be planned when enabled"
  }

  assert {
    condition     = length(aws_sqs_queue.node_auto_heal_dlq) == 1
    error_message = "Node auto-heal DLQ should be planned when DLQ is enabled"
  }
}

run "minimal_external_role_platform" {
  command = plan

  variables {
    create_iam_roles          = false
    create_vpc_endpoints      = false
    enable_cluster_autoscaler = false
    enable_node_auto_heal     = false
    fargate_profiles          = {}
    ec2_node_group            = {}
    existing_cluster_role_arn = "arn:aws:iam::123456789012:role/existing-cluster"
    existing_fargate_role_arn = "arn:aws:iam::123456789012:role/existing-fargate"
  }

  assert {
    condition     = length(module.eks_cluster_role) == 0
    error_message = "Generated cluster role should be absent when create_iam_roles is false"
  }

  assert {
    condition     = length(module.fargate_pod_execution_role) == 0
    error_message = "Generated Fargate role should be absent when create_iam_roles is false"
  }

  assert {
    condition     = length(module.vpc_endpoints) == 0
    error_message = "VPC endpoints should be absent when create_vpc_endpoints is false"
  }

  assert {
    condition     = length(module.fargate_profile) == 0
    error_message = "Fargate profiles should be absent when fargate_profiles is empty"
  }

  assert {
    condition     = length(module.ec2_nodes) == 0
    error_message = "EC2 node groups should be absent when ec2_node_group is empty"
  }

  assert {
    condition     = length(module.cluster_autoscaler_role) == 0
    error_message = "Cluster autoscaler should be absent when disabled"
  }

  assert {
    condition     = length(aws_sqs_queue.node_auto_heal) == 0
    error_message = "Node auto-heal queue should be absent when disabled"
  }
}

run "cilium_overlay_platform" {
  command = plan

  variables {
    pod_networking_mode = "cilium-overlay"
    fargate_profiles    = {}
    ec2_node_group = {
      workers = {}
    }
    eks_addons = {
      coredns = {
        version = "v1.14.2-eksbuild.4"
      }
      kube-proxy = {
        version = "v1.35.3-eksbuild.2"
      }
    }
  }

  assert {
    condition     = length(terraform_data.cilium_bootstrap) == 1
    error_message = "Cilium bootstrap should be planned in cilium-overlay mode"
  }

  assert {
    condition     = length(terraform_data.cilium_bootstrap_cleanup) == 1
    error_message = "Cilium bootstrap cleanup should be planned in cilium-overlay mode"
  }

  assert {
    condition     = length(terraform_data.disable_aws_node_daemonset) == 1
    error_message = "aws-node disable hook should be planned in cilium-overlay mode"
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 0
    error_message = "VPC-CNI addon should be absent in cilium-overlay mode"
  }

  assert {
    condition     = length(module.vpc_cni_irsa_role) == 0
    error_message = "VPC-CNI IRSA role should be absent in cilium-overlay mode"
  }

  assert {
    condition     = length(module.fargate_profile) == 0
    error_message = "Fargate profiles should be absent in cilium-overlay mode"
  }
}

run "node_auto_heal_without_dlq" {
  command = plan

  variables {
    enable_node_auto_heal     = true
    node_auto_heal_enable_dlq = false
    fargate_profiles          = {}
    ec2_node_group            = {}
  }

  assert {
    condition     = length(aws_sqs_queue.node_auto_heal) == 1
    error_message = "Node auto-heal queue should be planned when enabled"
  }

  assert {
    condition     = length(aws_sqs_queue.node_auto_heal_dlq) == 0
    error_message = "Node auto-heal DLQ should be absent when node_auto_heal_enable_dlq is false"
  }

  assert {
    condition     = length(module.node_auto_heal_role) == 1
    error_message = "Node auto-heal IRSA role should be planned when enabled"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.node_auto_heal) == 4
    error_message = "All node auto-heal EventBridge rules should be planned when enabled"
  }
}

run "addon_access_variation" {
  command = plan

  variables {
    cluster_admin_access_principal_arns = [
      "arn:aws:iam::123456789012:role/cluster-admin-a",
      "arn:aws:iam::123456789012:role/cluster-admin-b",
    ]
    eks_addons = {
      coredns = {
        version = "v1.14.2-eksbuild.4"
      }
      kube-proxy = {
        version = "v1.35.3-eksbuild.2"
      }
      vpc-cni = {
        version = "v1.21.1-eksbuild.8"
      }
      "amazon-cloudwatch-observability" = {
        version = "v4.5.0-eksbuild.1"
      }
    }
    fargate_profiles = {}
    ec2_node_group   = {}
  }

  assert {
    condition     = length(aws_eks_access_entry.cluster_admin) == 2
    error_message = "Cluster admin access entries should match principal ARN inputs"
  }

  assert {
    condition     = length(aws_eks_access_policy_association.cluster_admin) == 2
    error_message = "Cluster admin policy associations should match principal ARN inputs"
  }

  assert {
    condition     = length(aws_eks_addon.addons) == 3
    error_message = "Non-VPC-CNI addons should be planned separately from the VPC-CNI addon"
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 1
    error_message = "VPC-CNI addon should still be planned when present in eks_addons"
  }
}
