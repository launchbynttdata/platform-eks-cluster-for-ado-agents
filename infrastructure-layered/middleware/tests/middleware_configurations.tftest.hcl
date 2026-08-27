# Credential-free middleware configuration plan tests.
# Run from the middleware layer root after copying ci/static-provider.tf:
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

  mock_data "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "kubernetes" {}

mock_provider "helm" {}

mock_provider "time" {}

variables {
  remote_state_bucket                = "test-bucket"
  remote_state_region                = "us-west-2"
  remote_state_environment           = "test"
  aws_region                         = "us-west-2"
  application_crd_ready_wait_seconds = 0
}

override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      cluster_name                   = "mock-cluster"
      cluster_oidc_issuer_url        = "https://oidc.eks.us-west-2.amazonaws.com/id/MOCK"
      oidc_provider_arn              = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/MOCK"
      kms_key_arn                    = "arn:aws:kms:us-west-2:123456789012:key/mock"
      common_tags                    = { Project = "mock", Environment = "test" }
      ec2_node_group_role_name       = "mock-node-group-role"
      cluster_autoscaler_role_arn    = "arn:aws:iam::123456789012:role/mock-cluster-autoscaler"
      cluster_autoscaler_namespace   = "kube-system"
      cluster_autoscaler_version     = "v1.31.0"
      cluster_autoscaler_extra_args  = {}
      node_auto_heal_enabled         = true
      node_auto_heal_role_arn        = "arn:aws:iam::123456789012:role/mock-node-auto-heal"
      node_auto_heal_queue_url       = "https://sqs.us-west-2.amazonaws.com/123456789012/mock-queue"
      node_auto_heal_namespace       = "kube-system"
      node_auto_heal_service_account = "aws-node-termination-handler"
      pod_networking_mode            = "vpc-cni"
    }
  }
}

run "feature_rich_baseline" {
  command = plan

  variables {
    install_keda                                       = true
    install_eso                                        = true
    install_metrics_server                             = true
    enable_cloudwatch_observability                    = true
    enable_cloudwatch_observability_addon              = true
    enable_fargate_cloudwatch_logging                  = true
    enable_buildkitd                                   = true
    enable_ecr_pull_through_cache                      = true
    create_ecr_pull_through_cache_repository_templates = true
    buildkitd_hpa_enabled                              = true
    buildkitd_pdb_enabled                              = true
    buildkitd_recycle = {
      enabled  = true
      schedule = "0 2 * * 0"
      timezone = "America/Los_Angeles"
    }
    buildkitd_node_keyring_limits = {
      enabled   = true
      max_keys  = 20000
      max_bytes = 25000000
    }
    ecr_pull_through_cache_rules = {
      ecr-public = {
        upstream_registry_url = "public.ecr.aws"
      }
    }
  }

  assert {
    condition     = length(module.keda_operator) == 1
    error_message = "KEDA operator should be planned when install_keda is true"
  }

  assert {
    condition     = module.keda_operator[0].use_host_network_for_control_plane_reachability == false
    error_message = "KEDA should not use hostNetwork when pod_networking_mode is vpc-cni"
  }

  assert {
    condition     = length(module.external_secrets_operator) == 1
    error_message = "ESO should be planned when install_eso is true"
  }

  assert {
    condition     = length(module.metrics_server) == 1
    error_message = "Metrics server should be planned when install_metrics_server is true"
  }

  assert {
    condition     = length(module.cluster_autoscaler) == 1
    error_message = "Cluster autoscaler should be planned when base outputs include its role ARN"
  }

  assert {
    condition     = length(module.node_termination_handler) == 1
    error_message = "Node auto-heal should be planned when base outputs enable it"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.platform) > 0
    error_message = "CloudWatch platform log groups should be planned when observability is enabled"
  }

  assert {
    condition     = length(aws_ecr_pull_through_cache_rule.cache) > 0
    error_message = "ECR pull-through cache rules should be planned when enabled"
  }

  assert {
    condition     = length(kubernetes_manifest.buildkitd) == 1
    error_message = "BuildKit manifest should be planned when enable_buildkitd is true"
  }
}

