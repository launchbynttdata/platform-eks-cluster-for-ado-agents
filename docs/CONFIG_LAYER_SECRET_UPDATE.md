# Config Layer Secret Management - Updated Behavior

## Summary of Changes

Changed the config layer's ADO secret injection behavior to be **opt-in** instead of opt-out, and switched from CLI arguments to environment variables for credential handling.

## Changes Made

### 1. Reversed Secret Update Logic

**Before** (v1):
- Default: **Update secret** during config layer deployment
- Flag: `--skip-ado-secret` to skip the update
- Credentials via CLI args: `--pat TOKEN --org-url URL`

**After** (v2):
- Default: **Do NOT update secret** during config layer deployment
- Flag: `--update-ado-secret` to explicitly update credentials
- Credentials via environment variables: `ADO_PAT` and `ADO_ORG_URL`

### 2. Environment Variables Instead of CLI Args

**Removed**:
- `--pat TOKEN` - No longer accepted via CLI
- `--org-url URL` - No longer accepted via CLI
- `--skip-ado-secret` - Replaced with opposite logic

**Added**:
- `--update-ado-secret` - Explicitly opt-in to update credentials
- `ADO_PAT` - Environment variable for PAT token
- `ADO_ORG_URL` - Environment variable for organization URL

### 3. Prompting Behavior

If `--update-ado-secret` is specified but environment variables are not set:
1. Script checks for `ADO_PAT` environment variable
2. If not found, prompts interactively: "Enter Azure DevOps PAT Token:"
3. Script checks for `ADO_ORG_URL` environment variable
4. If not found, prompts interactively: "Enter Azure DevOps Organization URL:"

## Rationale

### Why Opt-In (--update-ado-secret)?

1. **Security**: Secrets shouldn't be updated on every deployment
2. **Separation of Concerns**: Infrastructure deployment ≠ credential management
3. **Safety**: Reduces risk of accidentally overwriting working credentials
4. **Explicit Intent**: Forces user to consciously decide to update credentials

### Why Environment Variables?

1. **Security**: Credentials don't appear in shell history
2. **Automation**: Easier to set in CI/CD pipelines
3. **Flexibility**: Can be set via direnv, .env files, or export commands
4. **Best Practice**: Industry standard for passing secrets to scripts

## Usage Examples

### Initial Deployment (Without Secret Update)

```bash
# Deploy config layer - creates ClusterSecretStore, skips secret update
./deploy.sh --layer config deploy
```

**Output**:
```
[INFO] Skipping ADO secret update (use --update-ado-secret to update credentials)
[INFO] The Terraform-managed secret container exists and is configured
```

### Update ADO PAT Credentials

**Option 1: With Environment Variables**
```bash
# Set credentials via environment variables
export ADO_PAT="your-pat-token-here"
export ADO_ORG_URL="https://dev.azure.com/your-org"

# Deploy config layer with secret update
./deploy.sh --layer config --update-ado-secret deploy
```

**Option 2: Interactive Prompting**
```bash
# Script will prompt for credentials
./deploy.sh --layer config --update-ado-secret deploy

# Prompts:
# Enter Azure DevOps PAT Token: ****
# Enter Azure DevOps Organization URL: https://dev.azure.com/your-org
```

**Option 3: Using direnv**
```bash
# Create .envrc file
cat > .envrc <<EOF
export ADO_PAT="your-pat-token"
export ADO_ORG_URL="https://dev.azure.com/your-org"
EOF

# Allow direnv
direnv allow

# Deploy (credentials loaded automatically)
./deploy.sh --layer config --update-ado-secret deploy
```

### Full Stack Deployment

```bash
# Deploy all layers (config layer skips secret update by default)
./deploy.sh deploy

# Later, update credentials separately
export ADO_PAT="new-token"
export ADO_ORG_URL="https://dev.azure.com/your-org"
./deploy.sh --layer config --update-ado-secret deploy
```

## Migration Guide

### If you have existing scripts using old behavior:

**Old command**:
```bash
./deploy.sh --layer config --pat "token" --org-url "url" deploy
```

