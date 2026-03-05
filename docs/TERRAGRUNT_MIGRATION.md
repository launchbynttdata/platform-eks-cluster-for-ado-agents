# Terragrunt Migration Guide

## Overview

This guide covers the migration from layer-specific `terraform.tfvars` files to a unified Terragrunt-based configuration approach. The new structure provides:

- **Single source of truth** - All configuration in `env.hcl`
- **Automatic dependency management** - Terragrunt handles layer dependencies
- **Multi-environment support** - Easy switching between dev/staging/prod
- **DRY principles** - No duplication of common configuration
- **Improved workflow** - Simpler deployment and management

## Architecture Changes

### Before (Terraform with tfvars)

```
infrastructure-layered/
├── deploy.sh
├── base/
│   ├── terraform.tfvars          # Base configuration
│   ├── main.tf
│   └── variables.tf
├── middleware/
│   ├── terraform.tfvars          # Middleware configuration
│   ├── main.tf
│   ├── variables.tf
│   └── remote_state.tf          # Manual remote state
└── application/
    ├── terraform.tfvars          # Application configuration
    ├── main.tf
    ├── variables.tf
    └── remote_state.tf          # Manual remote state
```

### After (Terragrunt)

```
infrastructure-layered/
├── terragrunt.hcl               # Root config (backend, providers)
├── env.hcl                      # Single configuration file ⭐
├── env.sample.hcl               # Template for new environments
├── common.hcl                   # Shared helpers
├── deploy-tg.sh                 # Terragrunt deployment script
├── base/
│   ├── terragrunt.hcl          # Base layer config (reads env.hcl)
│   ├── main.tf
│   └── variables.tf
├── middleware/
│   ├── terragrunt.hcl          # Middleware config + dependencies
│   ├── main.tf
│   └── variables.tf
└── application/
    ├── terragrunt.hcl          # Application config + dependencies
    ├── main.tf
    └── variables.tf
```

## Migration Steps

### Step 1: Install Terragrunt

```bash
# macOS
brew install terragrunt

# Linux
curl -LO https://github.com/gruntwork-io/terragrunt/releases/download/v0.55.0/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

# Verify installation
terragrunt --version
```

### Step 2: Create Environment Configuration

The new Terragrunt setup uses `env.hcl` as the single source of truth for all configuration.

```bash
# Copy the sample file
cp env.sample.hcl env.hcl

# Edit with your environment-specific values
vim env.hcl
```

**Migrating your existing tfvars:**

Open your existing `base/terraform.tfvars`, `middleware/terraform.tfvars`, and `application/terraform.tfvars` files and transfer the values to corresponding sections in `env.hcl`.

```hcl
# env.hcl structure
locals {
  environment = "development"
  aws_region  = "us-west-2"
  
  # Base layer values (from base/terraform.tfvars)
  cluster_name = "..."
  vpc_id = "..."
  # ... etc
  
  # Middleware layer values (from middleware/terraform.tfvars)
  install_keda = true
  keda_version = "2.17.2"
  # ... etc
  
  # Application layer values (from application/terraform.tfvars)
  ado_org = "..."
  ado_url = "..."
  # ... etc
}
```

### Step 3: Environment Variables

The same environment variables are still required:

```bash
# Required
export TF_STATE_BUCKET='your-terraform-state-bucket'
export TF_STATE_REGION='us-west-2'  # Optional, defaults to AWS_REGION

# Optional
export AWS_REGION='us-west-2'
export AWS_PROFILE='your-aws-profile'
export TF_VAR_ado_pat_value='your-ado-pat'
```

Or use direnv with `.envrc`:

```bash
# .envrc
export TF_STATE_BUCKET='your-terraform-state-bucket'
export TF_STATE_REGION='us-west-2'
export AWS_REGION='us-west-2'
export TF_VAR_ado_pat_value='your-ado-pat'
```

### Step 4: Clean Up Old State (Optional)

If you're migrating existing infrastructure, you have two options:

#### Option A: Keep Existing State (Recommended)

Terragrunt will work with your existing Terraform state files. No migration needed!

```bash
# The state files remain in the same S3 locations:
# - base/terraform.tfstate
# - middleware/terraform.tfstate
# - application/terraform.tfstate
```

#### Option B: Fresh Deployment

If you want to start fresh:

```bash
# Destroy old infrastructure
./deploy.sh destroy --auto-approve

# Deploy with Terragrunt
./deploy-tg.sh deploy
```

### Step 5: Deploy with Terragrunt

```bash
# Validate all layers
./deploy-tg.sh validate

# Plan all layers
./deploy-tg.sh plan

# Deploy all layers
./deploy-tg.sh deploy

# Or deploy specific layer
./deploy-tg.sh deploy --layer base
```

## Key Differences

### Configuration Management

| Aspect | Old (Terraform) | New (Terragrunt) |
|--------|----------------|------------------|
| **Configuration files** | 3 separate tfvars | 1 env.hcl |
| **Dependencies** | Manual remote_state | Automatic via dependencies |
| **Provider config** | Manual in each layer | Generated automatically |
| **Backend config** | Manual in each layer | Generated automatically |
| **Multi-environment** | Copy/modify tfvars | Switch env.hcl symlink |

### Deployment Commands

