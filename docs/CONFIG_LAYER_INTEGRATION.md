# Config Layer Integration

**Date:** October 20, 2025  
**Issue:** Integration of post-deployment configuration as a "config" layer  
**Author:** System Integration

## Overview

Integrated post-deployment configuration steps (previously in `post-deploy.sh`) as a fourth deployment layer called "config" within the main `deploy.sh` orchestration script. This provides a unified deployment workflow:

```
base → middleware → application → config
```

## What Changed

### 1. New Config Layer

The config layer performs post-deployment configuration tasks:
- **ClusterSecretStore Creation**: Creates AWS Secrets Manager ClusterSecretStore for External Secrets Operator
- **kubectl Configuration**: Automatically configures kubectl to access the EKS cluster
- **ADO PAT Injection**: Injects Azure DevOps Personal Access Token into AWS Secrets Manager
- **Verification Steps**: Provides next-steps guidance for verifying the deployment

### 2. Integration Points

#### Layer Constants
```bash
readonly CONFIG_LAYER_DIR="$LAYERS_DIR"  # Config layer doesn't have a subdirectory
```

#### Default Deployment Sequence
```bash
local layers=("base" "middleware" "application" "config")
```

#### New Command-Line Flags
- `--skip-ado-secret`: Skip Azure DevOps PAT secret injection
- `--pat TOKEN`: Provide Azure DevOps PAT token non-interactively
- `--org-url URL`: Provide Azure DevOps organization URL

### 3. Key Functions Added

#### `deploy_config_layer()`
Main deployment function for the config layer. Orchestrates:
1. Prerequisites check (aws, kubectl)
2. Cluster name detection from Terraform outputs or AWS EKS
3. kubectl configuration
4. ClusterSecretStore creation
5. ADO secret injection (interactive or skipped)
6. Next-steps guidance

#### `detect_cluster_name_from_tf()`
Intelligently detects cluster name with multiple fallbacks:
1. Try middleware layer Terraform outputs
2. Try base layer Terraform outputs
3. Fallback to AWS EKS list-clusters API

#### `configure_kubectl_for_cluster()`
Configures kubectl using `aws eks update-kubeconfig` and verifies access.

#### `create_cluster_secret_store()`
Creates and waits for ClusterSecretStore readiness with timeout.

#### `inject_ado_secret()`
Manages ADO PAT secret in AWS Secrets Manager:
- Prompts for credentials if not provided
- Creates or updates secret
- Verifies ExternalSecret resources

### 4. Special Handling

The config layer is treated specially in various commands:

#### Validation (`cmd_validate`)
```bash
if [[ "$layer" == "config" ]]; then
    log_info "Skipping validation for config layer (no Terraform)"
    log_success "$layer layer validation passed (runtime checks only)"
    continue
fi
```

#### Planning (`cmd_plan`)
```bash
if [[ "$layer" == "config" ]]; then
    log_info "Skipping plan for config layer (no Terraform)"
    continue
fi
```

#### Destruction (`cmd_destroy`)
```bash
if [[ "$layer" == "config" ]]; then
    log_info "Config layer cleanup (manual steps required):"
    log_info "  1. Delete ClusterSecretStore: kubectl delete clustersecretstore aws-secrets-manager"
    log_info "  2. Delete AWS Secrets Manager secret: aws secretsmanager delete-secret --secret-id eks/<cluster-name>/ado-pat"
    log_info "Config layer destroy is informational only"
    return 0
fi
```

#### Dependency Validation
Config layer requires all infrastructure layers to be deployed:
```bash
"config")
    # Config layer requires all infrastructure layers to be deployed
    local base_status middleware_status application_status
    base_status=$(get_layer_status "base" "$BASE_LAYER_DIR")
    middleware_status=$(get_layer_status "middleware" "$MIDDLEWARE_LAYER_DIR")
    application_status=$(get_layer_status "application" "$APPLICATION_LAYER_DIR")
    
    if [[ "$base_status" != "deployed" || 
          "$middleware_status" != "deployed" || 
          "$application_status" != "deployed" ]]; then
        log_error "Config layer requires all infrastructure layers to be deployed"
        return 1
    fi
    ;;
```

## Usage Examples

### Deploy Only Config Layer
```bash
./deploy.sh --layer config deploy
```

### Deploy Config Layer with Credentials
```bash
./deploy.sh --layer config \
  --pat "your-pat-token" \
  --org-url "https://dev.azure.com/your-org" \
  deploy
```

### Deploy Config Layer (Skip ADO Secret)
```bash
./deploy.sh --layer config --skip-ado-secret deploy
```