run "minimal_middleware" {
  command = plan

  override_data {
    target = data.terraform_remote_state.base
    values = {
      outputs = {
        cluster_name                   = "mock-cluster"
        cluster_oidc_issuer_url        = "https://oidc.eks.us-west-2.amazonaws.com/id/MOCK"
        oidc_provider_arn              = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/MOCK"
        kms_key_arn                    = "arn:aws:kms:us-west-2:123456789012:key/mock"
        common_tags                    = { Project = "mock", Environment = "test" }
        ec2_node_group_role_name       = null
        cluster_autoscaler_role_arn    = null
        cluster_autoscaler_namespace   = "kube-system"
        cluster_autoscaler_version     = "v1.31.0"
        cluster_autoscaler_extra_args  = {}
        node_auto_heal_enabled         = false
        node_auto_heal_role_arn        = null
        node_auto_heal_queue_url       = null
        node_auto_heal_namespace       = "kube-system"
        node_auto_heal_service_account = "aws-node-termination-handler"
      }
    }
  }

  variables {
    install_keda                       = false
    install_eso                        = false
    install_metrics_server             = false
    enable_cloudwatch_observability    = false
    enable_buildkitd                   = false
    enable_ecr_pull_through_cache      = false
    application_crd_ready_wait_seconds = 0
  }

  assert {
    condition     = length(module.keda_operator) == 0
    error_message = "KEDA operator should be absent when install_keda is false"
  }

  assert {
    condition     = length(module.external_secrets_operator) == 0
    error_message = "ESO should be absent when install_eso is false"
  }

  assert {
    condition     = length(module.metrics_server) == 0
    error_message = "Metrics server should be absent when install_metrics_server is false"
  }

  assert {
    condition     = length(module.cluster_autoscaler) == 0
    error_message = "Cluster autoscaler should be absent without base autoscaler role ARN"
  }

  assert {
    condition     = length(module.node_termination_handler) == 0
    error_message = "Node auto-heal should be absent when base outputs disable it"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.platform) == 0
    error_message = "CloudWatch platform log groups should be absent when observability is disabled"
  }

  assert {
    condition     = length(aws_ecr_pull_through_cache_rule.cache) == 0
    error_message = "ECR pull-through cache rules should be absent when disabled"
  }

  assert {
    condition     = length(kubernetes_manifest.buildkitd) == 0
    error_message = "BuildKit manifest should be absent when enable_buildkitd is false"
  }

  assert {
    condition = [
      for volume in local.buildkitd_volumes :
      try(volume.configMap.name, "absent")
      if contains(["buildkit-docker-config", "buildkitd-config"], volume.name)
    ] == [null, null]
    error_message = "Count-gated BuildKit config map references should resolve safely when BuildKit is disabled"
  }
}

