# Deploy Script Code Analysis

## Quick Stats

- **Total Lines**: 2,217
- **Functions**: 45+
- **Command Functions**: 5 (deploy, plan, validate, destroy, status)
- **Estimated Duplicate/Redundant Code**: 300-400 lines (~15-18%)

## Major Duplication Patterns

### 1. Layer Selection Logic (120 lines duplicated)

Found in: `cmd_deploy()`, `cmd_plan()`, `cmd_validate()`, `cmd_destroy()`

```bash
# This exact pattern appears 4 times:
if [[ -n "$TARGET_LAYER" ]]; then
    case "$TARGET_LAYER" in
        "base")
            layers=("base")
            layer_dirs=("$BASE_LAYER_DIR")
            ;;
        "middleware")
            layers=("middleware")
            layer_dirs=("$MIDDLEWARE_LAYER_DIR")
            ;;
        "application")
            layers=("application")
            layer_dirs=("$APPLICATION_LAYER_DIR")
            ;;
        "config")
            layers=("config")
            layer_dirs=("$CONFIG_LAYER_DIR")
            ;;
        *)
            log_error "Invalid layer: $TARGET_LAYER"
            log_error "Valid layers: base, middleware, application, config"
            exit 1
            ;;
    esac
fi
```

**Lines**: ~30 lines × 4 occurrences = **~120 lines**

### 2. Bucket Placeholder Substitution (50+ lines duplicated)

Found in: `terraform_init()`, `terraform_validate()`, `terraform_plan()`, `terraform_apply()`, `terraform_destroy()`

```bash
# Every terraform function does this:
# 1. Substitute placeholder
if ! substitute_bucket_placeholder "$layer_dir"; then
    log_error "Failed to substitute bucket placeholder"
    return 1
fi

# 2. Do terraform operation
cd "$layer_dir"
terraform <command>
local exit_code=$?

# 3. Restore placeholder
restore_bucket_placeholder "$layer_dir"
return $exit_code
```

**Lines**: ~10 lines × 5 functions = **~50 lines**

### 3. Skipped Layers Calculation (75 lines duplicated)

Found in: `cmd_deploy()`, `cmd_plan()`, `cmd_validate()`

```bash
# This pattern appears 3 times:
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
```

**Lines**: ~25 lines × 3 occurrences = **~75 lines**

### 4. Layer Status Display (60 lines duplicated)

Found in: `cmd_deploy()` (multiple places), `cmd_plan()`, `cmd_validate()`

```bash
# Success message pattern:
echo "Successfully deployed:"
for layer in "${successful_layers[@]}"; do
    echo "  ✓ $layer"
done
echo

# Failed message pattern:
echo "Failed layers:"
for layer in "${failed_layers[@]}"; do
    echo "  ✗ $layer"
done
echo
```

**Lines**: ~10 lines × 6 occurrences = **~60 lines**

### 5. Argument Parsing (Currently not optimal)

The argument parsing uses a while loop but could be more maintainable with getopts or better structure.

**Lines**: Could be improved, but lower priority

## Detailed Breakdown by Section

| Section | Lines | Notes |
|---------|-------|-------|
| Header/Comments | 80 | Necessary documentation |
| Configuration/Constants | 30 | Necessary setup |
| Logging Functions | 25 | Minimal duplication |
| Usage/Help | 100 | Could be trimmed slightly |
| Prerequisites Check | 90 | Good as-is |
| Layer Validation | 50 | Good as-is |
| Bucket Substitution | 80 | **Duplicated in terraform functions** |
| Terraform Operations | 300 | **50+ lines could be extracted** |
| Layer Dependencies | 60 | Good as-is |
| Config Layer Functions | 250 | Good as-is (specialized) |
| Layer Operations | 100 | Good as-is |
| Command Functions | 600 | **270+ lines could be reduced** |
| Status/Display | 200 | **60+ lines could be extracted** |
| Argument Parsing | 100 | Could be improved |
| Main Function | 50 | Good as-is |

## Refactoring Opportunities (Prioritized)

### High Priority (Low Risk, High Value)

1. **Extract Layer Config Helper** → Save ~120 lines
   - Risk: Low
   - Value: High (eliminates major duplication)
   - Effort: 30 minutes

2. **Extract Status Display Helpers** → Save ~60 lines
   - Risk: Low
   - Value: Medium (cleaner output code)
   - Effort: 20 minutes

3. **Extract Skipped Layers Helper** → Save ~75 lines
   - Risk: Low
   - Value: Medium (cleaner logic)
   - Effort: 20 minutes

### Medium Priority (Low-Medium Risk, Medium Value)

4. **Create Terraform Wrapper** → Save ~50 lines
   - Risk: Low-Medium (changes terraform execution flow)
   - Value: Medium (ensures consistency)
   - Effort: 45 minutes

5. **Simplify Argument Parsing** → Save ~20 lines
   - Risk: Medium (affects script interface)
   - Value: Low-Medium (cleaner parsing)
   - Effort: 30 minutes

### Low Priority (Higher Risk, Lower Value)

6. **Consolidate Command Functions** → Save ~150 lines
   - Risk: Medium-High (major restructuring)
   - Value: Medium (cleaner but risky)
   - Effort: 2-3 hours

7. **Split into Modules** → Reorganize entire script
   - Risk: High (changes deployment model)
   - Value: High (better organization)
   - Effort: 4-6 hours + extensive testing

## Recommended Changes Summary

**Phase 1: Quick Wins (Total: ~200-250 lines saved, 2-3 hours effort)**

1. Add `get_layer_config()` function
2. Add `get_layer_directory()` function  
3. Update all command functions to use helpers
4. Add `show_layer_status()` function
5. Add `show_skipped_layers()` function
6. Update command functions to use display helpers
7. Add `terraform_exec()` wrapper (optional)

**Result**: Script reduces from ~2,217 lines to ~2,000 lines with better maintainability

## Risk Assessment

| Change | Risk Level | Testing Required |
|--------|------------|------------------|
| Layer config helpers | Low | Basic unit tests |
| Display helpers | Low | Visual inspection |
| Terraform wrapper | Medium | Full terraform workflow |
| Command restructuring | High | Full integration tests |
| Module splitting | Very High | Complete regression testing |

## Recommendation

**Implement Phase 1 only**: Focus on extracting duplicate code into helper functions without changing the overall structure or logic flow. This gives the best return on investment with minimal risk.

The script will remain large (~2,000 lines) because it genuinely has a lot of functionality:
- 4 infrastructure layers (base, middleware, application, config)
- 5 commands (deploy, plan, validate, destroy, status)
- Comprehensive error handling and recovery
- Interactive mode with confirmations
- Dry-run mode
- Layer-specific validation
- Post-deployment configuration
- Extensive logging and status reporting

This is valuable complexity that should be preserved, just organized better.
