# Application Layer Outputs
#
# These outputs provide information about deployed application resources
# that may be needed by other systems or for operational purposes.

# =============================================================================
# ECR Repository Outputs
# =============================================================================

output "ecr_repositories" {
  description = "ECR repository information for ADO agent images"
  value = length(var.ecr_repositories) > 0 ? {
    for key in keys(var.ecr_repositories) : key => {
      repository_url = module.ecr[0].repository_urls[key]
      registry_id    = module.ecr[0].registry_ids[key]
      arn           = module.ecr[0].repository_arns[key]
    }
  } : {}
}

# =============================================================================
# ADO Secrets Outputs
# =============================================================================

output "ado_pat_secret" {
  description = "ADO PAT secret information"
  value = {
    name = aws_secretsmanager_secret.ado_pat.name
    arn  = aws_secretsmanager_secret.ado_pat.arn
    id   = aws_secretsmanager_secret.ado_pat.id
  }
  sensitive = true
}

# =============================================================================
# IAM Role Outputs
# =============================================================================

output "ado_agent_execution_roles" {
  description = "IAM roles for ADO agent execution with IRSA"
  value = {
    for role_name, role in aws_iam_role.ado_agent_execution_roles : role_name => {
      name = role.name
      arn  = role.arn
      id   = role.id
    }
  }
}

# =============================================================================
# Helm Release Outputs
# =============================================================================

output "helm_release" {
  description = "Helm release information for ADO agents"
  value = {
    name      = helm_release.ado_agents.name
    namespace = helm_release.ado_agents.namespace
    chart     = helm_release.ado_agents.chart
    version   = helm_release.ado_agents.version
    status    = helm_release.ado_agents.status
  }
}

# =============================================================================
# Application Configuration Summary
# =============================================================================

output "application_summary" {
  description = "Summary of deployed application resources"
  value = {
    cluster_name = local.cluster_name
    region      = data.aws_region.current.name
    
    # Agent pool configuration
    agent_pools = {
      for pool_name, pool_config in var.agent_pools : pool_name => {
        enabled           = pool_config.enabled
        ado_pool_name    = pool_config.ado_pool_name
        min_replicas     = pool_config.autoscaling.min_replicas
        max_replicas     = pool_config.autoscaling.max_replicas
        service_account  = pool_config.service_account_name
        iam_role_arn    = aws_iam_role.ado_agent_execution_roles[pool_name].arn
        image_repository = pool_config.image_repository
        image_tag       = pool_config.image_tag
      }
    }
    
    # ECR repositories
    ecr_repositories = [
      for key in keys(var.ecr_repositories) : key
    ]
    
    # Security configuration
    secrets = {
      ado_pat_secret_name = aws_secretsmanager_secret.ado_pat.name
    }
    
    # Deployment metadata
    deployment = {
      helm_release_name = helm_release.ado_agents.name
      helm_namespace   = helm_release.ado_agents.namespace
      helm_status      = helm_release.ado_agents.status
    }
    
    tags = local.common_tags
  }
}

# =============================================================================
# Operational Information
# =============================================================================

output "operational_info" {
  description = "Operational information for managing the ADO agent deployment"
  value = {
    # Kubectl commands for troubleshooting
    kubectl_commands = {
      view_pods = "kubectl get pods -n ${helm_release.ado_agents.namespace} -l app.kubernetes.io/name=ado-agent"
      view_hpa  = "kubectl get hpa -n ${helm_release.ado_agents.namespace}"
      view_logs = "kubectl logs -n ${helm_release.ado_agents.namespace} -l app.kubernetes.io/name=ado-agent --tail=100"
    }
    
    # Helm commands for management
    helm_commands = {
      status   = "helm status ${helm_release.ado_agents.name} -n ${helm_release.ado_agents.namespace}"
      history  = "helm history ${helm_release.ado_agents.name} -n ${helm_release.ado_agents.namespace}"
      upgrade  = "helm upgrade ${helm_release.ado_agents.name} ../helm/ado-agent-cluster -n ${helm_release.ado_agents.namespace}"
      rollback = "helm rollback ${helm_release.ado_agents.name} -n ${helm_release.ado_agents.namespace}"
    }
    
    # AWS CLI commands for secrets management
    aws_commands = {
      view_secret = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.ado_pat.name} --query SecretString --output text"
      update_secret = "aws secretsmanager update-secret --secret-id ${aws_secretsmanager_secret.ado_pat.name} --secret-string '{\"personalAccessToken\":\"NEW_PAT\",\"organization\":\"${var.ado_org}\",\"adourl\":\"${var.ado_url}\"}'"
    }
    
    # Monitoring and observability
    monitoring = {
      cloudwatch_log_groups = [
        "/aws/eks/${local.cluster_name}/cluster",
        "/aws/fargate/${local.cluster_name}"
      ]
      keda_metrics_namespace = "keda-operator-metrics"
      prometheus_metrics     = "http://keda-operator-metrics.keda-system.svc.cluster.local:8080/metrics"
    }
  }
  sensitive = true
}