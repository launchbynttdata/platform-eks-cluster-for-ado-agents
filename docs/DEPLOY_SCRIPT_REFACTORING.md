# Deploy Script Refactoring Plan

## Current State

The `deploy.sh` script is **~2,217 lines** of bash code, which makes it challenging to maintain. While comprehensive and functional, there are opportunities for modularization and code reduction.

## Analysis Summary

### Key Issues Identified

1. **Repetitive layer selection logic** (~120 lines duplicated across 4 command functions)
2. **Duplicated layer iteration patterns** in cmd_deploy, cmd_plan, cmd_validate, cmd_destroy
3. **Similar skipped layer calculation** repeated in multiple functions
4. **Repeated bucket placeholder substitution** in every Terraform operation
5. **Verbose deployment status reporting** with similar patterns across functions
6. **Long argument parsing** could be simplified

### Code Statistics

- **Functions**: ~45 functions total
- **Duplicated Patterns**: ~300-400 lines could be reduced through refactoring
- **Command Functions**: Each 150-250 lines with similar structure

## Recommended Refactoring Strategy

### Phase 1: Extract Common Patterns (Low Risk)

#### 1.1 Create Layer Configuration Helper (~30 lines saved)

```bash
# Centralize layer configuration
get_layer_config() {
    local target_layer="$1"
    
    # Define all layers
    local -a all_layers=("base" "middleware" "application" "config")
    local -a all_dirs=("$BASE_LAYER_DIR" "$MIDDLEWARE_LAYER_DIR" "$APPLICATION_LAYER_DIR" "$CONFIG_LAYER_DIR")
    
    if [[ -z "$target_layer" ]]; then
        # Return all layers
        printf '%s\n' "${all_layers[@]}"
        return 0
    fi
    
    # Validate and return single layer
    case "$target_layer" in
        base|middleware|application|config)
            echo "$target_layer"
            return 0
            ;;
        *)
            log_error "Invalid layer: $target_layer"
            log_error "Valid layers: ${all_layers[*]}"
            return 1
            ;;
    esac
}

get_layer_directory() {
    local layer="$1"
    case "$layer" in
        base) echo "$BASE_LAYER_DIR" ;;
        middleware) echo "$MIDDLEWARE_LAYER_DIR" ;;
        application) echo "$APPLICATION_LAYER_DIR" ;;
        config) echo "$CONFIG_LAYER_DIR" ;;
        *) return 1 ;;
    esac
}
```

**Impact**: Eliminates 120+ lines of duplicated case statements across cmd_deploy, cmd_plan, cmd_validate, cmd_destroy.

#### 1.2 Create Terraform Wrapper (~40 lines saved)

```bash
# Wrapper that handles bucket substitution automatically
terraform_exec() {
    local layer="$1"
    local layer_dir="$2"
    shift 2
    local tf_command="$@"
    
    # Skip config layer
    if [[ "$layer" == "config" ]]; then
        log_debug "Skipping Terraform for config layer"
        return 0
    fi
    
    # Substitute placeholder
    if ! substitute_bucket_placeholder "$layer_dir"; then
        log_error "Failed to substitute bucket placeholder"
        return 1
    fi
    
    # Execute in layer directory
    (
        cd "$layer_dir"
        eval "terraform $tf_command"
    )
    local exit_code=$?
    
    # Restore placeholder
    restore_bucket_placeholder "$layer_dir"
    
    return $exit_code
}
```

**Impact**: Reduces terraform_init, terraform_validate, terraform_plan, terraform_apply, terraform_destroy by ~10 lines each (50 lines total). Ensures bucket placeholder handling is never forgotten.

#### 1.3 Create Layer Status Display Helper (~25 lines saved)

```bash
show_layer_status() {
    local title="$1"
    shift
    local layers=("$@")
    
    if [[ ${#layers[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "$title:"
    for layer in "${layers[@]}"; do
        echo "  ✓ $layer"
    done
    echo
}

show_skipped_layers() {
    local all_layers=("base" "middleware" "application")
    local deployed_layers=("$@")
    local skipped_layers=()
    
    for check_layer in "${all_layers[@]}"; do
        local found=false
        for deployed_layer in "${deployed_layers[@]}"; do
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
}
```

**Impact**: Eliminates duplication in cmd_deploy, cmd_plan, cmd_validate (~75 lines).

### Phase 2: Simplify Command Functions (Medium Risk)

#### 2.1 Unified Layer Iterator

