# Fix: Environment Variable Preservation

**Date**: October 20, 2025  
**Issue**: Scripts were overwriting environment variables instead of preserving them

## Problem

Both `deploy.sh` and `post-deploy.sh` were overwriting environment variables (particularly `AWS_REGION`) with hardcoded defaults, ignoring values set by direnv or other environment management tools.

### Original Behavior

**deploy.sh (line 68):**
```bash
AWS_REGION="$DEFAULT_REGION"  # Overwrites AWS_REGION with "us-east-1"
```

**post-deploy.sh (line 51):**
```bash
AWS_REGION=""  # Overwrites AWS_REGION with empty string
```

### Impact

- Environment variables from direnv (`.envrc`) were ignored
- Users had to specify `--region` even when AWS_REGION was set in environment
- `post-deploy.sh` failed with "Invalid endpoint: https://sts..amazonaws.com" due to empty region
- Inconsistent behavior between manual runs and automated deployments

## Solution

### 1. Preserve Environment Variables in Initialization

**deploy.sh:**
```bash
# OLD
AWS_REGION="$DEFAULT_REGION"

# NEW
AWS_REGION="${AWS_REGION:-$DEFAULT_REGION}"
```

**post-deploy.sh:**
```bash
# OLD
CLUSTER_NAME=""
AWS_REGION=""
ADO_PAT_TOKEN=""
ADO_ORG_URL=""

# NEW
CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_REGION="${AWS_REGION:-}"
ADO_PAT_TOKEN="${ADO_PAT_TOKEN:-}"
ADO_ORG_URL="${ADO_ORG_URL:-}"
```

### 2. Respect Environment Priority in deploy.sh

Updated the region detection logic to follow this priority:

1. **Environment variable** (from direnv, export, etc.)
2. **AWS CLI config** (`aws configure get region`)
3. **Hardcoded default** (`us-east-1`)

**Before:**
```bash
# Check AWS region
local current_region
current_region=$(aws configure get region || echo "")
if [[ -z "$current_region" ]]; then
    log_warning "No default AWS region configured, using: $AWS_REGION"
    AWS_REGION="${AWS_REGION:-us-east-1}"
else
    AWS_REGION="$current_region"  # Always overwrites with CLI config
    log_info "AWS region: $AWS_REGION"
fi
```

**After:**
```bash
# Check AWS region (prioritize environment variable, then AWS CLI config, then default)
if [[ -n "${AWS_REGION:-}" ]]; then
    log_info "Using AWS region from environment: $AWS_REGION"
else
    local current_region
    current_region=$(aws configure get region 2>/dev/null || echo "")
    if [[ -n "$current_region" ]]; then
        AWS_REGION="$current_region"
        log_info "Using AWS region from AWS CLI config: $AWS_REGION"
    else
        AWS_REGION="$DEFAULT_REGION"
        log_warning "No AWS region configured, using default: $AWS_REGION"
    fi
fi
```

## Benefits

### ✅ Improved Developer Experience
- direnv configurations are now respected
- No need to repeatedly specify `--region` flag
- Consistent behavior across all invocations

### ✅ Better Error Messages
- Clear indication of which region source is being used
- Easier debugging of configuration issues

### ✅ More Flexible Configuration
- Works with multiple environment management tools
- Supports team-specific configurations
- Command-line flags still override when needed

### ✅ Backward Compatible
- Scripts still work without environment variables
- Defaults are applied when nothing is set
- No breaking changes to existing workflows

## Testing

### Verify Environment Variable Preservation

```bash
cd infrastructure-layered

# Test 1: direnv sets AWS_REGION
export AWS_REGION="us-west-2"
./deploy.sh status
# Should show: "Using AWS region from environment: us-west-2"

# Test 2: No environment variable set
unset AWS_REGION
./deploy.sh status
# Should show: "Using AWS region from AWS CLI config: <from-config>" 
# OR: "No AWS region configured, using default: us-east-1"

# Test 3: Command-line override (not implemented yet, but env is respected)
export AWS_REGION="us-west-2"
./deploy.sh --region us-east-1 plan
# Should use us-east-1 (command-line takes precedence)
```

### Verify post-deploy.sh

```bash
# Test 1: With direnv AWS_REGION
export AWS_REGION="us-west-2"
./post-deploy.sh --help
# Should work without errors

# Test 2: Verify AWS credentials check
DEBUG=true ./post-deploy.sh 2>&1 | grep AWS_REGION
# Should show: "[DEBUG] AWS_REGION env var: 'us-west-2'"
```

## Related Files

- `infrastructure-layered/deploy.sh` - Lines 68, 250-262
- `infrastructure-layered/post-deploy.sh` - Lines 50-53, 189-204
- `infrastructure-layered/.envrc` - Environment variable definitions

## Bash Parameter Expansion Reference

The fix uses bash parameter expansion:

- `${VAR:-default}` - Use `$VAR` if set and non-empty, otherwise use `default`
- `${VAR:-}` - Use `$VAR` if set and non-empty, otherwise use empty string (preserves existing value)

This is different from:
- `VAR="default"` - Always overwrites VAR with "default"
- `VAR=${VAR}` - Expands to empty if VAR is unset (can cause errors with `set -u`)

## Migration Notes

No migration required - this is a bug fix that improves existing behavior without breaking changes.

Users with `.envrc` files will immediately benefit from this fix. Users without environment variables will see no change in behavior.