run "buildkit_complete" {
  command = plan

  variables {
    enable_buildkitd           = true
    buildkitd_tls_enabled      = true
    buildkitd_tls_secret_name  = "buildkitd-tls"
    buildkitd_tmp_storage_size = "10Gi"
    buildkitd_storage_size     = "50Gi"
    buildkitd_hpa_enabled      = true
    buildkitd_pdb_enabled      = true
    buildkitd_recycle = {
      enabled  = true
      schedule = "0 2 * * 0"
      timezone = "America/Los_Angeles"
    }
    buildkitd_node_keyring_limits = {
      enabled   = true
      max_keys  = 20000
      max_bytes = 25000000
    }
    install_keda                    = false
    install_eso                     = false
    install_metrics_server          = false
    enable_cloudwatch_observability = false
    enable_ecr_pull_through_cache   = false
  }

  assert {
    condition     = length(kubernetes_manifest.buildkitd) == 1
    error_message = "BuildKit manifest should be planned"
  }

  assert {
    condition     = length(kubernetes_pod_disruption_budget_v1.buildkitd) == 1
    error_message = "BuildKit PDB should be planned when PDB is enabled"
  }

  assert {
    condition     = length(kubernetes_horizontal_pod_autoscaler_v2.buildkitd) == 1
    error_message = "BuildKit HPA should be planned when HPA is enabled"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.buildkitd_recycler) == 1
    error_message = "BuildKit recycler CronJob should be planned when recycle is enabled"
  }

  assert {
    condition     = length([for volume in local.buildkitd_volumes : volume if volume.name == "buildkit-tls"]) == 1
    error_message = "TLS volume should be present when buildkitd_tls_enabled is true"
  }

  assert {
    condition     = length([for container in local.buildkitd_init_containers : container if container.name == "raise-keyring-limits"]) == 1
    error_message = "Keyring init container should be present when keyring limits are enabled"
  }

  assert {
    condition = contains(
      local.buildkitd_empty_dir_medium_computed_fields,
      "spec.template.spec.volumes[3].emptyDir.medium"
    )
    error_message = "tmp emptyDir.medium computed field path should be derived by volume index"
  }

  assert {
    condition = contains(
      local.buildkitd_empty_dir_medium_computed_fields,
      "spec.template.spec.volumes[5].emptyDir.medium"
    )
    error_message = "buildkit-rootless emptyDir.medium computed field path should be derived by volume index"
  }

  assert {
    condition = [
      for volume in local.buildkitd_volumes :
      try(volume.emptyDir.medium, null)
      if contains(["tmp", "buildkit-rootless"], volume.name)
    ] == ["", ""]
    error_message = "BuildKit emptyDir.medium should use the concrete Kubernetes default"
  }

  assert {
    condition = [
      for volume in local.buildkitd_volumes :
      try(volume.emptyDir.sizeLimit, null)
      if volume.name == "tmp"
    ] == ["10Gi"]
    error_message = "BuildKit tmp sizeLimit should remain Terraform-managed"
  }
}

run "buildkit_reduced" {
  command = plan

  variables {
    enable_buildkitd           = true
    buildkitd_tls_enabled      = false
    buildkitd_tmp_storage_size = null
    buildkitd_hpa_enabled      = false
    buildkitd_pdb_enabled      = false
    buildkitd_recycle = {
      enabled  = false
      schedule = "0 2 * * 0"
      timezone = "America/Los_Angeles"
    }
    buildkitd_node_keyring_limits = {
      enabled   = false
      max_keys  = 20000
      max_bytes = 25000000
    }
    install_keda                    = false
    install_eso                     = false
    install_metrics_server          = false
    enable_cloudwatch_observability = false
    enable_ecr_pull_through_cache   = false
  }

  assert {
    condition     = length(kubernetes_manifest.buildkitd) == 1
    error_message = "BuildKit manifest should still be planned when optional features are disabled"
  }

  assert {
    condition     = length(kubernetes_pod_disruption_budget_v1.buildkitd) == 0
    error_message = "BuildKit PDB should be absent when PDB is disabled"
  }

  assert {
    condition     = length(kubernetes_horizontal_pod_autoscaler_v2.buildkitd) == 0
    error_message = "BuildKit HPA should be absent when HPA is disabled"
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.buildkitd_recycler) == 0
    error_message = "BuildKit recycler CronJob should be absent when recycle is disabled"
  }

  assert {
    condition     = length([for volume in local.buildkitd_volumes : volume if volume.name == "buildkit-tls"]) == 0
    error_message = "TLS volume should be absent when buildkitd_tls_enabled is false"
  }

  assert {
    condition     = length([for container in local.buildkitd_init_containers : container if container.name == "raise-keyring-limits"]) == 0
    error_message = "Keyring init container should be absent when keyring limits are disabled"
  }

  assert {
    condition = [
      for volume in local.buildkitd_volumes :
      try(volume.emptyDir.sizeLimit, null)
      if volume.name == "tmp"
    ] == [null]
    error_message = "BuildKit tmp sizeLimit should be omitted when buildkitd_tmp_storage_size is null"
  }
}

