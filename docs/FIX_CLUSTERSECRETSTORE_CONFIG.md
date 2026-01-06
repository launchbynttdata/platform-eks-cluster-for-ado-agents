# ClusterSecretStore Configuration Fix

**Date:** October 20, 2025  
**Issue:** ClusterSecretStore InvalidProviderConfig error  
**Status:** ✅ RESOLVED

## Problem

The ClusterSecretStore was failing with `InvalidProviderConfig` status:

```bash
$ kubectl get clustersecretstore
NAME                  AGE     STATUS                  CAPABILITIES   READY
aws-secrets-manager   2m36s   InvalidProviderConfig                  False
```

Error message from `kubectl describe`:
```
Message: unable to create session: ServiceAccount "external-secrets-sa" not found
```

## Root Cause

The `create_cluster_secret_store()` function in `deploy.sh` was using hardcoded values that didn't match the actual deployment:

**Incorrect Configuration:**
```yaml
serviceAccountRef:
  name: external-secrets-sa          # Wrong name
  namespace: external-secrets-operator  # Wrong namespace
```

**Actual Deployment:**
- **Namespace:** `external-secrets-system` (not `external-secrets-operator`)
- **ServiceAccount:** `external-secrets` (not `external-secrets-sa`)

## Investigation

1. Checked ClusterSecretStore status:
   ```bash
   kubectl describe clustersecretstore aws-secrets-manager
   # Error: ServiceAccount "external-secrets-sa" not found
   ```

2. Listed namespaces:
   ```bash
   kubectl get namespaces | grep secret
   # Found: external-secrets-system (not external-secrets-operator)
   ```

3. Checked ServiceAccounts:
   ```bash
   kubectl get serviceaccount -n external-secrets-system
   # Found: external-secrets (not external-secrets-sa)
   ```

4. Verified middleware layer configuration:
   ```bash
   grep eso_namespace infrastructure-layered/middleware/terraform.tfvars
   # eso_namespace = "external-secrets-system"  ✓ Correct
   ```

5. Checked ESO module defaults:
   ```terraform
   variable "service_account_name" {
     default = "external-secrets"  # ✓ Correct
   }
   ```

## Solution

Updated `deploy.sh` line 1008-1028 to use correct namespace and ServiceAccount name:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${region}
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets        # ✓ Fixed
            namespace: external-secrets-system  # ✓ Fixed
```

## Verification

After redeploying the config layer:

```bash
$ kubectl get clustersecretstore aws-secrets-manager
NAME                  AGE   STATUS   CAPABILITIES   READY
aws-secrets-manager   7s    Valid    ReadWrite      True
```

```bash
$ kubectl describe clustersecretstore aws-secrets-manager
...
  Service Account Ref:
    Name:       external-secrets
    Namespace:  external-secrets-system
  Region:           us-west-2
  Service:          SecretsManager
Status:
  Capabilities:  ReadWrite
  Conditions:
    Message:  store validated
    Reason:   Valid
    Status:   True
    Type:     Ready
```

✅ **Status: Valid**  
✅ **Ready: True**  
✅ **Capabilities: ReadWrite**

## Files Modified

- `infrastructure-layered/deploy.sh` - Lines 1008-1028
  - Changed `external-secrets-sa` → `external-secrets`
  - Changed `external-secrets-operator` → `external-secrets-system`

## Impact

- ClusterSecretStore now successfully validates
- External Secrets Operator can now access AWS Secrets Manager
- ExternalSecret resources can sync secrets from AWS to Kubernetes
- No changes required to Terraform configuration (it was already correct)

## Prevention

To prevent similar issues in the future:

1. **Don't Hardcode Values:** Should read namespace/SA from Terraform outputs or environment
2. **Add Validation:** Config layer could validate ESO deployment before creating ClusterSecretStore
3. **Documentation:** Document the expected namespace and ServiceAccount names
4. **Testing:** Include ClusterSecretStore validation in deployment tests

## Related

- Original implementation: `docs/CONFIG_LAYER_INTEGRATION.md`
- ESO module: `infrastructure/modules/primitive/external-secrets-operator/`
- Middleware layer: `infrastructure-layered/middleware/main.tf` (lines 257-280)
