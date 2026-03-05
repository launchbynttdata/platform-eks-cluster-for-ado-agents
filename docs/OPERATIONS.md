# Operations Guide - EKS Cluster for ADO Agents

This guide provides operational procedures for deploying, configuring, and maintaining the EKS cluster infrastructure for Azure DevOps agents.

## Table of Contents

- [Deployment Workflow](#deployment-workflow)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [ADO PAT Secret Management](#ado-pat-secret-management)
- [Cluster Autoscaler](#cluster-autoscaler)
- [Troubleshooting](#troubleshooting)

---

## Deployment Workflow

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform 1.5+ installed
- kubectl installed
- Appropriate IAM permissions for EKS, S3, Secrets Manager, and related services

### Layer Deployment Sequence

The infrastructure is deployed in three layers:

1. **Base Layer** - VPC, EKS cluster, node groups
2. **Middleware Layer** - KEDA, External Secrets Operator, Buildkitd
3. **Application Layer** - ADO agents, ECR repositories, ExternalSecrets

#### Deploy All Layers

```bash
cd infrastructure-layered

# Deploy all layers in sequence
./deploy.sh --layer all deploy
```

#### Deploy Individual Layers

```bash
# Base layer
./deploy.sh --layer base deploy

# Middleware layer
./deploy.sh --layer middleware deploy

# Application layer
./deploy.sh --layer application deploy
```

#### Plan Before Deploying

```bash
# Plan all layers
./deploy.sh --layer all plan

# Plan specific layer
./deploy.sh --layer middleware plan
```

### Region Configuration

The AWS region is configured once in each layer's `terraform.tfvars`:

```hcl
aws_region = "us-west-2"
```

This region propagates to:
- All AWS resources
- Kubernetes/Helm provider authentication
- Agent pool environment variables
- Secrets Manager operations

---

## Post-Deployment Configuration

### Complete Infrastructure Post-Deployment

After ALL infrastructure layers are deployed (base + middleware + application), you **must** run the config layer to complete the setup.

#### Why This Step is Required

Terraform cannot create `ClusterSecretStore` resources during the initial apply because:
1. External Secrets Operator installs CRDs during Helm chart deployment
2. Terraform validates `kubernetes_manifest` resources during the **plan** phase
3. If CRDs don't exist yet, validation fails before any resources are created

The config layer creates the ClusterSecretStore **after** all layers are deployed and ESO has installed its CRDs.

#### Run Config Layer

**Important**: Run this AFTER deploying all Terraform layers with `./deploy.sh deploy` or `./deploy.sh --layer all deploy`

```bash
cd infrastructure-layered

# Deploy config layer (interactive mode - prompts for PAT)
./deploy.sh --layer config deploy

# With explicit credentials
./deploy.sh --layer config --pat "your-ado-pat-token" --org-url "https://dev.azure.com/your-org" deploy

# Skip ADO secret injection
./deploy.sh --layer config --skip-ado-secret deploy
```

#### What the Config Layer Does

1. **Verifies** all infrastructure layers are deployed (base, middleware, application)
2. **Auto-detects** cluster name and AWS region from Terraform state
3. **Configures** kubectl access to your EKS cluster
4. **Creates** ClusterSecretStore for AWS Secrets Manager integration
5. **Prompts** for Azure DevOps PAT token (interactive mode, unless --skip-ado-secret)
6. **Injects** ADO PAT secret into AWS Secrets Manager
7. **Verifies** all components are working (ESO, KEDA, agents)

#### Manual Post-Deployment (Alternative)

If you prefer manual steps:

**Step 1: Configure kubectl**

```bash
cd infrastructure-layered/base
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -raw aws_region)

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
```

**Step 2: Verify ESO is Running**

```bash
kubectl get pods -n external-secrets-system
kubectl get crd | grep external-secrets
```

**Step 3: Create ClusterSecretStore**

```bash
# Get ESO IAM role ARN
cd infrastructure-layered/middleware
ESO_ROLE_ARN=$(terraform output -raw eso_role_arn)

# Create ClusterSecretStore
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${AWS_REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets-system
EOF
```

**Step 4: Verify ClusterSecretStore**

```bash
kubectl get clustersecretstore aws-secrets-manager
kubectl describe clustersecretstore aws-secrets-manager
```

---

## ADO PAT Secret Management

### Overview

The application layer creates an AWS Secrets Manager secret for storing your Azure DevOps Personal Access Token (PAT), but intentionally leaves it empty. This security-first approach ensures sensitive credentials are never stored in Terraform state or version control.

### PAT Requirements

Your Azure DevOps PAT must have the following permissions:
- **Agent Pools**: Read & manage
- **Deployment Groups**: Read & manage (if using deployment groups)

### Secret Structure

The secret stores three key-value pairs in JSON format:

```json
{
  "personalAccessToken": "your-ado-pat-token-here",
  "organization": "your-org-name",
  "adourl": "https://dev.azure.com/your-org-name"
}
```

### Quick Reference - Inject PAT Secret

```bash
# 1. Set your configuration
export SECRET_NAME="ado-agent-pat"
export AWS_REGION="us-west-2"  # Match your cluster region
export ADO_ORG="your-org-name"
export ADO_URL="https://dev.azure.com/${ADO_ORG}"

# 2. Securely prompt for PAT
echo "Enter your Azure DevOps PAT:"
read -s ADO_PAT

# 3. Update the secret
aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    --secret-string "$(jq -n \
        --arg pat "$ADO_PAT" \
        --arg org "$ADO_ORG" \
        --arg url "$ADO_URL" \
        '{personalAccessToken: $pat, organization: $org, adourl: $url}')"

# 4. Clear sensitive data
unset ADO_PAT

# 5. Verify ExternalSecret synchronization
kubectl get externalsecret -n ado-agents
kubectl describe externalsecret ado-pat -n ado-agents
```

### Verify Secret in Kubernetes

```bash
# Check if ExternalSecret is synced
kubectl get externalsecret ado-pat -n ado-agents -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# View secret (base64 encoded)
kubectl get secret ado-pat -n ado-agents -o yaml

# Decode and view secret values (careful - this exposes sensitive data)
kubectl get secret ado-pat -n ado-agents -o jsonpath='{.data.personalAccessToken}' | base64 -d
```

### Update PAT Secret

To rotate or update the PAT:

```bash
# Use the same command as injection
aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    --secret-string "{\"personalAccessToken\":\"new-pat\",\"organization\":\"${ADO_ORG}\",\"adourl\":\"${ADO_URL}\"}"

# ExternalSecret will auto-sync within 1 hour (default refresh interval)
# Or force immediate sync by deleting the K8s secret:
kubectl delete secret ado-pat -n ado-agents
# ESO will recreate it immediately
```

---

## Cluster Autoscaler

### Overview

The infrastructure includes AWS Cluster Autoscaler for EC2 node groups (Buildkit workloads). Fargate profiles handle ADO agents and operators with built-in auto-scaling.

### Deployment

Cluster Autoscaler is deployed via a separate script after the base layer:

```bash
cd infrastructure-layered
./deploy-cluster-autoscaler.sh
```

### Configuration

Autoscaler settings are configured in `infrastructure/terraform.tfvars`:

```hcl
enable_cluster_autoscaler = true
cluster_autoscaler_version = "v1.29.0"
cluster_autoscaler_settings = {
  scale_down_enabled              = true
  scale_down_delay_after_add      = "10m"
  scale_down_unneeded_time        = "10m"
  scale_down_utilization_threshold = 0.5
  max_node_provision_time         = "15m"
  scan_interval                   = "10s"
  skip_nodes_with_local_storage   = false
  skip_nodes_with_system_pods     = true
  balance_similar_node_groups     = true
  expander                        = "least-waste"
}
```

### Verification

```bash
# Check Cluster Autoscaler pod
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler

# View logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=50

# Check node autoscaling
kubectl get nodes
kubectl describe configmap cluster-autoscaler-status -n kube-system
```

### Node Group Configuration

EC2 node groups with autoscaling must have proper tags:

```hcl
tags = {
  "k8s.io/cluster-autoscaler/${cluster_name}" = "owned"
  "k8s.io/cluster-autoscaler/enabled"         = "true"
}
```

---

## Troubleshooting

### Middleware Components Not Starting

**KEDA Operator Pods Not Starting**
```bash
# Check Fargate profile includes keda-system namespace
kubectl describe fargateprofile -n kube-system

# Check pod events
kubectl describe pods -n keda-system

# Verify IAM role
kubectl describe sa keda-operator -n keda-system
```

**External Secrets Operator Pods Not Starting**
```bash
# Verify webhook is disabled for Fargate
# In middleware/terraform.tfvars:
eso_webhook_enabled = false

# Check pod status
kubectl get pods -n external-secrets-system
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

**Buildkitd Pods Failing**
```bash
# Check if privileged containers are allowed
kubectl auth can-i create pods --as system:serviceaccount:buildkit-system:default -n buildkit-system

# Verify node selection (EC2 nodes required)
kubectl get pods -n buildkit-system -o wide
kubectl describe nodes
```

### ClusterSecretStore Not Ready

```bash
# Check if ESO CRDs are installed
kubectl get crd | grep external-secrets

# Check ClusterSecretStore status
kubectl describe clustersecretstore aws-secrets-manager

# Verify ESO service account has correct IAM role
kubectl get sa external-secrets -n external-secrets-system -o yaml

# Check ESO logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets --tail=100
```

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret ado-pat -n ado-agents

# Common issues:
# 1. Secret doesn't exist in AWS Secrets Manager
aws secretsmanager describe-secret --secret-id ado-agent-pat --region us-west-2

# 2. ESO IAM role lacks permissions
# Verify IAM policy includes secretsmanager:GetSecretValue

# 3. ClusterSecretStore not ready
kubectl get clustersecretstore aws-secrets-manager
```

### KEDA ScaledObject Not Scaling

```bash
# Check ScaledObject status
kubectl describe scaledobject -n ado-agents

# Check KEDA operator logs
kubectl logs -n keda-system -l app.kubernetes.io/name=keda-operator --tail=100

# Verify TriggerAuthentication
kubectl get triggerauthentication -n ado-agents
kubectl describe triggerauthentication ado-trigger-auth -n ado-agents

# Test ADO PAT manually
curl -u ":${PAT_TOKEN}" \
    "https://dev.azure.com/${ORG_NAME}/_apis/distributedtask/pools?api-version=6.0"
```

### Remote State Access Denied

```bash
# Verify S3 bucket exists and is accessible
aws s3 ls s3://your-state-bucket/

# Check DynamoDB table (if using)
aws dynamodb describe-table --table-name terraform-state-lock

# Verify IAM permissions
aws sts get-caller-identity
```

### Logs and Debugging

```bash
# View all pods across namespaces
kubectl get pods -A

# Check specific namespace
kubectl get all -n ado-agents

# View pod logs
kubectl logs <pod-name> -n <namespace>

# Follow logs in real-time
kubectl logs -f <pod-name> -n <namespace>

# Describe resource for events
kubectl describe <resource-type> <resource-name> -n <namespace>

# Execute commands in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
```

---

## Additional Resources

- [Changelog](../CHANGELOG.md) - Detailed history of changes and fixes
- [Infrastructure-Layered README](../infrastructure-layered/README.md) - Layered infrastructure overview
- [Middleware README](../infrastructure-layered/middleware/README.md) - Middleware layer details
- [Application README](../infrastructure-layered/application/README.md) - Application layer details

---

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section above
2. Review the [Changelog](../CHANGELOG.md) for recent fixes
3. Examine Terraform outputs and Kubernetes resource status
4. Check relevant component logs
