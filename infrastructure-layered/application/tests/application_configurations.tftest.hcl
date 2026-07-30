# Credential-free application configuration plan tests.
# Run from the application layer root after copying ci/static-provider.tf:
#   terraform init -backend=false
#   terraform test -test-directory=tests

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "us-west-2"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_secretsmanager_secret" {
    defaults = {
      arn  = "arn:aws:secretsmanager:us-west-2:123456789012:secret:ado-agent-spn-secret-abc"
      name = "ado-agent-spn-secret"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock-policy"
    }
  }

  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-west-2:123456789012:repository/mock-cluster-ado-agent"
      repository_url = "123456789012.dkr.ecr.us-west-2.amazonaws.com/mock-cluster-ado-agent"
    }
  }
}

mock_provider "kubernetes" {}

mock_provider "helm" {}

variables {
  remote_state_bucket      = "test-bucket"
  remote_state_region      = "us-west-2"
  remote_state_environment = "test"
  aws_region               = "us-west-2"
  ado_url                  = "https://dev.azure.com/mockorg"
  ado_org                  = "mockorg"
  ado_pat_value            = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz1234567890"
}

override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      cluster_name                       = "mock-cluster"
      cluster_oidc_issuer_url            = "https://oidc.eks.us-west-2.amazonaws.com/id/MOCK"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/MOCK"
      kms_key_arn                        = "arn:aws:kms:us-west-2:123456789012:key/mock"
      common_tags                        = { Project = "mock", Environment = "test" }
      fargate_role_name                  = "mock-cluster-fargate-role"
      cluster_endpoint                   = "https://mock-cluster.eks.us-west-2.amazonaws.com"
      cluster_certificate_authority_data = "Y2VydA=="
    }
  }
}

override_data {
  target = data.terraform_remote_state.middleware
  values = {
    outputs = {
      eso_role_arn               = "arn:aws:iam::123456789012:role/mock-eso-role"
      eso_service_account_name   = "external-secrets"
      eso_namespace              = "external-secrets"
      ado_secret_name            = "ado-agent-pat"
      ado_agents_namespace       = "ado-agents"
      cluster_secret_store_name  = "aws-secrets-manager"
      buildkitd_enabled          = true
      buildkitd_service_endpoint = "buildkitd.buildkit.svc.cluster.local:1234"
      cloudwatch_log_groups      = ["/aws/eks/mock-cluster/platform"]
    }
  }
}

run "pat_with_managed_ecr" {
  command = plan

  variables {
    ado_agent_auth_mode = "pat"
  }

  assert {
    condition     = length(module.ecr) == 1
    error_message = "Managed ECR module should be planned when ecr_repositories is non-empty"
  }

  assert {
    condition     = length(aws_secretsmanager_secret.ado_pat) == 1
    error_message = "ADO PAT secret should be planned in PAT auth mode"
  }

  assert {
    condition     = length(kubernetes_secret.ado_pat_bootstrap) == 1
    error_message = "Bootstrap PAT secret should be planned in PAT auth mode"
  }

  assert {
    condition     = length(terraform_data.wait_for_ado_agent_spn_secret) == 0
    error_message = "SPN wait hook should be absent in PAT auth mode"
  }

  assert {
    condition     = module.eso_ado_secret_access_policy.policy_name != ""
    error_message = "ESO ADO secret access policy should be planned"
  }

  assert {
    condition     = helm_release.ado_agents.name == "ado-agents"
    error_message = "ADO agents Helm release should be planned"
  }

  assert {
    condition     = contains(keys(var.ecr_repositories), var.agent_pools["ado-agent"].ecr_repository_key)
    error_message = "Managed ECR repositories should be keyed for agent pool image resolution"
  }
}

run "spn_mode" {
  command = plan

  variables {
    ado_agent_auth_mode = "spn"
    ado_agent_spn_secret = {
      aws_secret_name = "ado-agent-spn-secret"
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.ado_pat) == 0
    error_message = "PAT secret should be absent in SPN auth mode"
  }

  assert {
    condition     = length(kubernetes_secret.ado_pat_bootstrap) == 0
    error_message = "Bootstrap PAT secret should be absent in SPN auth mode"
  }

  assert {
    condition     = length(data.aws_secretsmanager_secret.ado_agent_spn) == 1
    error_message = "SPN secret lookup should be planned in SPN auth mode"
  }

  assert {
    condition     = length(terraform_data.wait_for_ado_agent_spn_secret) == 1
    error_message = "SPN wait hook should be planned in SPN auth mode"
  }

  assert {
    condition     = helm_release.ado_agents.name == "ado-agents"
    error_message = "ADO agents Helm release should still be planned in SPN mode"
  }
}

run "external_images_without_managed_ecr" {
  command = plan

  variables {
    ecr_repositories = {}
    agent_pools = {
      ado-agent = {
        enabled              = true
        ado_pool_name        = "EKS-External-Agents"
        ecr_repository_key   = "unused"
        image_repository     = "mcr.microsoft.com/azure-pipelines/vsts-agent"
        image_tag            = "ubuntu-20.04"
        image_pull_policy    = "IfNotPresent"
        service_account_name = "ado-agent"
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "2Gi" }
        }
        autoscaling = {
          enabled             = true
          min_replicas        = 1
          max_replicas        = 3
          polling_interval    = 30
          target_queue_length = 1
        }
        tolerations                 = []
        node_selector               = {}
        affinity                    = null
        topology_spread_constraints = []
        additional_env_vars         = {}
        volume_mounts               = []
        volumes                     = []
      }
    }
    ado_execution_roles = {
      ado-agent = {
        namespace            = "ado-agents"
        service_account_name = "ado-agent"
        permissions = [{
          effect    = "Allow"
          actions   = ["ecr:GetAuthorizationToken"]
          resources = ["*"]
        }]
      }
    }
  }

  assert {
    condition     = length(module.ecr) == 0
    error_message = "Managed ECR module should be absent when ecr_repositories is empty"
  }

  assert {
    condition     = var.agent_pools["ado-agent"].image_repository == "mcr.microsoft.com/azure-pipelines/vsts-agent"
    error_message = "Agent pools should keep explicit image_repository when managed ECR is disabled"
  }

  assert {
    condition     = helm_release.ado_agents.name == "ado-agents"
    error_message = "ADO agents Helm release should still plan without managed ECR"
  }
}