run "operator_cache_variation" {
  command = plan

  override_data {
    target = data.terraform_remote_state.base
    values = {
      outputs = {
        cluster_name                   = "mock-cluster"
        cluster_oidc_issuer_url        = "https://oidc.eks.us-west-2.amazonaws.com/id/MOCK"
        oidc_provider_arn              = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/MOCK"
        kms_key_arn                    = "arn:aws:kms:us-west-2:123456789012:key/mock"
        common_tags                    = { Project = "mock", Environment = "test" }
        ec2_node_group_role_name       = null
        cluster_autoscaler_role_arn    = null
        cluster_autoscaler_namespace   = "kube-system"
        cluster_autoscaler_version     = "v1.31.0"
        cluster_autoscaler_extra_args  = {}
        node_auto_heal_enabled         = false
        node_auto_heal_role_arn        = null
        node_auto_heal_queue_url       = null
        node_auto_heal_namespace       = "kube-system"
        node_auto_heal_service_account = "aws-node-termination-handler"
      }
    }
  }

  variables {
    install_keda                                       = true
    install_eso                                        = false
    install_metrics_server                             = true
    enable_cloudwatch_observability                    = true
    enable_cloudwatch_observability_addon              = false
    enable_fargate_cloudwatch_logging                  = false
    enable_buildkitd                                   = false
    enable_ecr_pull_through_cache                      = true
    create_ecr_pull_through_cache_repository_templates = false
    ecr_pull_through_cache_rules = {
      quay = {
        upstream_registry_url = "quay.io"
      }
    }
    application_crd_ready_wait_seconds = 0
  }

  assert {
    condition     = length(module.keda_operator) == 1
    error_message = "KEDA operator should be planned when install_keda is true"
  }

  assert {
    condition     = length(module.external_secrets_operator) == 0
    error_message = "ESO should be absent when install_eso is false"
  }

  assert {
    condition     = length(module.metrics_server) == 1
    error_message = "Metrics server should be planned when install_metrics_server is true"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.platform) > 0
    error_message = "CloudWatch platform log groups should be planned when observability is enabled"
  }

  assert {
    condition     = length(aws_eks_addon.cloudwatch_observability) == 0
    error_message = "CloudWatch observability addon should be absent when its addon flag is false"
  }

  assert {
    condition     = length(aws_ecr_pull_through_cache_rule.cache) == 1
    error_message = "ECR pull-through cache rules should be planned when enabled"
  }

  assert {
    condition     = length(aws_ecr_repository_creation_template.pull_through_cache) == 0
    error_message = "ECR repository templates should be absent when template creation is disabled"
  }
}

run "cilium_overlay_keda_host_network" {
  command = plan

  override_data {
    target = data.terraform_remote_state.base
    values = {
      outputs = {
        cluster_name                   = "mock-cluster"
        cluster_oidc_issuer_url        = "https://oidc.eks.us-west-2.amazonaws.com/id/MOCK"
        oidc_provider_arn              = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/MOCK"
        kms_key_arn                    = "arn:aws:kms:us-west-2:123456789012:key/mock"
        common_tags                    = { Project = "mock", Environment = "test" }
        ec2_node_group_role_name       = "mock-node-group-role"
        cluster_autoscaler_role_arn    = null
        cluster_autoscaler_namespace   = "kube-system"
        cluster_autoscaler_version     = "v1.31.0"
        cluster_autoscaler_extra_args  = {}
        node_auto_heal_enabled         = false
        node_auto_heal_role_arn        = null
        node_auto_heal_queue_url       = null
        node_auto_heal_namespace       = "kube-system"
        node_auto_heal_service_account = "aws-node-termination-handler"
        pod_networking_mode            = "cilium-overlay"
      }
    }
  }

  variables {
    install_keda                       = true
    install_eso                        = false
    install_metrics_server             = false
    enable_cloudwatch_observability    = false
    enable_buildkitd                   = false
    application_crd_ready_wait_seconds = 0
  }

  assert {
    condition     = length(module.keda_operator) == 1
    error_message = "KEDA operator should be planned when install_keda is true"
  }

  assert {
    condition     = module.keda_operator[0].use_host_network_for_control_plane_reachability == true
    error_message = "KEDA should use hostNetwork when pod_networking_mode is cilium-overlay"
  }
}
