# Deploy Script Improvements

## Changes Overview

Two key improvements have been made to the `deploy.sh` orchestration script to enhance usability and reliability.

## 1. Kubectl Configuration with Alias Support

### Feature: `configure_kubectl_alias()`

A new utility function has been added to automatically configure kubectl access to the deployed EKS cluster with a custom context alias.

**Function Signature:**
```bash
configure_kubectl_alias <cluster_name> [region] [context_alias]
```

**Parameters:**
- `cluster_name` (required): The EKS cluster name
- `region` (optional): AWS region (defaults to `$AWS_REGION`)
- `context_alias` (optional): Custom context name (defaults to cluster name)

**Features:**
- Automatically runs `aws eks update-kubeconfig` with the `--alias` flag
- Sets up a named context in `~/.kube/config` for easy cluster switching
- Verifies cluster connectivity after configuration
- Provides helpful instructions for using the configured context
- Supports dry-run mode for testing

**Example Usage:**
```bash
# Configure with default alias (cluster name)
configure_kubectl_alias "my-eks-cluster"

# Configure with custom alias
configure_kubectl_alias "my-eks-cluster" "us-west-2" "production"
```

**Benefits:**
- **Multiple Clusters**: Easily manage multiple EKS clusters with distinct context names
- **No Overwrites**: Using aliases prevents overwriting existing kubeconfig entries
- **Quick Switching**: Switch between clusters using `kubectl config use-context <alias>`
- **Clear Identification**: Context names clearly identify which cluster you're working with

### Integration

The function is automatically called during base layer deployment:

```bash
validate_base_layer_deployment() {
    # ... cluster creation ...
    
    # Configure kubectl with cluster name as alias
    configure_kubectl_alias "$cluster_name" "$AWS_REGION" "$cluster_name"
}
```

### Usage Examples

After deployment, you can:

```bash
# View available contexts
kubectl config get-contexts

# Use the specific cluster
kubectl --context my-cluster-name get nodes

# Set as default context
kubectl config use-context my-cluster-name

# Switch between multiple clusters
kubectl config use-context dev-cluster
kubectl config use-context prod-cluster
```

## 2. Fail-Fast Error Handling

### Previous Behavior

When a layer deployment or destruction failed, the script would:
- In interactive mode: Ask "Continue with remaining layers?"
- In auto-approve mode: Exit immediately

This created inconsistent behavior and could lead to:
- Partially deployed infrastructure in unpredictable states
- Confusion about which layers succeeded vs failed
- Potential for cascading failures if continuing after errors

### New Behavior

The script now **always exits immediately** on any error, regardless of mode:

**Deploy Command:**
```bash
if ! deploy_layer "$layer" "$layer_dir"; then
    # Always exit on error - no option to continue
    log_error "Deployment failed at $layer layer"
    show_recovery_guidance "$layer" "${successful_layers[@]}"
    exit 1
fi
```

**Destroy Command:**
```bash
if ! destroy_layer "$layer" "$layer_dir"; then
    # Always exit on error - no option to continue
    log_error "Destruction halted at $layer layer"
    log_error "Failed to destroy layers: ${failed_layers[*]}"
    exit 1
fi
```

### Benefits

1. **Predictable Behavior**: Script behavior is consistent across all modes
2. **Prevents Cascading Failures**: Stops before attempting to deploy dependent layers
3. **Clear Error States**: Easy to identify exactly where the failure occurred
4. **Easier Recovery**: Recovery guidance shows clear state and next steps
5. **CI/CD Friendly**: Non-interactive behavior suitable for automation pipelines

### Error Recovery

When an error occurs, the script now:

1. **Immediately stops** execution
2. **Shows clear status** of which layers succeeded and which failed
3. **Provides recovery guidance** with specific commands to:
   - Fix the failed layer: `./deploy.sh --layer <failed_layer> deploy`
   - Check infrastructure status: `./deploy.sh status`
   - Review Terraform state: `cd infrastructure-layered/<layer> && terraform show`

### Example Error Output

```
Deployment Status:
  ✓ base
  ✗ middleware

Not yet deployed:
  ○ application

[ERROR] Deployment failed at middleware layer

Recovery Guidance:
================

Failed Layer: middleware
Successful Layers: base

To recover from this error:

1. Review the error messages above
2. Fix the issue in the middleware layer
3. Re-run deployment for the failed layer:
   ./deploy.sh --layer middleware deploy

4. Once fixed, continue with remaining layers:
   ./deploy.sh --layer application deploy

5. Or check current infrastructure status:
   ./deploy.sh status
```

## Migration Notes

### For Existing Scripts/Automation

If you had automation relying on the "continue on error" behavior:

**Before:**
```bash
# Would continue to next layer even if one failed
./deploy.sh deploy
```

**After:**
```bash
# Exits immediately on error
./deploy.sh deploy
# Add explicit error handling in your automation
if [ $? -ne 0 ]; then
    echo "Deployment failed, stopping"
    exit 1
fi
```

### For Interactive Users

The interactive prompts to "continue anyway" have been removed. If a layer fails:

1. Fix the issue
2. Re-run deployment for that specific layer: `./deploy.sh --layer <layer> deploy`
3. Continue with subsequent layers if needed

This is the **safer and more predictable** approach.

## Testing

Both changes have been validated:

### Kubectl Configuration Test

```bash
# Deploy base layer
./deploy.sh --layer base deploy

# Verify context was created
kubectl config get-contexts | grep <cluster-name>

# Test cluster access
kubectl --context <cluster-name> get nodes
```

### Error Handling Test

```bash
# Introduce an error in middleware layer
# (e.g., invalid Terraform configuration)

# Run deployment
./deploy.sh deploy

# Verify:
# 1. Script exits immediately on error
# 2. No prompt to continue
# 3. Clear error message displayed
# 4. Recovery guidance shown
```

## Related Documentation

- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Complete deployment procedures
- [Operations Guide](OPERATIONS_GUIDE.md) - Day 2 operations and maintenance
- [Troubleshooting Guide](TROUBLESHOOTING_GUIDE.md) - Common issues and solutions
