# ADO Agent Cluster Helm Chart

This Helm chart deploys Azure DevOps (ADO) agents on Kubernetes with KEDA-based autoscaling and External Secrets integration.

## Features

- **Multiple Agent Pools**: Support for multiple ADO agent pools with different configurations
- **KEDA Autoscaling**: Event-driven autoscaling based on ADO pipeline queue length
- **External Secrets**: Automatic secret synchronization from AWS Secrets Manager
- **Flexible Configuration**: Configurable resources, tolerations, node selectors per pool
- **Security**: IRSA (IAM Roles for Service Accounts) integration for secure AWS access
- **Buildkit Integration**: Optional integration with cluster-wide buildkit service

## Prerequisites

- Kubernetes 1.19+
- Helm 3.8.0+
- KEDA operator installed in the cluster  
- External Secrets Operator installed in the cluster
- AWS Secrets Manager containing ADO PAT and organization info

## Installation

### Via Terraform (Recommended)

This chart is designed to be deployed via Terraform as part of the layered infrastructure approach:

```hcl
resource "helm_release" "ado_agents" {
  name       = "ado-agents"
  repository = "${path.module}/helm"
  chart      = "ado-agent-cluster"
  namespace  = var.namespace
  
  values = [templatefile("${path.module}/helm-values.yaml.tpl", {
    # Values from Terraform...
  })]
}
```

### Direct Helm Installation

```bash
# Add values
cp values.yaml my-values.yaml
# Edit my-values.yaml with your configuration

# Install
helm install ado-agents ./ado-agent-cluster -f my-values.yaml
```

## Configuration

### Required Values

```yaml
global:
  namespace: ado-agents
  clusterName: your-cluster-name

agentPools:
  dev-build:
    enabled: true
    name: "dev-build"
    ado:
      poolName: "your-ado-pool-name" 
      secretName: "ado-pat"
    image:
      repository: "your-ecr-repo/ado-agent"
      tag: "latest"
    serviceAccount:
      name: "ado-agent-dev-build"
      roleArn: "arn:aws:iam::account:role/role-name"
```

### Agent Pool Configuration

Each agent pool supports:

- **ADO Configuration**: Pool name and secret references
- **Container Image**: Repository, tag, and pull policy
- **Resources**: CPU and memory requests/limits  
- **Autoscaling**: Min/max replicas and scaling trigger configuration
- **Node Assignment**: Node selectors, tolerations, and affinity rules
- **Security**: Service account and IAM role configuration

### External Secrets Configuration

```yaml
externalSecrets:
  enabled: true
  clusterSecretStoreName: "aws-secrets-manager"
  secrets:
    ado-pat:
      aws:
        secretName: "ado/pat"
        region: "us-west-2"
      k8s:
        secretName: "ado-pat"
        refreshInterval: "1h"
      data:
        personalAccessToken: "personalAccessToken"
        organization: "organization"
        adourl: "adourl"
```

## Values Reference

### Global Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.namespace | string | `"ado-agents"` | Kubernetes namespace for deployments |
| global.clusterName | string | `""` | EKS cluster name |
| global.region | string | `"us-west-2"` | AWS region |

### Agent Pool Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agentPools.*.enabled | bool | `true` | Enable this agent pool |
| agentPools.*.ado.poolName | string | `""` | ADO agent pool name |
| agentPools.*.image.repository | string | `""` | Container image repository |
| agentPools.*.resources.requests.cpu | string | `"500m"` | CPU request |
| agentPools.*.resources.requests.memory | string | `"1Gi"` | Memory request |
| agentPools.*.autoscaling.minReplicas | int | `0` | Minimum replicas |
| agentPools.*.autoscaling.maxReplicas | int | `10` | Maximum replicas |

### Security Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| podSecurityContext.runAsNonRoot | bool | `true` | Run as non-root user |
| securityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation |

## Examples

### Basic Development Agent Pool

```yaml
agentPools:
  dev:
    enabled: true
    name: "dev"
    ado:
      poolName: "development-agents"
      secretName: "ado-pat"
    image:
      repository: "123456789.dkr.ecr.us-west-2.amazonaws.com/ado-agent"
      tag: "latest"
    serviceAccount:
      name: "ado-agent-dev"
      roleArn: "arn:aws:iam::123456789:role/ado-dev-role"
    autoscaling:
      minReplicas: 1
      maxReplicas: 5
```

### Production IaC Agent Pool

```yaml
agentPools:
  iac:
    enabled: true
    name: "iac"
    ado:
      poolName: "infrastructure-agents"
      secretName: "ado-pat"
    image:
      repository: "123456789.dkr.ecr.us-west-2.amazonaws.com/ado-iac-agent"
      tag: "v1.0.0"
    serviceAccount:
      name: "ado-agent-iac"
      roleArn: "arn:aws:iam::123456789:role/ado-iac-role"
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
    autoscaling:
      minReplicas: 0
      maxReplicas: 3
    nodeSelector:
      workload-type: "infrastructure"
```

## Troubleshooting

### Pods Not Starting

1. **Check Fargate Profile**: Ensure namespace is included in Fargate profile selectors
2. **Verify Service Account**: Check IRSA role ARN annotation is correct
3. **Check Tolerations**: Ensure tolerations match node taints

```bash
kubectl describe pod -n ado-agents -l app.kubernetes.io/name=ado-agent-cluster
```

### KEDA Not Scaling

1. **Verify TriggerAuthentication**: Check secret exists and has correct keys
2. **Check KEDA Logs**: Look for authentication or API errors
3. **Test ADO Connection**: Verify PAT has correct permissions

```bash
kubectl get scaledobjects -n ado-agents
kubectl describe scaledobject -n ado-agents
kubectl logs -n keda-system -l app.kubernetes.io/name=keda-operator
```

### External Secrets Not Syncing

1. **Check ClusterSecretStore**: Verify AWS Secrets Manager integration
2. **Verify IAM Permissions**: ESO role needs access to specific secrets
3. **Check ExternalSecret Status**: Look for error messages

```bash
kubectl get externalsecrets -n ado-agents
kubectl describe externalsecret ado-pat -n ado-agents
kubectl get secrets -n ado-agents
```

## Security Considerations

### IAM Roles
- Each agent pool should have its own IAM role with least-privilege permissions
- Use IRSA for secure credential management (no long-lived access keys)
- Regularly audit and rotate IAM policies

### Container Security
- Run containers as non-root users
- Disable privilege escalation
- Use read-only root filesystem where possible
- Regular image updates and vulnerability scanning

### Network Security  
- Use network policies to restrict pod-to-pod communication
- Ensure secrets are encrypted at rest and in transit
- Monitor access patterns and audit logs

## Monitoring and Observability

### Key Metrics to Monitor
- Pod CPU and memory usage
- KEDA scaling events and queue lengths
- Secret synchronization success/failure rates
- Agent registration and job completion rates

### Logging
- Agent logs are available via `kubectl logs`
- KEDA metrics available via Prometheus
- External Secrets events in cluster events

### Alerts
Consider setting up alerts for:
- Pods stuck in pending state
- KEDA scaling failures
- Secret synchronization failures
- High resource usage or throttling