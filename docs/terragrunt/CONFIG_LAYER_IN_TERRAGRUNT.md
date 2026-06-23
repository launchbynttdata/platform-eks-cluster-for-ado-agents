# Config Layer in Terragrunt Deployment

## Overview

The **config layer** is a special post-deployment layer that performs Kubernetes-native configuration after all Terraform layers are deployed. Unlike the other layers (base, networking, middleware, application), the config layer does **NOT** use Terraform/Terragrunt—it uses `kubectl` and AWS CLI directly.

## Purpose

The config layer handles critical post-deployment tasks that require:
1. The EKS cluster to be fully operational
2. External Secrets Operator (ESO) to be installed
3. kubectl access to the cluster

## What the Config Layer Does

### 1. Configure kubectl Access
```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```
Sets up kubectl to communicate with the newly created EKS cluster.

### 2. Create ClusterSecretStore
Applies a Kubernetes manifest to create the `ClusterSecretStore` resource for External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
```

**Why this matters**: Without the ClusterSecretStore, External Secrets Operator cannot sync secrets from AWS Secrets Manager to Kubernetes, and ADO agents won't be able to authenticate.

### 3. Wait for ClusterSecretStore Ready
The script waits up to 60 seconds (30 attempts × 2 seconds) for the ClusterSecretStore to become ready:
```bash
kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

### 4. Optional: Update ADO PAT in AWS Secrets Manager
When `--update-ado-secret` flag is used, the script prompts for Azure DevOps credentials and updates the PAT in AWS Secrets Manager:
```bash
aws secretsmanager put-secret-value \
    --secret-id <cluster-name>-ado-pat \
    --secret-string <pat-value> \
    --region <region>
```

## Usage

### Deploy All Layers Including Config
```bash
# Interactive: prompts for config layer after Terraform layers
./deploy.sh deploy

# Non-interactive: explicit config layer and ADO credentials
export ADO_PAT='...'
export ADO_ORG_URL='https://dev.azure.com/yourorg'
./deploy.sh deploy --auto-approve --with-config-layer --update-ado-secret
```

In interactive mode you are prompted after Terraform layers complete:
```
Deploy config layer (ClusterSecretStore + kubectl setup)? [y/N]
```

With `--auto-approve`, use `--with-config-layer` or `--skip-config-layer` explicitly (no prompt).

### Deploy Config Layer Only
```bash
./deploy.sh deploy --layer config
```

### Update ADO PAT
```bash
# Interactive
./deploy.sh deploy --layer config --update-ado-secret

# Non-interactive
export ADO_PAT='...'
export ADO_ORG_URL='https://dev.azure.com/yourorg'
./deploy.sh deploy --layer config --auto-approve --update-ado-secret
```

### Skip Config Layer
```bash
./deploy.sh deploy --auto-approve --skip-config-layer
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Terraform Layers (Terragrunt-managed)                       │
│                                                             │
│  ┌──────────┐      ┌─────────────┐      ┌──────────────┐  │
│  │   Base   │  →   │ Middleware  │  →   │ Application  │  │
│  └──────────┘      └─────────────┘      └──────────────┘  │
│   EKS Cluster       KEDA + ESO           ECR + Secrets     │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Config Layer (kubectl-based, non-Terraform)                │
│                                                             │
│  1. Configure kubectl for cluster access                   │
│  2. Create ClusterSecretStore (ESO)                        │
│  3. Wait for ClusterSecretStore ready                      │
│  4. Optional: Update ADO PAT in AWS Secrets Manager        │
└─────────────────────────────────────────────────────────────┘
                           ↓
              Cluster Ready for ADO Agents
```

## Prerequisites

Before running the config layer:
1. ✅ Base layer deployed (EKS cluster exists)
2. ✅ Middleware layer deployed (ESO installed)
3. ✅ Application layer deployed (secrets created in AWS Secrets Manager)
4. ✅ kubectl installed locally
5. ✅ aws CLI configured with proper credentials
6. ✅ IAM permissions to access EKS cluster

## Verification

After config layer deployment, verify:

### 1. ClusterSecretStore Status
```bash
kubectl get clustersecretstore aws-secrets-manager
```
Expected output:
```
NAME                   AGE   STATUS   CAPABILITIES   READY
aws-secrets-manager    1m    Valid    ReadWrite      True
```

### 2. External Secrets Syncing
```bash
kubectl get externalsecrets -A
```
Expected output shows secrets in sync:
```
NAMESPACE   NAME              STORE                 REFRESH INTERVAL   STATUS         READY
default     ado-agent-secret  aws-secrets-manager   1h                 SecretSynced   True
```

### 3. Kubernetes Secrets Created
```bash
kubectl get secrets -A | grep ado
```
Should show secrets synced from AWS Secrets Manager.

### 4. Check ESO Logs (if issues)
```bash
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets
```

## Troubleshooting

### ClusterSecretStore Not Ready
```bash
# Check ClusterSecretStore details
kubectl describe clustersecretstore aws-secrets-manager

# Check External Secrets Operator logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets --tail=50

# Verify ESO ServiceAccount and IAM role
kubectl get sa -n external-secrets-system external-secrets
kubectl describe sa -n external-secrets-system external-secrets
```

### kubectl Access Issues
```bash
# Manually configure kubectl
aws eks update-kubeconfig --region us-west-2 --name poc-ado-agent-cluster

# Test access
kubectl get nodes
kubectl auth can-i get pods --all-namespaces
```

### ADO PAT Update Fails
```bash
# Check if secret exists
aws secretsmanager describe-secret --secret-id poc-ado-agent-cluster-ado-pat --region us-west-2

# Manually update secret
aws secretsmanager put-secret-value \
    --secret-id poc-ado-agent-cluster-ado-pat \
    --secret-string "your-pat-here" \
    --region us-west-2
```

## CI/CD Integration

### Non-interactive deploy
```bash
export ADO_PAT="your-pat-here"
export ADO_ORG_URL="https://dev.azure.com/yourorg"

# Full deploy: Terraform layers + config + ADO secret
./deploy.sh deploy --auto-approve --with-config-layer --update-ado-secret

# Or staged:
./deploy.sh deploy --auto-approve --skip-config-layer
./deploy.sh deploy --layer config --auto-approve --update-ado-secret
```

With `--auto-approve`, the script never reads from stdin. Missing `ADO_PAT` or `ADO_ORG_URL` when using `--update-ado-secret` exits immediately with an error.

## Summary

The config layer bridges the gap between infrastructure provisioning (Terraform/Terragrunt) and application readiness (Kubernetes). It ensures that:

1. ✅ kubectl can access the cluster
2. ✅ External Secrets Operator can sync secrets from AWS Secrets Manager
3. ✅ ADO agents can authenticate using synced secrets
4. ✅ The cluster is ready for workload deployment

Without the config layer, ADO agents would fail to start due to missing secret synchronization.
