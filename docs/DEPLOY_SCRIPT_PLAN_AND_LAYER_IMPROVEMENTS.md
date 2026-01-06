# Deploy Script: Plan-File and Layer-Mode Improvements

## Overview

Two additional improvements have been made to the `deploy.sh` orchestration script to enhance the deployment workflow and improve clarity when operating in layer-specific mode.

## Improvement 1: Plan-File Based Deployment

### Problem

Previously, the deployment workflow required users to confirm twice:
1. After viewing the `terraform plan` output
2. Again when running `terraform apply` (interactive approval)

This was redundant and could lead to differences between what was planned and what was applied if the infrastructure changed between the two steps.

### Solution

The script now uses Terraform plan files to create an atomic plan-apply workflow:

1. **Plan Phase**: `terraform plan -out=<file>` saves the execution plan to a file
2. **User Confirmation**: User reviews the plan and confirms once
3. **Apply Phase**: `terraform apply <file>` executes the exact saved plan (no re-confirmation needed)

### Implementation Details

#### Updated `terraform_plan()` Function

```bash
terraform_plan() {
    local layer="$1"
    local layer_dir="$2"
    local plan_file="${3:-}"  # Optional plan file path
    
    # ...
    
    if [[ -n "$plan_file" ]]; then
        plan_cmd="$plan_cmd -out=$plan_file"
    fi
    
    # ...
    
    # Clean up plan file if no changes or on error
    case $plan_exitcode in
        0|1)
            if [[ -n "$plan_file" && -f "$plan_file" ]]; then
                rm -f "$plan_file"
            fi
            ;;
        2)
            log_debug "Plan saved to: $plan_file"
            ;;
    esac
}
```

#### Updated `terraform_apply()` Function

```bash
terraform_apply() {
    local layer="$1"
    local layer_dir="$2"
    local plan_file="${3:-}"  # Optional plan file to apply
    
    if [[ -n "$plan_file" && -f "$plan_file" ]]; then
        # Apply from plan file (no need for -auto-approve or var args)
        apply_cmd="terraform apply $plan_file"
    else
        # Traditional apply with variables and approval flags
        # ...
    fi
    
    # Clean up plan file after successful apply
    if [[ -n "$plan_file" && -f "$plan_file" ]]; then
        rm -f "$plan_file"
    fi
}
```

#### Updated `deploy_layer()` Function

```bash
deploy_layer() {
    # ...
    
    # Create temporary plan file
    local plan_file="$layer_dir/terraform-deploy-$layer.tfplan"
    
    # Plan changes with output file
    terraform_plan "$layer" "$layer_dir" "$plan_file"
    
    # Confirm before applying (single confirmation)
    if ! confirm_action "Apply the planned changes to $layer layer?"; then
        rm -f "$plan_file"
        return 1
    fi
    
    # Apply changes using the plan file
    terraform_apply "$layer" "$layer_dir" "$plan_file"
}
```

### Benefits

1. **Single Confirmation**: Users only confirm once after reviewing the plan
2. **Consistency**: The exact planned changes are applied (no drift between plan and apply)
3. **Faster Workflow**: No need to wait for `terraform apply` to re-calculate the plan
4. **Audit Trail**: Plan files can be saved/reviewed before apply
5. **Safe Cleanup**: Plan files are automatically cleaned up after use or on errors

### Plan File Management

**Naming Convention**: `terraform-deploy-<layer>.tfplan`
- Example: `terraform-deploy-base.tfplan`

**Lifecycle**:
- Created: During `terraform plan` with changes detected
- Used: Applied by `terraform apply` immediately after confirmation
- Cleaned up: Automatically removed after successful apply or on error
- Git Ignored: `*.tfplan` pattern already in `.gitignore`

### Workflow Comparison

**Before:**
```bash
1. terraform plan          # Show changes
2. User: "y"              # Confirm to view plan
3. terraform apply         # Re-calculate (may differ!)
4. User: "yes"            # Confirm again
```

**After:**
```bash
1. terraform plan -out=file   # Save plan to file
2. User: "y"                  # Confirm once
3. terraform apply file       # Execute saved plan (no re-confirm)
```

## Improvement 2: Layer-Mode Status Indicators

### Problem

When running the script with `--layer <specific>`, the output was ambiguous:
- Other layers appeared to have "not deployed" or "failed"
- Users couldn't easily tell if layers were skipped intentionally or failed

### Solution

Added clear status indicators to differentiate between:
- **Deployed**: Layers that were successfully deployed (✓)
- **Failed**: Layers that encountered errors (✗)
- **Skipped**: Layers intentionally not processed due to layer mode (⊘)

### Implementation

#### Deploy Command Output

**All Layers Mode** (`./deploy.sh deploy`):
```
================================
DEPLOYMENT SUCCESSFUL
================================

[SUCCESS] All layers deployed successfully
  ✓ base
  ✓ middleware
  ✓ application
```

**Single Layer Mode** (`./deploy.sh --layer base deploy`):
```
================================
DEPLOYMENT SUCCESSFUL
================================

[SUCCESS] Target layer deployed successfully: base
  ✓ base

Other layers (not deployed - layer mode):
  ⊘ middleware (skipped)
  ⊘ application (skipped)
```

#### Plan Command Output

**Single Layer Mode** (`./deploy.sh --layer middleware plan`):
```
================================
PLAN MODE: LAYER middleware
================================

[INFO] Planned layer: middleware

Other layers (not planned - layer mode):
  ⊘ base (skipped)
  ⊘ application (skipped)
```

#### Validate Command Output

