# ADO Secret Management Architecture

## Overview

This document explains how Azure DevOps (ADO) Personal Access Token (PAT) secrets are managed across the infrastructure layers.

## Architecture

The ADO PAT secret management follows a **separation of concerns** pattern:

```
┌─────────────────────────────────────────────────────────────┐
│                    SECRET LIFECYCLE                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. TERRAFORM (IaC)          2. CONFIG LAYER               │
│     Creates "container"          Populates content          │
│                                                             │
│  ┌──────────────────┐       ┌──────────────────┐          │
│  │ AWS Secrets      │       │ ADO Credentials  │          │
│  │ Manager          │──────▶│ Injection        │          │
│  │                  │       │                  │          │
│  │ ✓ Secret resource│       │ ✓ PAT token      │          │
│  │ ✓ KMS encryption │       │ ✓ Organization   │          │
│  │ ✓ IAM policies   │       │ ✓ URL            │          │
│  │ ✓ Tags/metadata  │       │                  │          │
│  │ ✗ Secret value   │       │                  │          │
│  └──────────────────┘       └──────────────────┘          │
│                                                             │
│  3. EXTERNAL SECRETS OPERATOR                              │
│     Syncs to Kubernetes                                     │
│                                                             │
│  ┌──────────────────────────────────────────┐             │
│  │ Kubernetes Secret: ado-pat               │             │
│  │                                          │             │
│  │ Keys:                                    │             │
│  │  - personalAccessToken: (from AWS)      │             │
│  │  - organization: (from AWS)             │             │
│  │  - adourl: (from AWS)                   │             │
│  └──────────────────────────────────────────┘             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Application Layer (Terraform)

**Responsibility**: Create the secret "container" with proper security configuration

**Creates**:
- `aws_secretsmanager_secret.ado_pat` - The secret resource
- KMS encryption configuration
- IAM policies for ESO to read the secret
- Tags and metadata
- Initial placeholder secret value

**Location**: `infrastructure-layered/application/main.tf`

```terraform
resource "aws_secretsmanager_secret" "ado_pat" {
  name                    = var.ado_pat_secret_name  # Default: "ado-agent-pat"
  description             = "Personal Access Token for Azure DevOps integration"
  recovery_window_in_days = var.secret_recovery_days
  kms_key_id              = data.terraform_remote_state.base.outputs.kms_key_arn
  
  tags = {
    ManagedBy  = "terraform"
    SecretType = "ado-pat"
    Purpose    = "ADO-Integration"
  }
}

resource "aws_secretsmanager_secret_version" "ado_pat" {
  secret_id = aws_secretsmanager_secret.ado_pat.id
  secret_string = jsonencode({
    personalAccessToken = var.ado_pat_value  # Placeholder
    organization        = var.ado_org
    adourl             = var.ado_url
  })
  
  lifecycle {
    ignore_changes = [secret_string]  # Allow config layer to update
  }
}
```

**Key Features**:
- `lifecycle.ignore_changes = [secret_string]` - Allows the config layer to update the secret value without Terraform reverting it
- Secret structure matches ExternalSecret expectations

### 2. Config Layer (Post-Deployment Script)

**Responsibility**: Populate the secret with actual ADO credentials

**Function**: `inject_ado_secret()` in `deploy.sh`

**Process**:
1. Look up the Terraform-managed secret name (default: `ado-agent-pat`)
2. Verify the secret exists (created by Terraform)
3. Prompt for ADO credentials (PAT token, organization URL)
4. Update the secret content using `aws secretsmanager put-secret-value`
5. Verify ExternalSecret resources are configured

**Usage**:
```bash
# Deploy config layer (includes secret injection)
./deploy.sh --layer config deploy

# Skip secret injection if already configured
./deploy.sh --layer config --skip-ado-secret deploy

# Provide credentials via environment variables
export ADO_PAT_TOKEN="your-pat-token"
export ADO_ORG_URL="https://dev.azure.com/your-org"
./deploy.sh --layer config deploy
```

**Secret Structure**:
```json
{
  "personalAccessToken": "actual-pat-token",
  "organization": "your-org-name",
  "adourl": "https://dev.azure.com/your-org"
}
```

### 3. External Secrets Operator (ESO)

**Responsibility**: Sync the secret from AWS Secrets Manager to Kubernetes

**Configuration**: Created by application layer Helm chart

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ado-pat
  namespace: ado-agents
spec:
  secretStoreRef:
    name: aws-secrets-manager  # ClusterSecretStore created by config layer
    kind: ClusterSecretStore
  target:
    name: ado-pat
  data:
    - secretKey: AZP_TOKEN
      remoteRef:
        key: ado-agent-pat
        property: personalAccessToken
    - secretKey: AZP_ORG
      remoteRef:
        key: ado-agent-pat
        property: organization
    - secretKey: AZP_URL
      remoteRef:
        key: ado-agent-pat
        property: adourl
```