```bash
# Generic layer processor
process_layers() {
    local operation="$1"  # deploy, plan, validate, destroy
    local target_layer="$2"
    
    # Get layer configuration
    local layers=()
    local layer_dirs=()
    
    if [[ -n "$target_layer" ]]; then
        layers=("$target_layer")
        layer_dirs=("$(get_layer_directory "$target_layer")")
    else
        case "$operation" in
            destroy)
                layers=("config" "application" "middleware" "base")  # Reverse
                ;;
            *)
                layers=("base" "middleware" "application" "config")  # Normal
                ;;
        esac
        for layer in "${layers[@]}"; do
            layer_dirs+=("$(get_layer_directory "$layer")")
        done
    fi
    
    # Process each layer
    case "$operation" in
        deploy)
            deploy_layers "${layers[@]}"
            ;;
        plan)
            plan_layers "${layers[@]}"
            ;;
        validate)
            validate_layers "${layers[@]}"
            ;;
        destroy)
            destroy_layers "${layers[@]}"
            ;;
    esac
}
```

**Impact**: Reduces cmd_deploy, cmd_plan, cmd_validate, cmd_destroy to thin wrappers (~200 lines saved).

### Phase 3: Split Into Modules (Optional - Higher Risk)

For future consideration, the script could be split into sourced modules:

```
deploy.sh              # Main orchestrator (~400 lines)
lib/
  ├── common.sh        # Logging, utilities (~150 lines)
  ├── terraform.sh     # Terraform operations (~300 lines)
  ├── kubectl.sh       # Kubernetes operations (~200 lines)
  ├── config.sh        # Config layer functions (~250 lines)
  ├── layers.sh        # Layer management (~300 lines)
  └── commands.sh      # Command implementations (~400 lines)
```

**Impact**: Better organization, but requires careful source path management and testing.

## Implementation Recommendations

### Recommended Approach: **Phase 1 Only**

**Rationale**:
- Lowest risk (extracting duplicate code, not changing logic)
- Immediate maintainability improvement (~200-250 lines saved, 10-12% reduction)
- Each change is independently testable
- Preserves existing command structure that users may depend on
- Can be done incrementally with testing between each step

### Testing Strategy

1. **Before refactoring**: Create comprehensive test suite
   ```bash
   # Test all commands with all layer combinations
   ./deploy.sh status
   ./deploy.sh --layer base validate
   ./deploy.sh --layer middleware plan
   ./deploy.sh --dry-run deploy
   ./deploy.sh --dry-run --layer application deploy
   ```

2. **After each change**: Run full test suite

3. **Integration test**: Deploy to test environment

### Incremental Implementation Order

1. **Step 1**: Add `get_layer_config()` and `get_layer_directory()` helpers
   - Test: Verify helpers work correctly
   
2. **Step 2**: Refactor `cmd_deploy()` to use helpers
   - Test: Full deployment dry-run
   
3. **Step 3**: Refactor `cmd_plan()` to use helpers
   - Test: Plan all layers
   
4. **Step 4**: Refactor `cmd_validate()` to use helpers
   - Test: Validate all layers
   
5. **Step 5**: Refactor `cmd_destroy()` to use helpers
   - Test: Destroy dry-run
   
6. **Step 6**: Add `show_layer_status()` and `show_skipped_layers()`
   - Test: Check all output formatting
   
7. **Step 7**: Add `terraform_exec()` wrapper
   - Test: Run terraform init/plan on each layer

## Alternative: Keep As-Is

**If refactoring is deemed too risky**, consider:

1. **Add comprehensive comments** - Section markers are good, but add function-level docs
2. **Create developer guide** - Document the script's architecture
3. **Add linting** - Use shellcheck to catch issues
4. **Improve test coverage** - Document expected behavior

## Estimated Impact

| Metric | Current | Phase 1 | Phase 2 | Phase 3 |
|--------|---------|---------|---------|---------|
| Total Lines | ~2,217 | ~2,000 | ~1,800 | ~600 (main) |
| Functions | ~45 | ~50 | ~30 | ~40 (distributed) |
| Duplicate Code | High | Low | Minimal | None |
| Maintainability | Medium | High | High | Very High |
| Risk | N/A | Low | Medium | High |

## Recommendation

**Proceed with Phase 1 refactoring only**:
- Reduces script by ~200-250 lines (10-12%)
- Eliminates most code duplication
- Low risk, high value
- Can be completed in 2-4 hours with testing
- Preserves existing script structure
- Sets foundation for future improvements if needed

The script will still be ~2,000 lines, but with significantly less duplication and better maintainability. The core complexity comes from the comprehensive features (4 layers, 5 commands, error handling, recovery guidance, validation, etc.), which is valuable functionality worth keeping.

## Next Steps

1. Review this refactoring plan
2. If approved, create feature branch: `refactor/deploy-script-phase1`
3. Implement Phase 1 changes incrementally
4. Test thoroughly after each change
5. Document changes in CHANGELOG.md
6. Merge when all tests pass