| Task | Old Command | New Command |
|------|------------|-------------|
| Deploy all | `./deploy.sh deploy` | `./deploy-tg.sh deploy` |
| Deploy one layer | `./deploy.sh deploy --layer base` | `./deploy-tg.sh deploy --layer base` |
| Plan all | `./deploy.sh plan` | `./deploy-tg.sh plan` |
| Destroy all | `./deploy.sh destroy` | `./deploy-tg.sh destroy` |
| Validate | `./deploy.sh validate` | `./deploy-tg.sh validate` |
| Status | `./deploy.sh status` | `./deploy-tg.sh status` |

### Direct Terragrunt Commands

You can also use Terragrunt directly:

```bash
# Deploy all layers at once
cd infrastructure-layered
terragrunt run-all apply

# Deploy specific layer
cd infrastructure-layered/base
terragrunt apply

# Plan with dependencies
cd infrastructure-layered/middleware
terragrunt plan

# Show outputs
cd infrastructure-layered/base
terragrunt output

# Destroy in reverse order
cd infrastructure-layered
terragrunt run-all destroy
```

## Multi-Environment Workflow

One of the biggest advantages of Terragrunt is easy multi-environment management:

### Option 1: Environment-Specific Files

```bash
# Create environment-specific configs
cp env.sample.hcl env.dev.hcl
cp env.sample.hcl env.staging.hcl
cp env.sample.hcl env.prod.hcl

# Edit each for their environment
vim env.dev.hcl
vim env.staging.hcl
vim env.prod.hcl

# Switch environments with symlink
ln -sf env.dev.hcl env.hcl      # Use development
ln -sf env.staging.hcl env.hcl  # Use staging
ln -sf env.prod.hcl env.hcl     # Use production
```

### Option 2: Directory Structure

For more complex setups:

```
infrastructure-layered/
├── terragrunt.hcl
├── common.hcl
├── environments/
│   ├── dev/
│   │   ├── env.hcl
│   │   ├── base/terragrunt.hcl
│   │   ├── middleware/terragrunt.hcl
│   │   └── application/terragrunt.hcl
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
└── modules/
    ├── base/
    ├── middleware/
    └── application/
```

## Troubleshooting

### Error: terragrunt.hcl not found

```bash
# Make sure you're in the right directory
cd infrastructure-layered

# Or specify the working dir
terragrunt --terragrunt-working-dir ./base apply
```

### Error: env.hcl not found

```bash
# Create env.hcl from sample
cp env.sample.hcl env.hcl
vim env.hcl
```

### Error: TF_STATE_BUCKET not set

```bash
export TF_STATE_BUCKET='your-state-bucket-name'
```

### Error: Dependency outputs not available

```bash
# Deploy dependencies first
cd base
terragrunt apply

cd ../middleware
terragrunt apply
```

### Clearing Terragrunt Cache

```bash
# Remove all cache directories
find . -type d -name ".terragrunt-cache" -exec rm -rf {} +

# Or per layer
rm -rf base/.terragrunt-cache
rm -rf middleware/.terragrunt-cache
rm -rf application/.terragrunt-cache
```

### State Lock Issues

```bash
# Force unlock (use carefully!)
cd base
terragrunt force-unlock <lock-id>
```

## Benefits of Terragrunt Approach

### 1. **Single Source of Truth**
All configuration in one place (`env.hcl`) makes it easy to understand and modify the entire stack.

### 2. **Automatic Dependency Management**
Terragrunt automatically passes outputs from base → middleware → application.

### 3. **DRY Configuration**
No duplication of:
- AWS region
- Common tags
- Backend configuration
- Provider configuration

### 4. **Multi-Environment Support**
Easy to maintain dev/staging/prod with environment-specific `env.hcl` files.

### 5. **Better Error Messages**
Terragrunt provides clearer error messages when dependencies are missing.

### 6. **Parallel Execution**
`terragrunt run-all` can deploy independent resources in parallel.

### 7. **Consistent Workflow**
Same commands work across all environments and layers.

## Best Practices

### 1. **Keep Sensitive Data in Environment Variables**

```bash
# Never commit to version control
export TF_VAR_ado_pat_value='secret-pat'
export TF_VAR_db_password='secret-password'
```

### 2. **Use Descriptive Environment Names**

```hcl
# env.hcl
locals {
  environment = "dev-us-west-2"  # Include region
  # or
  environment = "prod-customer-a"  # Include customer/tenant
}
```

### 3. **Version Control Your env.hcl**

```bash
# Add to .gitignore (already done)
env.hcl

# Commit the sample
git add env.sample.hcl
```

### 4. **Test with Plan First**

```bash
# Always plan before apply
./deploy-tg.sh plan
./deploy-tg.sh deploy --auto-approve
```

### 5. **Use Workspaces for Temporary Testing**

```bash
# Create test workspace
cd base
terraform workspace new test
terragrunt apply

# Clean up
terraform workspace select default
terraform workspace delete test
```

## Rollback Strategy

If you need to rollback to the old Terraform approach:

1. **Keep your old tfvars files** (git stash or commit them)
2. **State files remain unchanged** - they work with both approaches
3. **Use the old deploy.sh script**

```bash
# Rollback command
git stash  # Save Terragrunt files
git checkout HEAD -- base/terraform.tfvars middleware/terraform.tfvars application/terraform.tfvars
./deploy.sh deploy
```

## Questions?

For additional help:
- Terragrunt documentation: https://terragrunt.gruntwork.io/docs/
- Terragrunt examples: https://github.com/gruntwork-io/terragrunt-infrastructure-live-example
- Project README: [README.md](./README.md)
