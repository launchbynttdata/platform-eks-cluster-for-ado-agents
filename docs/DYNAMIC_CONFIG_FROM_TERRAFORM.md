# Dynamic Configuration from Terraform Outputs

**Date:** October 20, 2025  
**Enhancement:** Config layer now reads values dynamically from Terraform  
**Status:** ✅ IMPLEMENTED

## Overview

Enhanced the config layer to dynamically read configuration values from Terraform outputs instead of using hardcoded values. This makes the deployment more robust and adaptable to different configurations.

## Problem

The initial config layer implementation used hardcoded values:
- ESO namespace: `external-secrets-system` (hardcoded)
- ESO ServiceAccount: `external-secrets` (hardcoded)
- ClusterSecretStore name: `aws-secrets-manager` (hardcoded)
- ADO agents namespace: `ado-agents` (hardcoded)
- ADO secret name: `ado-agent-pat` (hardcoded)

**Issues:**
- Breaks if infrastructure is deployed with different variable values
- Not maintainable - requires code changes if IaC variables change
- Doesn't respect terraform.tfvars customizations
- Not production-ready for teams with varying configurations

## Solution

### 1. Added Terraform Output

Added new output to `infrastructure-layered/middleware/outputs.tf`:

```terraform
output "eso_service_account_name" {
  description = "Name of the External Secrets Operator service account"
  value       = var.install_eso ? module.external_secrets_operator[0].service_account_name : "external-secrets"
}
```

This exposes the ESO ServiceAccount name from the module, with a fallback to the default value.

### 2. Created Helper Function

Added `get_eso_config_from_tf()` function to read Terraform outputs with fallbacks:

```bash
get_eso_config_from_tf() {
    local output_name="$1"
    local default_value="$2"
    local value=""
    
    # Try to get from middleware layer
    if [[ -d "$MIDDLEWARE_LAYER_DIR" ]]; then
        log_debug "Attempting to get $output_name from middleware layer..."
        
        # Initialize if needed
        if terraform_init "middleware" "$MIDDLEWARE_LAYER_DIR" &>/dev/null; then
            value=$(cd "$MIDDLEWARE_LAYER_DIR" && terraform output -raw "$output_name" 2>/dev/null || echo "")
        fi
    fi
    
    # Use default if not found
    if [[ -z "$value" ]]; then
        log_debug "Using default value for $output_name: $default_value"
        value="$default_value"
    fi
    
    echo "$value"
}
```

### 3. Updated Functions to Use Dynamic Values

#### ClusterSecretStore Creation

```bash
create_cluster_secret_store() {
    local region="$1"
    
    # Get ESO configuration from Terraform outputs
    local eso_namespace=$(get_eso_config_from_tf "eso_namespace" "external-secrets-system")
    local eso_sa_name=$(get_eso_config_from_tf "eso_service_account_name" "external-secrets")
    local css_name=$(get_eso_config_from_tf "cluster_secret_store_name" "aws-secrets-manager")
    
    log_info "ESO Configuration:"
    log_info "  Namespace: $eso_namespace"
    log_info "  ServiceAccount: $eso_sa_name"
    log_info "  ClusterSecretStore: $css_name"
    
    # Create manifest with dynamic values
    cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: ${css_name}
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${region}
      auth:
        jwt:
          serviceAccountRef:
            name: ${eso_sa_name}
            namespace: ${eso_namespace}
EOF
```

#### Deploy Config Layer

```bash
deploy_config_layer() {
    # ...
    
    # Get ESO configuration for later use in messages
    local css_name=$(get_eso_config_from_tf "cluster_secret_store_name" "aws-secrets-manager")
    local ado_namespace=$(get_eso_config_from_tf "ado_agents_namespace" "ado-agents")
   local ado_secret=$(get_eso_config_from_tf "ado_secret_name" "ado-agent-pat")
    
    # ...
    
    # Show next steps with dynamic values
    log "Next Steps:"
    log "  1. Verify ClusterSecretStore:"
    log "     kubectl get clustersecretstore $css_name"
    log ""
    log "  2. Verify ExternalSecret syncs:"
    log "     kubectl get externalsecret -n $ado_namespace"
    log "     kubectl get secret -n $ado_namespace $ado_secret"
    # ...
}
```

## Configuration Sources

The config layer now dynamically reads from these Terraform outputs:

| Configuration | Terraform Output | Default Fallback |
|--------------|------------------|------------------|
| ESO Namespace | `eso_namespace` | `external-secrets-system` |
| ESO ServiceAccount | `eso_service_account_name` | `external-secrets` |
| ClusterSecretStore Name | `cluster_secret_store_name` | `aws-secrets-manager` |
| ADO Agents Namespace | `ado_agents_namespace` | `ado-agents` |
| ADO Secret Name | `ado_secret_name` | `ado-agent-pat` |
| Cluster Name | `cluster_name` | (AWS EKS list) |
| AWS Region | `aws_region` | (from environment) |

## Benefits

### 1. Respects IaC Configuration
- Reads actual deployed values from Terraform state
- Honors terraform.tfvars customizations
- No code changes needed for different configurations

### 2. Robust Fallback Mechanism
- Uses Terraform outputs when available
- Falls back to sensible defaults if outputs unavailable
- Graceful degradation if middleware layer isn't initialized

### 3. Better Visibility
- Logs the configuration being used
- Clear indication of where values come from
- Easier debugging and troubleshooting

### 4. Production Ready
- Teams can customize via terraform.tfvars
- No hardcoded assumptions
- Works with varying deployment patterns

## Example Output

```bash
$ ./deploy.sh --layer config --skip-ado-secret deploy

[INFO] Deploying config layer (post-deployment configuration)...
[INFO] Detected cluster: poc-ado-agent-cluster
[INFO] Creating ClusterSecretStore for AWS Secrets Manager...
[INFO] ESO Configuration:
[INFO]   Namespace: external-secrets-system
[INFO]   ServiceAccount: external-secrets
[INFO]   ClusterSecretStore: aws-secrets-manager

clustersecretstore.external-secrets.io/aws-secrets-manager created
[SUCCESS] ClusterSecretStore created successfully
[SUCCESS] ClusterSecretStore is ready

Next Steps:
  1. Verify ClusterSecretStore:
     kubectl get clustersecretstore aws-secrets-manager
  
  2. Verify ExternalSecret syncs:
     kubectl get externalsecret -n ado-agents
   kubectl get secret -n ado-agents ado-agent-pat
```

## Testing

### Test with Default Configuration
```bash
./deploy.sh --layer config --skip-ado-secret deploy
# ✅ Uses values from middleware layer Terraform outputs
```

### Test with Custom Configuration
Update `infrastructure-layered/middleware/terraform.tfvars`:
```hcl
eso_namespace = "custom-eso-namespace"
cluster_secret_store_name = "custom-css-name"
```

Deploy middleware layer:
```bash
./deploy.sh --layer middleware deploy
```

Deploy config layer:
```bash
./deploy.sh --layer config deploy
# ✅ Automatically uses custom values
```

### Verification
```bash
$ kubectl get clustersecretstore
NAME                  AGE   STATUS   CAPABILITIES   READY
aws-secrets-manager   42s   Valid    ReadWrite      True
```

## Files Modified

1. **`infrastructure-layered/middleware/outputs.tf`**
   - Added `eso_service_account_name` output
   - Exposes ServiceAccount name from ESO module

2. **`infrastructure-layered/deploy.sh`**
   - Added `get_eso_config_from_tf()` helper function
   - Updated `create_cluster_secret_store()` to use dynamic values
   - Updated `deploy_config_layer()` to use dynamic values
   - Updated status check to use dynamic CSS name
   - Updated next-steps guidance to use dynamic values

## Future Enhancements

1. **Cache Terraform Outputs**
   - Call `terraform output -json` once and parse
   - Avoid multiple terraform init/output calls
   - Improve performance

2. **Validate Configuration**
   - Check that ServiceAccount exists before creating CSS
   - Verify namespace exists
   - Warn if configuration seems unusual

3. **Support Multiple Clusters**
   - Handle environments with multiple EKS clusters
   - Add cluster selection prompt or flag

4. **Export Configuration**
   - Save detected configuration to file
   - Enable re-running without re-initializing Terraform

## Related Documentation

- `docs/CONFIG_LAYER_INTEGRATION.md` - Original config layer integration
- `docs/FIX_CLUSTERSECRETSTORE_CONFIG.md` - ClusterSecretStore fix
- `infrastructure-layered/middleware/outputs.tf` - Terraform outputs
- `modules/primitive/external-secrets-operator/` - ESO module

## Conclusion

The config layer is now production-ready and respects the IaC configuration. Teams can customize their deployments via `terraform.tfvars` without needing to modify the deployment scripts. The robust fallback mechanism ensures the script works even if Terraform outputs are temporarily unavailable.

This enhancement makes the deployment tooling more shareable and suitable for diverse team environments.