run "multiple_execution_roles_and_pools" {
  command = plan

  variables {
    ado_execution_roles = {
      pool-a = {
        namespace            = "ado-agents"
        service_account_name = "pool-a"
        permissions = [{
          effect    = "Allow"
          actions   = ["s3:ListBucket"]
          resources = ["arn:aws:s3:::example"]
        }]
      }
      pool-b = {
        namespace            = "ado-agents"
        service_account_name = "pool-b"
        permissions = [{
          effect    = "Allow"
          actions   = ["dynamodb:GetItem"]
          resources = ["arn:aws:dynamodb:us-west-2:123456789012:table/example"]
        }]
      }
      pool-c = {
        namespace            = "ado-agents"
        service_account_name = "pool-c"
        permissions = [{
          effect    = "Allow"
          actions   = ["logs:DescribeLogGroups"]
          resources = ["*"]
        }]
      }
    }
    agent_pools = {
      pool-a = {
        enabled              = true
        ado_pool_name        = "Pool-A"
        ecr_repository_key   = "ado-agent"
        image_repository     = ""
        image_tag            = "latest"
        image_pull_policy    = "IfNotPresent"
        service_account_name = "pool-a"
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "2Gi" }
        }
        autoscaling = {
          enabled             = true
          min_replicas        = 1
          max_replicas        = 2
          polling_interval    = 30
          target_queue_length = 1
        }
        tolerations                 = []
        node_selector               = {}
        affinity                    = null
        topology_spread_constraints = []
        additional_env_vars         = {}
        volume_mounts               = []
        volumes                     = []
      }
      pool-b = {
        enabled              = true
        ado_pool_name        = "Pool-B"
        ecr_repository_key   = "ado-iac-agent"
        image_repository     = ""
        image_tag            = "latest"
        image_pull_policy    = "IfNotPresent"
        service_account_name = "pool-b"
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "2Gi" }
        }
        autoscaling = {
          enabled             = true
          min_replicas        = 1
          max_replicas        = 2
          polling_interval    = 30
          target_queue_length = 1
        }
        tolerations                 = []
        node_selector               = {}
        affinity                    = null
        topology_spread_constraints = []
        additional_env_vars         = {}
        volume_mounts               = []
        volumes                     = []
      }
      pool-c = {
        enabled              = false
        ado_pool_name        = "Pool-C"
        ecr_repository_key   = "ado-agent"
        image_repository     = ""
        image_tag            = "latest"
        image_pull_policy    = "IfNotPresent"
        service_account_name = "pool-c"
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "1000m", memory = "2Gi" }
        }
        autoscaling = {
          enabled             = false
          min_replicas        = 1
          max_replicas        = 1
          polling_interval    = 30
          target_queue_length = 1
        }
        tolerations                 = []
        node_selector               = {}
        affinity                    = null
        topology_spread_constraints = []
        additional_env_vars         = {}
        volume_mounts               = []
        volumes                     = []
      }
    }
  }

  assert {
    condition     = length(module.ado_agent_execution_role) == 3
    error_message = "Execution roles should be planned for each ado_execution_roles entry"
  }

  assert {
    condition     = length(module.ado_agent_execution_policy) == 3
    error_message = "Execution policies should be planned for each ado_execution_roles entry"
  }

  assert {
    condition     = length(module.ado_agent_execution_policy_attachment) == 3
    error_message = "Execution policy attachments should be planned for each ado_execution_roles entry"
  }

  assert {
    condition     = var.agent_pools["pool-a"].enabled == true
    error_message = "Enabled agent pools should remain configured in inputs"
  }

  assert {
    condition     = var.agent_pools["pool-c"].enabled == false
    error_message = "Disabled agent pools should remain configured in inputs"
  }
}

run "buildkit_cloudwatch_variation" {
  command = plan

  override_data {
    target = data.terraform_remote_state.middleware
    values = {
      outputs = {
        eso_role_arn               = "arn:aws:iam::123456789012:role/mock-eso-role"
        eso_service_account_name   = "external-secrets"
        eso_namespace              = "external-secrets"
        ado_secret_name            = "ado-agent-pat"
        ado_agents_namespace       = "ado-agents"
        cluster_secret_store_name  = "aws-secrets-manager"
        buildkitd_enabled          = false
        buildkitd_service_endpoint = null
        cloudwatch_log_groups      = []
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.middleware.outputs.buildkitd_enabled == false
    error_message = "Middleware remote state should disable BuildKit for this scenario"
  }

  assert {
    condition     = data.terraform_remote_state.middleware.outputs.buildkitd_service_endpoint == null
    error_message = "Middleware remote state should omit the BuildKit endpoint for this scenario"
  }

  assert {
    condition     = length(data.terraform_remote_state.middleware.outputs.cloudwatch_log_groups) == 0
    error_message = "Middleware remote state should expose an empty CloudWatch log-group map"
  }

  assert {
    condition     = helm_release.ado_agents.name == "ado-agents"
    error_message = "ADO agents Helm release should still plan when BuildKit and CloudWatch outputs are empty"
  }
}