**Single Layer Mode** (`./deploy.sh --layer application validate`):
```
[SUCCESS] Target layer validation passed: application

Other layers (not validated - layer mode):
  ⊘ base (skipped)
  ⊘ middleware (skipped)
```

#### Destroy Command Output

**Single Layer Mode** (`./deploy.sh --layer middleware destroy`):
```
[SUCCESS] Target layer destroyed successfully: middleware

Other layers (not destroyed - layer mode):
  ⊘ base (skipped)
  ⊘ application (skipped)
```

### Code Implementation

```bash
# Example from cmd_deploy
if [[ -n "$TARGET_LAYER" ]]; then
    log_success "Target layer deployed successfully: $TARGET_LAYER"
    for layer in "${successful_layers[@]}"; do
        echo "  ✓ $layer"
    done
    echo
    
    # List other layers that were intentionally skipped
    local all_layers=("base" "middleware" "application")
    local skipped_layers=()
    for check_layer in "${all_layers[@]}"; do
        local found=false
        for deployed_layer in "${successful_layers[@]}"; do
            if [[ "$check_layer" == "$deployed_layer" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            skipped_layers+=("$check_layer")
        fi
    done
    
    if [[ ${#skipped_layers[@]} -gt 0 ]]; then
        echo "Other layers (not deployed - layer mode):"
        for layer in "${skipped_layers[@]}"; do
            echo "  ⊘ $layer (skipped)"
        done
        echo
    fi
fi
```

### Benefits

1. **Clear Intent**: Users immediately understand which layers were intentionally skipped
2. **Reduced Confusion**: No ambiguity between "failed" and "skipped"
3. **Better UX**: Clear visual distinction with status symbols (✓ ✗ ⊘)
4. **Complete Context**: Shows both what was processed and what was skipped
5. **Consistent Across Commands**: Same pattern used for deploy, plan, validate, and destroy

### Status Symbols

| Symbol | Meaning | Usage |
|--------|---------|-------|
| ✓ | Success | Layer successfully processed |
| ✗ | Failed | Layer encountered an error |
| ⊘ | Skipped | Layer intentionally not processed (layer mode) |
| ○ | Pending | Layer not yet attempted (after failure) |

## Usage Examples

### Example 1: Deploy Specific Layer with Plan File

```bash
./deploy.sh --layer base deploy
```

**Output:**
```
[INFO] Planning Terraform changes for base layer...
terraform plan -detailed-exitcode -out=.../base/terraform-deploy-base.tfplan ...
[INFO] Changes planned for base layer

Apply the planned changes to base layer? (y/N): y

[INFO] Applying Terraform changes for base layer...
terraform apply .../base/terraform-deploy-base.tfplan
[SUCCESS] Terraform apply completed for base layer

================================
DEPLOYMENT SUCCESSFUL
================================

[SUCCESS] Target layer deployed successfully: base
  ✓ base

Other layers (not deployed - layer mode):
  ⊘ middleware (skipped)
  ⊘ application (skipped)
```

### Example 2: Plan All Layers vs Single Layer

**All Layers:**
```bash
./deploy.sh plan
# Shows plans for: base, middleware, application
```

**Single Layer:**
```bash
./deploy.sh --layer middleware plan

================================
PLAN MODE: LAYER middleware
================================

[INFO] Planned layer: middleware

Other layers (not planned - layer mode):
  ⊘ base (skipped)
  ⊘ application (skipped)
```

### Example 3: Validation in Layer Mode

```bash
./deploy.sh --layer application validate

[INFO] Validating 1 layer(s)...
[INFO] Validating application layer...
[SUCCESS] application layer validation passed

[SUCCESS] Target layer validation passed: application

Other layers (not validated - layer mode):
  ⊘ base (skipped)
  ⊘ middleware (skipped)
```

## Migration Notes

### For Existing Users

**No Breaking Changes**: These improvements are backward compatible:
- Existing automation will continue to work
- All commands have the same interface
- Only output format has changed (for clarity)

### For CI/CD Pipelines

**Auto-Approve Mode**: Still works the same way:
```bash
./deploy.sh --layer base --auto-approve deploy
# No confirmation prompts, uses plan file automatically
```

### For Interactive Users

**Better Experience**:
- View plan output
- Confirm once
- Apply executes immediately from saved plan
- Clear status on what was skipped in layer mode

## Testing

### Validate Plan-File Workflow

```bash
# Deploy a layer and verify plan file is created then cleaned up
./deploy.sh --layer base deploy

# During execution, check for plan file:
ls -la infrastructure-layered/base/terraform-deploy-*.tfplan
# Should exist during confirmation, then be removed after apply
```

### Verify Layer-Mode Indicators

```bash
# Deploy single layer
./deploy.sh --layer middleware deploy
# Verify output shows skipped layers with ⊘ symbol

# Plan single layer
./deploy.sh --layer base plan
# Verify "PLAN MODE" header and skipped layers listed
```

### Confirm Cleanup

```bash
# After any deployment
find infrastructure-layered -name "*.tfplan"
# Should return no results (all plan files cleaned up)
```

## Related Documentation

- [Deploy Script Improvements](DEPLOY_SCRIPT_IMPROVEMENTS.md) - Previous improvements (kubectl config, fail-fast)
- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Complete deployment procedures
- [Operations Guide](OPERATIONS_GUIDE.md) - Day 2 operations

## Summary

These improvements make the deployment workflow more efficient and clear:

1. **Plan-File Workflow**: Atomic plan-apply with single confirmation
2. **Layer-Mode Indicators**: Clear status showing skipped vs failed layers

Both changes enhance the user experience without breaking existing functionality or requiring changes to existing automation.