**Result**: Kubernetes secret `ado-pat` in namespace `ado-agents` with keys:
- `AZP_TOKEN` - The PAT token
- `AZP_ORG` - Organization name
- `AZP_URL` - Organization URL

## Secret Name Configuration

The secret name is configurable via Terraform variable:

**File**: `infrastructure-layered/application/terraform.tfvars`

```hcl
# Customize the secret name (optional)
ado_pat_secret_name = "ado-agent-pat"  # Default value
```

The config layer automatically reads this value from tfvars, or falls back to the default.

## Deployment Workflow

### Initial Deployment

```bash
# 1. Deploy base layer (VPC, EKS, KMS)
./deploy.sh --layer base deploy

# 2. Deploy middleware layer (KEDA, ESO)
./deploy.sh --layer middleware deploy

# 3. Deploy application layer (creates secret container)
./deploy.sh --layer application deploy

# 4. Deploy config layer (populates secret + configures ESO)
./deploy.sh --layer config deploy
# Prompts for:
#  - Azure DevOps Organization URL
#  - Personal Access Token

# OR skip secret injection if done separately
./deploy.sh --layer config --skip-ado-secret deploy
```

### Update Secret Credentials

To update the PAT token (e.g., when it expires):

```bash
# Option 1: Use AWS CLI directly
aws secretsmanager put-secret-value \
  --secret-id ado-agent-pat \
  --secret-string '{"personalAccessToken":"new-token","organization":"your-org","adourl":"https://dev.azure.com/your-org"}'

# Option 2: Re-run config layer
./deploy.sh --layer config deploy
# Will prompt for new credentials

# Option 3: Use Terraform variable (discouraged for secrets)
# Edit application/terraform.tfvars:
ado_pat_value = "new-token"
# Then:
./deploy.sh --layer application deploy
```

**Recommendation**: Use Option 1 or 2 to keep secrets out of Terraform state and version control.

## Security Considerations

### Why This Architecture?

1. **Secrets Not in Terraform State**
   - The `lifecycle.ignore_changes` prevents Terraform from storing the actual PAT in state
   - Secret values are injected post-deployment
   - Reduces risk of secret exposure through Terraform state

2. **Separation of Concerns**
   - Infrastructure team manages the secret infrastructure (Terraform)
   - Operations team manages secret content (config layer)
   - Clear responsibility boundaries

3. **Secret Rotation**
   - Easy to rotate PAT without re-running Terraform
   - No infrastructure changes needed for credential updates

4. **Encryption**
   - Secret encrypted at rest with KMS
   - IAM policies control access
   - ESO uses IRSA for secure AWS access

### Best Practices

✅ **DO**:
- Rotate PAT tokens regularly (every 90 days)
- Use the config layer to inject credentials
- Store PAT tokens in a password manager
- Use environment variables for automation
- Monitor secret access via CloudTrail

❌ **DON'T**:
- Store PAT tokens in `terraform.tfvars`
- Commit secrets to version control
- Use long-lived PAT tokens
- Share PAT tokens between teams
- Use full-scope PAT tokens (use minimum required scopes)

## Troubleshooting

### Secret Not Found

```bash
# Verify secret exists
aws secretsmanager describe-secret --secret-id ado-agent-pat

# If missing, deploy application layer
./deploy.sh --layer application deploy
```

### ExternalSecret Not Syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret -n ado-agents
kubectl describe externalsecret ado-pat -n ado-agents

# Check ClusterSecretStore
kubectl get clustersecretstore aws-secrets-manager
kubectl describe clustersecretstore aws-secrets-manager

# Check ESO logs
kubectl logs -n external-secrets-system deployment/external-secrets -f
```

### Wrong Secret Structure

```bash
# View current secret value
aws secretsmanager get-secret-value --secret-id ado-agent-pat --query SecretString --output text | jq

# Should have these keys:
# - personalAccessToken
# - organization
# - adourl

# Update with correct structure
./deploy.sh --layer config deploy
```

### Multiple Secrets Created

If you see multiple ADO secrets (e.g., `ado-agent-pat` and `eks/*/ado-pat`):

```bash
# List all ADO-related secrets
aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `ado`)]'

# The correct secret is the one managed by Terraform:
# - Name: ado-agent-pat (or custom name from tfvars)
# - Tags: ManagedBy=terraform

# Delete any orphaned secrets
aws secretsmanager delete-secret --secret-id <orphaned-secret-name> --force-delete-without-recovery
```

## References

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [External Secrets Operator](https://external-secrets.io/)
- [Azure DevOps PAT Tokens](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate)

---

**Last Updated**: October 20, 2025  
**Version**: 1.0  
**Status**: ✅ Active
