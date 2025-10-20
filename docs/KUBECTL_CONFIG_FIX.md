# kubectl Configuration Fix for Fresh Deployments

## Problem

When deploying a fresh cluster from scratch, the middleware layer validation failed with:

```
error: error validating "/var/folders/...": failed to download openapi: 
Get "https://[CLUSTER_ID].gr7.us-west-2.eks.amazonaws.com/openapi/v2?timeout=32s": 
dial tcp: lookup [CLUSTER_ID].gr7.us-west-2.eks.amazonaws.com: no such host
```

### Root Causes

1. **kubectl not configured**: The base layer deployed the EKS cluster but didn't ensure kubectl was properly configured before middleware validation ran
2. **No cluster readiness check**: The script didn't wait for the EKS cluster to reach ACTIVE state
3. **Silent failures**: `configure_kubectl_alias` could fail but validation continued anyway
4. **Timing issue**: Middleware validation attempted to use kubectl before the cluster was ready

## Solution

Modified `infrastructure-layered/deploy.sh` with the following changes:

### 1. Enhanced `validate_base_layer_deployment()` (lines ~1509-1573)

**Added:**
- ✅ Wait for EKS cluster to reach ACTIVE status (with 5-minute timeout)
- ✅ Fail fast if kubectl configuration fails (don't proceed to middleware)
- ✅ Verify kubectl can communicate with cluster before continuing
- ✅ Better error messages and logging

**Implementation:**
```bash
validate_base_layer_deployment() {
    # ... existing cluster name detection ...
    
    # NEW: Wait for cluster to be ACTIVE
    log_info "Waiting for EKS cluster to be active..."
    local max_wait=300  # 5 minutes
    while [[ $elapsed -lt $max_wait ]]; do
        local cluster_status=$(aws eks describe-cluster ...)
        if [[ "$cluster_status" == "ACTIVE" ]]; then
            break
        fi
        sleep 10
    done
    
    # NEW: Check if kubectl configuration succeeded
    if ! configure_kubectl_alias "$cluster_name" "$AWS_REGION" "$cluster_name"; then
        log_error "Failed to configure kubectl"
        return 1  # STOP deployment
    fi
    
    # NEW: Verify kubectl can actually communicate
    if ! kubectl cluster-info &>/dev/null; then
        log_error "kubectl configured but cannot communicate with cluster"
        return 1
    fi
    
    log_success "Cluster is ready and kubectl is configured"
}
```

### 2. Improved `configure_kubectl_alias()` (lines ~447-480)

**Changed:**
- ✅ Better error messages (show actual AWS CLI output instead of suppressing with `2>/dev/null`)
- ✅ Added timeout to cluster connectivity test (30 seconds)
- ✅ More helpful error guidance for troubleshooting
- ✅ Changed log_warning to log_error for actual failures

**Before:**
```bash
if ! aws eks update-kubeconfig ... 2>/dev/null; then
    log_warning "Failed to configure kubectl"  # Continued anyway!
    return 1
fi
```

**After:**
```bash
if ! aws eks update-kubeconfig ... 2>&1 | grep -v "Updated context"; then
    log_error "Failed to configure kubectl"
    log_error "Please check that:"
    log_error "  - AWS credentials are valid"
    log_error "  - Cluster exists"
    return 1
fi
```

## Deployment Flow (Updated)

### Fresh Deployment

```
1. Base Layer Deploy
   ├─ Terraform creates EKS cluster
   ├─ Terraform creates node groups
   └─ Post-deploy validation:
      ├─ Wait for cluster status = ACTIVE ⏱️
      ├─ Configure kubectl access ✓
      ├─ Verify connectivity ✓
      └─ FAIL if any step fails ❌

2. Middleware Layer Deploy (only runs if base succeeded)
   ├─ Terraform deploys KEDA, ESO, buildkitd
   └─ Post-deploy validation:
      ├─ kubectl now works! ✓
      ├─ Check KEDA deployment ✓
      ├─ Check ESO deployment ✓
      └─ Deploy cluster autoscaler ✓

3. Application Layer Deploy
   └─ kubectl still works ✓

4. Config Layer Deploy
   └─ kubectl still works ✓
```

### Re-deployment (No Changes)

```
1. Base Layer - No changes
   ├─ terraform plan = 0 changes
   └─ Still runs validation:
      ├─ Cluster already ACTIVE ⚡
      ├─ kubectl already configured ⚡
      └─ Quick verification ✓

2. Middleware Layer - Continues as normal
```

## Testing

### Test Scenario 1: Fresh Deployment
```bash
# Destroy existing cluster
./deploy.sh destroy

# Deploy from scratch
./deploy.sh deploy
```

**Expected Output:**
```
[INFO] Waiting for EKS cluster to be active...
[SUCCESS] EKS cluster is active
[INFO] Configuring kubectl access...
[SUCCESS] Successfully configured kubectl with context alias: poc-ado-agent-cluster
[INFO] Verifying cluster connectivity...
[SUCCESS] Cluster is ready and kubectl is configured
[INFO] Validating middleware layer deployment...
[INFO] Deploying Cluster Autoscaler...
[SUCCESS] Cluster autoscaler deployed successfully
```

### Test Scenario 2: Re-run on Existing Cluster
```bash
./deploy.sh deploy
```

**Expected:** Should complete quickly, all validations pass

## Dependencies

This fix ensures proper ordering:

1. **Base layer** → EKS cluster ACTIVE → kubectl configured ✓
2. **Middleware layer** → Requires kubectl ✓ (now guaranteed)
3. **Application layer** → Requires kubectl ✓ (now guaranteed)
4. **Config layer** → Requires kubectl ✓ (now guaranteed)

## Files Modified

- `infrastructure-layered/deploy.sh`
  - `validate_base_layer_deployment()` - Enhanced with readiness checks
  - `configure_kubectl_alias()` - Better error handling

## Related Issues Fixed

- ✅ Cluster autoscaler deployment now works on fresh deployments
- ✅ KEDA validation no longer fails with "no such host"
- ✅ ESO validation works correctly
- ✅ Config layer can properly create ClusterSecretStore

## Rollback

If this causes issues, revert by:
1. Removing cluster readiness wait loop
2. Removing `return 1` checks after kubectl configuration
3. Restoring `2>/dev/null` error suppression

However, this would bring back the original bug where fresh deployments fail at middleware validation.
