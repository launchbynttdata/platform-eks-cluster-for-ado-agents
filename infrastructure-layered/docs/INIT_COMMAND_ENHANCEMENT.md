# Init Command Enhancement

## Overview

This enhancement adds automatic module initialization to the `deploy.sh` script to ensure external Terraform/Terragrunt modules are properly downloaded before running `plan` or `apply` operations.

## Problem Statement

When using external modules from Terraform registries, the modules must be downloaded via `terraform init` or `terragrunt init` before they can be used. Previously, the script would fail with "module not installed" errors if:

1. The `.terragrunt-cache` or `.terraform` directories didn't exist
2. External modules were added or updated but not re-initialized
3. Users ran `plan` or `apply` without manually running `init` first

## Solution

### New `init_layer` Function

Added a smart initialization function that:

1. **Checks if initialization is needed** by examining:
   - Existence of `.terragrunt-cache` directory
   - Existence of `.terraform` directory
   - Presence of module files in `.terraform/modules`
   - Existence of `modules.json` manifest in terragrunt cache

2. **Runs `terragrunt init -upgrade`** when needed to:
   - Download external modules from Terraform Registry
   - Upgrade modules to latest compatible versions
   - Initialize backend configuration

3. **Skips unnecessary initialization** to save time when modules are already present

### Automatic Initialization

The script now **automatically initializes layers** before:

- Running `plan` operations
- Running `apply` operations

This ensures modules are always present when needed, preventing "module not installed" errors.

### New `init` Command

Added a standalone `init` command for explicit initialization:

```bash
# Initialize all layers
./deploy.sh init

# Initialize specific layer
./deploy.sh init --layer base

# Force re-initialization with verbose output
./deploy.sh init --layer middleware --verbose
```

## Changes Made

### 1. New Function: `init_layer()`

Location: After `get_layer_dir()` function

```bash
init_layer() {
    local layer="$1"
    local layer_dir="$2"
    local force="${3:-false}"
    
    # Smart detection of initialization needs
    # Runs terragrunt init -upgrade when needed
    # Skips when already initialized
}
```

### 2. Modified Function: `plan_layer()`

Now calls `init_layer()` before planning:

```bash
plan_layer() {
    # ... existing code ...
    
    # Ensure layer is initialized before planning
    if ! init_layer "${layer}" "${layer_dir}"; then
        log_error "Failed to initialize ${layer} layer before planning"
        return 1
    fi
    
    # ... rest of function ...
}
```

### 3. Modified Function: `apply_layer()`

Now calls `init_layer()` before applying:

```bash
apply_layer() {
    # ... existing code ...
    
    # Ensure layer is initialized before applying
    if ! init_layer "${layer}" "${layer_dir}"; then
        log_error "Failed to initialize ${layer} layer before applying"
        return 1
    fi
    
    # ... rest of function ...
}
```

### 4. New Function: `init_all_layers()`

Initializes all layers in sequence:

```bash
init_all_layers() {
    log "Initializing all layers..."
    
    local layers=("base" "middleware" "application")
    
    for layer in "${layers[@]}"; do
        # Initialize each layer with force flag
    done
}
```

### 5. Updated Command Parsing

Added `init` to recognized commands:

```bash
case "$1" in
    deploy|init|plan|validate|destroy|status)
        command="$1"
        shift
        ;;
```

### 6. Updated Help Documentation

Added init command examples and documentation.

## Benefits

1. **Prevents Module Errors**: Automatically downloads external modules before use
2. **Saves Time**: Only initializes when needed, skips if modules already present
3. **Better DX**: Users don't need to remember to run init separately
4. **CI/CD Friendly**: Scripts can run reliably without manual initialization steps
5. **Explicit Control**: Users can still force initialization with the `init` command
6. **Verbose Logging**: Clear indication when initialization is happening and why

## Usage Examples

### Automatic (Recommended)

Just run plan or deploy - initialization happens automatically:

```bash
# Plan automatically initializes if needed
./deploy.sh plan --layer base

# Deploy automatically initializes if needed
./deploy.sh deploy --layer middleware
```

### Explicit Initialization

For when you want to pre-download modules or force re-initialization:

```bash
# Initialize all layers upfront
./deploy.sh init

# Initialize only base layer
./deploy.sh init --layer base

# Re-initialize with verbose output
./deploy.sh init --verbose
```

### After Adding New External Modules

When you add new external modules to your Terragrunt configuration:

```bash
# Force re-initialization to download new modules
./deploy.sh init --layer application

# Or let it happen automatically
./deploy.sh plan --layer application
```

## Testing

Verified that:

- ✅ Script syntax is valid (bash -n)
- ✅ Help command shows init documentation
- ✅ Init command is recognized in command parsing
- ✅ Plan and apply functions call init_layer before execution
- ✅ Dry-run mode works with init operations

## Migration Notes

**No breaking changes** - existing workflows continue to work:

- `./deploy.sh deploy` still works as before, now with automatic init
- `./deploy.sh plan` still works as before, now with automatic init
- All existing flags and options remain the same

**New capability** - users can now:

- Run `./deploy.sh init` to pre-initialize layers
- Rely on automatic initialization during plan/apply operations
- Work with external modules without manual init steps

## Future Enhancements

Potential improvements for future iterations:

1. **Module Version Checking**: Detect when module versions change and auto-reinitialize
2. **Parallel Initialization**: Initialize independent layers in parallel
3. **Cache Validation**: More sophisticated cache validation beyond file existence
4. **Init Performance Metrics**: Track and report initialization time per layer
