# Post-Deploy Script Restructure - Summary

## Changes Made

### 1. Moved Post-Deploy Script

**From:** `infrastructure-layered/middleware/post-deploy-middleware.sh`  
**To:** `infrastructure-layered/post-deploy.sh`

**Reason:** The script should be run after ALL infrastructure layers are deployed, not just middleware. Moving it to the root infrastructure-layered directory makes this clearer and aligns with the `deploy.sh` script location.

---

### 2. Updated Script Functionality

#### New Prerequisites Check
- Added `check_layer_deployment()` function
- Verifies all three layers are deployed before proceeding:
  - Base layer
  - Middleware layer  
  - Application layer
- Provides clear error message if any layer is missing

#### Enhanced AWS Region Detection
- Now checks all three layers for AWS region (base → middleware → application)
- Falls back to AWS CLI configuration
- Supports `TF_STATE_REGION` environment variable (from deploy.sh)
- Compatible with deploy.sh AWS CLI configuration

#### New Command-Line Options
- `--pat TOKEN` - Provide ADO PAT token directly
- `--org-url URL` - Provide ADO organization URL directly
- `--verify-only` - Skip ClusterSecretStore creation and secret injection, only verify
- Removed `--non-interactive` flag (not needed with --pat and --org-url)

#### Updated Directory References
```bash
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="$SCRIPT_DIR/base"
readonly MIDDLEWARE_DIR="$SCRIPT_DIR/middleware"
readonly APPLICATION_DIR="$SCRIPT_DIR/application"
```

---

### 3. Updated Workflow

#### Old Workflow
```bash
# Deploy layers
./deploy.sh --layer base deploy
./deploy.sh --layer middleware deploy

# Run post-deploy (from middleware directory)
cd middleware
./post-deploy-middleware.sh

# Then deploy application
cd ..
./deploy.sh --layer application deploy
```

#### New Workflow
```bash
# Deploy ALL layers first
./deploy.sh --layer all deploy

# Then run post-deploy (from infrastructure-layered directory)
./post-deploy.sh
```

**Benefits:**
- Clearer workflow: deploy everything, then configure
- All layers are guaranteed to be in place
- Consistent with typical infrastructure deployment patterns
- Post-deploy script location matches deploy script location

---

### 4. Documentation Updates

#### middleware/README.md
- Updated to reflect new script location
- Clarified that post-deploy runs AFTER all layers
- Simplified instructions to point to centralized script

#### docs/OPERATIONS.md
- Renamed section from "Middleware Layer Post-Deployment" to "Complete Infrastructure Post-Deployment"
- Updated script path and commands
- Added prerequisite check information
- Updated "What the Script Does" to include layer verification

---

### 5. AWS CLI Configuration Compatibility

The post-deploy script now inherits AWS configuration from the deploy.sh environment:

**Environment Variables Supported:**
- `AWS_REGION` - AWS region (auto-detected or from deploy.sh)
- `AWS_PROFILE` - AWS CLI profile (inherited from shell environment)
- `TF_STATE_REGION` - Terraform state bucket region (from deploy.sh)

**Auto-Detection Order:**
1. Command-line flag (`--region`)
2. Terraform outputs (base → middleware → application layers)
3. AWS CLI default region
4. `TF_STATE_REGION` environment variable

This ensures the post-deploy script uses the same AWS configuration as deploy.sh.

---

## Usage Examples

### Basic Interactive Mode
```bash
cd infrastructure-layered
./post-deploy.sh
```

### With Explicit Credentials
```bash
./post-deploy.sh \
    --pat "your-ado-pat-token" \
    --org-url "https://dev.azure.com/your-org"
```

### Verification Only
```bash
./post-deploy.sh --verify-only
```

### With Specific Cluster/Region
```bash
./post-deploy.sh \
    --cluster-name my-eks-cluster \
    --region us-west-2
```

---

## Migration Guide

### For Existing Deployments

If you have already deployed the middleware layer with the old script:

1. **Script is already run**: No action needed, ClusterSecretStore and secrets are already configured

2. **Need to run again**: Use the new script location
   ```bash
   cd infrastructure-layered
   ./post-deploy.sh --verify-only  # Just verify
   ```

3. **Fresh deployment**: Follow the new workflow
   ```bash
   ./deploy.sh --layer all deploy
   ./post-deploy.sh
   ```

---

## Files Modified

### Created/Moved
- `infrastructure-layered/post-deploy.sh` (moved from middleware/)

### Updated
- `infrastructure-layered/middleware/README.md` - Updated post-deploy instructions
- `docs/OPERATIONS.md` - Updated workflow and commands

### Removed
- `infrastructure-layered/middleware/post-deploy-middleware.sh` (moved to parent directory)

---

## Benefits

✅ **Clearer Workflow** - Deploy all, then configure  
✅ **Better Organization** - Script location matches deploy.sh  
✅ **Safer** - Verifies all layers before proceeding  
✅ **Consistent** - Uses same AWS configuration as deploy.sh  
✅ **Flexible** - Supports both interactive and non-interactive modes  
✅ **Robust** - Enhanced error checking and validation
