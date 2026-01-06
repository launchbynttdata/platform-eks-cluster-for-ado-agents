# Terraform Backend Configuration Refactoring

## Problem

The original deployment script used `sed` to rewrite `main.tf` files, replacing placeholders like `TF_STATE_BUCKET_PLACEHOLDER` and `TF_STATE_REGION_PLACEHOLDER` with actual values from environment variables. This approach had several problems:

1. **Modifies source files** - Creates git diffs
2. **Fragile** - Script interruption could leave files in modified state
3. **Complex** - Required paired substitute/restore calls around every terraform operation
4. **Non-standard** - Not the Terraform-recommended approach
5. **Error-prone** - Different sed syntax on macOS vs Linux

## Solution

Migrated to **Terraform's native partial backend configuration** using `-backend-config` flags during `terraform init`.

### Reference

Per [Terraform documentation](https://developer.hashicorp.com/terraform/language/backend#partial-configuration):

> You do not need to specify every required argument in the backend configuration. Omitting certain arguments may be desirable if some arguments are provided automatically by an automation script running Terraform.

## Changes Made

### 1. Updated `terraform_init()` Function

**Before:**
```bash
terraform_init() {
    # Substitute bucket placeholder before init
    substitute_bucket_placeholder "$layer_dir"
    terraform init -reconfigure
    # Restore placeholder after init
    restore_bucket_placeholder "$layer_dir"
}
```

**After:**
```bash
terraform_init() {
    terraform init -reconfigure \
        -backend-config="bucket=$TF_STATE_BUCKET" \
        -backend-config="region=$TF_STATE_REGION"
}
```

### 2. Removed Substitute/Restore from All Functions

Removed `substitute_bucket_placeholder` and `restore_bucket_placeholder` calls from:
- ✅ `terraform_init()`
- ✅ `terraform_validate()`
- ✅ `terraform_plan()`
- ✅ `terraform_apply()`
- ✅ `terraform_destroy()`
- ✅ `terraform_output()`
- ✅ `get_layer_status()`

### 3. Updated `main.tf` Files

**Before:**
```hcl
terraform {
  backend "s3" {
    bucket = "TF_STATE_BUCKET_PLACEHOLDER"
    key    = "base/terraform.tfstate"
    region = "TF_STATE_REGION_PLACEHOLDER"
    encrypt      = true
    use_lockfile = true
  }
}
```

**After:**
```hcl
terraform {
  backend "s3" {
    bucket = ""  # Provided via -backend-config="bucket=..."
    key    = "base/terraform.tfstate"
    region = ""  # Provided via -backend-config="region=..."
    encrypt      = true
    use_lockfile = true
  }
}
```

### 4. Updated `terraform_output()` Helper

Now ensures backend config is passed when auto-initializing:
```bash
terraform init -backend=true -upgrade=false \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="region=$TF_STATE_REGION"
```

### 5. Fixed kubectl Configuration

Fixed `configure_kubectl_alias()` to properly capture AWS CLI output instead of using problematic `grep -v`:

**Before:**
```bash
if ! aws eks update-kubeconfig ... 2>&1 | grep -v "Updated context"; then
    # Failed
fi
```

**After:**
```bash
if ! update_output=$(aws eks update-kubeconfig ... 2>&1); then
    log_error "AWS CLI output: $update_output"
    # Failed
fi
```

## Benefits

### 1. **No File Modification**
- Source files remain unchanged
- No git diffs from backend configuration
- Safe to interrupt at any time

### 2. **Terraform Standard**
- Uses official Terraform partial configuration feature
- Aligns with HashiCorp best practices
- Better documented and supported

### 3. **Simpler Code**
- Removed ~100 lines of substitute/restore logic
- Eliminated macOS vs Linux sed compatibility issues
- Clearer intent in terraform commands

### 4. **More Secure**
- Backend credentials never written to source files
- Follows Terraform security recommendations
- Reduces risk of accidentally committing sensitive data

### 5. **Better Error Messages**
- terraform init errors are clearer
- No confusion from placeholder values
- Easier to debug backend configuration issues

## Migration Impact

### Files Modified
- `infrastructure-layered/deploy.sh`
  - `terraform_init()` - Uses `-backend-config`
  - `terraform_validate()` - Removed substitute/restore
  - `terraform_plan()` - Removed substitute/restore
  - `terraform_apply()` - Removed substitute/restore
  - `terraform_destroy()` - Removed substitute/restore
  - `terraform_output()` - Added `-backend-config` to auto-init
  - `get_layer_status()` - Added `-backend-config` to init check
  - `configure_kubectl_alias()` - Fixed output capture

- `infrastructure-layered/base/main.tf`
  - Changed `TF_STATE_BUCKET_PLACEHOLDER` → `""`
  - Changed `TF_STATE_REGION_PLACEHOLDER` → `""`
  - Added comments referencing Terraform partial configuration docs

### Functions Deprecated
- `substitute_bucket_placeholder()` - Can be removed
- `restore_bucket_placeholder()` - Can be removed

These functions are still defined but no longer called. They can be safely deleted in a future cleanup.

## Testing

### Test Scenario 1: Fresh Deployment
```bash
export TF_STATE_BUCKET=my-terraform-state
export TF_STATE_REGION=us-west-2
./deploy.sh deploy
```

**Expected:**
- No modifications to `main.tf` files
- terraform init succeeds with backend configured
- All layers deploy successfully

### Test Scenario 2: Existing Deployment
```bash
./deploy.sh deploy
```

**Expected:**
- Backend reconfiguration works seamlessly
- No "backend changed" warnings
- State is preserved correctly

### Test Scenario 3: Status Check
```bash
./deploy.sh status
```

**Expected:**
- Can read state without modifying files
- Shows correct deployment status
- No placeholder errors

## Rollback

If needed, rollback by:
1. Reverting changes to `deploy.sh`
2. Restoring placeholder values in `main.tf` files
3. Re-enabling `substitute_bucket_placeholder` and `restore_bucket_placeholder` calls

However, the new approach is **strictly better** and rollback should not be necessary.

## References

- [Terraform Backend Configuration](https://developer.hashicorp.com/terraform/language/backend)
- [Partial Backend Configuration](https://developer.hashicorp.com/terraform/language/backend#partial-configuration)
- [Backend Security Best Practices](https://developer.hashicorp.com/terraform/language/backend#credentials-and-sensitive-data)