**New command**:
```bash
export ADO_PAT="token"
export ADO_ORG_URL="url"
./deploy.sh --layer config --update-ado-secret deploy
```

**Or skip secret update entirely**:
```bash
# Just configure ESO, don't touch the secret
./deploy.sh --layer config deploy
```

### If you were using --skip-ado-secret:

**Old command**:
```bash
./deploy.sh --layer config --skip-ado-secret deploy
```

**New command** (same behavior is now default):
```bash
./deploy.sh --layer config deploy
```

## Architecture Flow

```
┌─────────────────────────────────────────────────────────┐
│                  CONFIG LAYER BEHAVIOR                  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  WITHOUT --update-ado-secret (DEFAULT)                 │
│  ┌────────────────────────────────────┐               │
│  │ 1. Configure kubectl                │               │
│  │ 2. Create ClusterSecretStore        │               │
│  │ 3. Skip secret update ✓             │               │
│  └────────────────────────────────────┘               │
│                                                         │
│  WITH --update-ado-secret (OPT-IN)                     │
│  ┌────────────────────────────────────┐               │
│  │ 1. Configure kubectl                │               │
│  │ 2. Create ClusterSecretStore        │               │
│  │ 3. Check ADO_PAT env var            │               │
│  │ 4. Check ADO_ORG_URL env var        │               │
│  │ 5. Prompt if not set                │               │
│  │ 6. Update secret in AWS SM          │               │
│  │ 7. ESO syncs to Kubernetes          │               │
│  └────────────────────────────────────┘               │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Security Benefits

1. **Reduced Attack Surface**: Secrets not passed via CLI (no shell history)
2. **Explicit Actions**: Must consciously opt-in to update credentials
3. **Separation**: Infrastructure deployment separate from credential management
4. **Audit Trail**: Clear when secrets were intentionally updated vs. infrastructure deployed

## Testing

### Test Default Behavior (No Secret Update)

```bash
# Should skip secret update
./deploy.sh --dry-run --layer config deploy 2>&1 | grep "ADO"

# Expected output:
# [INFO] Skipping ADO secret update (use --update-ado-secret to update credentials)
```

### Test Secret Update with Environment Variables

```bash
# Set test credentials
export ADO_PAT="test-token"
export ADO_ORG_URL="https://dev.azure.com/test-org"

# Should attempt to update secret
./deploy.sh --dry-run --layer config --update-ado-secret deploy 2>&1 | grep "ADO"

# Expected output:
# [INFO] Using ADO_PAT from environment variable
# [INFO] Using ADO_ORG_URL from environment variable
```

### Test Interactive Prompting

```bash
# Unset environment variables
unset ADO_PAT ADO_ORG_URL

# Should prompt for credentials (can't test in automated mode)
./deploy.sh --layer config --update-ado-secret deploy

# Expected prompts:
# ADO_PAT environment variable not set
# Enter Azure DevOps PAT Token: 
# ADO_ORG_URL environment variable not set
# Enter Azure DevOps Organization URL:
```

## Documentation Updates

Updated files:
- `deploy.sh` - Implementation
- Help text - Removed `--pat` and `--org-url`, added `--update-ado-secret`
- Examples - Show environment variable usage

## Backward Compatibility

**Breaking Changes**:
- ❌ `--skip-ado-secret` flag removed (default behavior changed)
- ❌ `--pat` CLI argument removed (use `ADO_PAT` env var)
- ❌ `--org-url` CLI argument removed (use `ADO_ORG_URL` env var)

**Migration Required**: Yes, update any automation scripts to use new flags/env vars

## Related Documentation

- `docs/ADO_SECRET_MANAGEMENT.md` - Architecture overview
- `docs/DEPLOY_SCRIPT_REFACTORING_SUMMARY.md` - Recent refactoring changes

---

**Date**: October 20, 2025  
**Version**: 2.0  
**Status**: ✅ Implemented and Tested  
**Breaking Change**: Yes (see Backward Compatibility section)