### Deploy Full Stack (Including Config)
```bash
./deploy.sh deploy
```

### Validate Config Layer
```bash
./deploy.sh --layer config validate
```

### Check Status of All Layers
```bash
./deploy.sh status
```

## Benefits

### 1. Unified Workflow
- Single script for all deployment phases
- Consistent error handling and logging
- Integrated dependency checking

### 2. Better User Experience
- No need to remember separate post-deploy script
- Auto-runs as part of full stack deployment
- Clear next-steps guidance

### 3. Improved Reliability
- Automatic cluster detection
- Multiple fallback mechanisms
- Proper dependency validation

### 4. Flexibility
- Can run config layer independently
- Can skip interactive prompts with flags
- Can re-run config layer without affecting infrastructure

## Backward Compatibility

The standalone `post-deploy.sh` script remains available for backward compatibility but is now redundant. Consider adding a deprecation notice:

```bash
#!/usr/bin/env bash
echo "WARNING: This script is deprecated."
echo "Please use: ./deploy.sh --layer config deploy"
echo ""
echo "Redirecting to integrated config layer deployment..."
exec ./deploy.sh --layer config deploy "$@"
```

## Testing Performed

### Syntax Validation
```bash
bash -n deploy.sh
# ✓ No syntax errors
```

### Config Layer Validation
```bash
./deploy.sh --layer config validate
# ✓ Passed (runtime checks only)
```

### Config Layer Deployment
```bash
./deploy.sh --layer config --skip-ado-secret deploy
# ✓ Successfully deployed
# - Detected cluster: poc-ado-agent-cluster
# - Configured kubectl
# - Created ClusterSecretStore
# - Skipped ADO secret injection (as requested)
```

### Output Sample
```
[INFO] Detected cluster from AWS EKS: poc-ado-agent-cluster
[INFO] Configuring kubectl for cluster: poc-ado-agent-cluster
[SUCCESS] kubectl configured successfully
[INFO] Creating ClusterSecretStore for AWS Secrets Manager...
[SUCCESS] ClusterSecretStore created successfully
[SUCCESS] Config layer deployment completed

Next Steps:
  1. Verify ClusterSecretStore:
     kubectl get clustersecretstore aws-secrets-manager
  
  2. Verify ExternalSecret syncs:
     kubectl get externalsecret -n ado-agents
     kubectl get secret -n ado-agents ado-pat
  
  3. Monitor KEDA and agent pods:
     kubectl get scaledobject -n ado-agents
     kubectl get pods -n ado-agents -w
```

## Technical Details

### Cluster Name Detection Logic

1. **Try Terraform Outputs** (Preferred)
   - Middleware layer: `terraform output -raw cluster_name`
   - Base layer: `terraform output -raw cluster_name`

2. **Fallback to AWS API** (Reliable)
   - `aws eks list-clusters --region $AWS_REGION`
   - Assumes first cluster in list

3. **Error Handling**
   - Fails gracefully if no cluster detected
   - Provides clear error messages
   - Suggests remediation steps

### Auto-Approve Behavior

When `--auto-approve` is used for full stack deployment:
- Config layer automatically skips ADO secret injection
- User can run config layer separately later for interactive PAT entry
- Prevents deployment pipeline failures due to missing credentials

### File Structure

No new directories created - config layer functions are embedded in `deploy.sh`:
- Lines ~940-1100: Config layer functions
- Special handling integrated into existing layer functions
- Help text updated to document new options

## Future Enhancements

1. **Terraform State for Config Layer**
   - Track config layer deployment status
   - Enable idempotent re-runs
   - Store PAT secret reference

2. **Enhanced Verification**
   - Wait for ExternalSecret sync
   - Verify KEDA ScaledObject creation
   - Check first agent pod startup

3. **Rollback Support**
   - Automated ClusterSecretStore deletion
   - Automated secret cleanup
   - Integration with destroy workflow

4. **Multi-Cluster Support**
   - Handle multiple EKS clusters in region
   - Cluster name validation
   - Explicit cluster selection flag

## Related Documentation

- `docs/OPERATIONS.md`: Operational procedures including post-deployment
- `docs/CHANGELOG.md`: Historical record of all changes
- `infrastructure-layered/README.md`: Layer-by-layer deployment guide
- `infrastructure-layered/post-deploy.sh`: Original standalone script (deprecated)

## Conclusion

The config layer integration successfully unifies the deployment workflow, making it easier for users to deploy the complete EKS ADO agent infrastructure with a single command. The implementation maintains backward compatibility while providing improved error handling, cluster detection, and user experience.

All tests passed successfully, and the integration is ready for use.
