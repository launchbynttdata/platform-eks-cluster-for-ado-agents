# KEDA CloudEventSource Controller Issue and Fix

## Problem Description

When deploying KEDA 2.15.x with version 2.17.x container images, the KEDA operator pod enters a `CrashLoopBackOff` state with the following error:

```
ERROR controller-runtime.source.EventHandler if kind is a CRD, it should be installed before calling Start
{"kind": "ClusterCloudEventSource.eventing.keda.sh", "error": "no matches for kind \"ClusterCloudEventSource\" in version \"eventing.keda.sh/v1alpha1\""}
```

### Root Cause

The KEDA operator expects the `ClusterCloudEventSource` Custom Resource Definition (CRD) to be available, but this CRD is not installed by the KEDA Helm chart by default. The CloudEventSource feature is part of KEDA's eventing capabilities, which are optional and not commonly used in most deployments.

The issue occurs when:
1. There's a version mismatch between the Helm chart version and the container image tags
2. The operator starts with CloudEventSource controllers enabled by default
3. The required CRDs for these controllers are not installed

## Solution

We've implemented a configurable solution using Terraform variables to control CloudEventSource controllers.

### Configurable Variables

In `infrastructure-layered/middleware/terraform.tfvars`, you can configure:

```hcl
# KEDA Configuration
keda_version = "2.17.2"  # Use 2.17.2 or later for improved stability

# CloudEventSource controllers - disable if not using CloudEventSource resources
# These variables control whether KEDA watches for CloudEventSource CRDs
keda_enable_cloudeventsource         = false  # Default: disabled
keda_enable_cluster_cloudeventsource = false  # Default: disabled
```

### Default Behavior

By default, both CloudEventSource controllers are **disabled** to prevent CrashLoopBackOff when:
- CloudEventSource CRDs are not installed
- You don't need CloudEventSource functionality (typical for ADO agent autoscaling)
- Running KEDA 2.15.x or versions with this issue

The middleware layer automatically configures KEDA with these environment variables:
- `KEDA_ENABLE_CLOUDEVENTSOURCE_CONTROLLER`
- `KEDA_ENABLE_CLUSTERCLOUDEVENTSOURCE_CONTROLLER`

### When to Enable CloudEventSource

Set these to `true` only if you:
1. Have CloudEventSource CRDs installed in your cluster
2. Use KEDA's CloudEventSource for event-driven autoscaling
3. Need cloud event-based triggers for scaled objects

### Option 2: Align Helm Chart and Image Versions

Ensure that both the Helm chart version and container image tags use the same version:

```hcl
keda_version = "2.17.2"
```

## Implementation

### Changes Made

1. **Updated KEDA Operator Module** (`infrastructure/modules/primitive/keda-operator/`)
   - Added `env` variable to support passing environment variables to KEDA operator
   - Updated `main.tf` to pass environment variables to the Helm chart

2. **Updated Middleware Layer Variables** (`infrastructure-layered/middleware/variables.tf`)
   - Added `keda_enable_cloudeventsource` variable (default: `false`)
   - Added `keda_enable_cluster_cloudeventsource` variable (default: `false`)
   - Updated default `keda_version` to `2.17.2`

3. **Updated Middleware Layer Configuration** (`infrastructure-layered/middleware/`)
   - Modified `main.tf` to use configurable environment variables
   - Updated `terraform.tfvars` and `terraform.tfvars.sample` with new variables
   - Added documentation and comments explaining the configuration

### Files Modified

- `infrastructure/modules/primitive/keda-operator/variables.tf` - Added `env` variable
- `infrastructure/modules/primitive/keda-operator/main.tf` - Pass env vars to Helm
- `infrastructure-layered/middleware/variables.tf` - Added controller toggle variables
- `infrastructure-layered/middleware/main.tf` - Configure controllers via variables
- `infrastructure-layered/middleware/terraform.tfvars` - Set default values
- `infrastructure-layered/middleware/terraform.tfvars.sample` - Added sample configuration

### Benefits of This Approach

- **No Hard-Coding**: CloudEventSource controller states are configurable via Terraform variables
- **Flexibility**: Users can enable controllers if needed without modifying code
- **Safe Defaults**: Controllers disabled by default to prevent crashes
- **Clear Documentation**: Variables include descriptions explaining when to enable them
- **Version Consistency**: Updated to KEDA 2.17.2 for better stability

## How to Apply This Fix

After applying the fix, verify that the KEDA operator is running correctly:

```bash
# Check KEDA operator pod status
kubectl get pods -n keda-system

# Verify no CrashLoopBackOff
kubectl logs -n keda-system deployment/keda-operator --tail=50

# Confirm no CloudEventSource errors
kubectl logs -n keda-system deployment/keda-operator | grep -i cloudeventsource
```

Expected output: All KEDA pods should be in `Running` state with 1/1 ready.

### Redeployment Instructions

To apply this fix to an existing deployment:

```bash
cd infrastructure-layered/middleware

# Review the changes
terraform plan

# Apply the updates
terraform apply

# Monitor the KEDA operator rollout
kubectl rollout status deployment/keda-operator -n keda-system
```

The Helm release will be updated in-place, and Kubernetes will perform a rolling update of the KEDA operator deployment.

## References

- [KEDA GitHub Issue #5751](https://github.com/kedacore/keda/issues/5751) - CloudEventSource CRD issues
- [KEDA Documentation - Environment Variables](https://keda.sh/docs/latest/operate/cluster/#operator-configuration)
- [KEDA Eventing Documentation](https://keda.sh/docs/latest/concepts/eventing/)

## Additional Notes

### When to Use CloudEventSource

The CloudEventSource feature is only needed if you're using KEDA's CloudEvents integration for event-driven autoscaling. For standard Azure DevOps agent autoscaling based on pipeline queue depth, this feature is not required.

### Future Considerations

If you need to enable CloudEventSource functionality in the future:

1. Install the required CRDs manually before deploying KEDA
2. Set the configuration variables to `true`:
   ```hcl
   keda_enable_cloudeventsource         = true
   keda_enable_cluster_cloudeventsource = true
   ```
3. Redeploy using Terraform

### Version Compatibility

- KEDA 2.17.2+ includes better handling of optional CRDs
- Helm chart 2.17.2 aligns with container image version 2.17.2
- Earlier versions (2.15.x) may have CRD installation issues when used with newer image tags
