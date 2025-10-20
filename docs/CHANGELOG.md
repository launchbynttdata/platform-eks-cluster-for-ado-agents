# Changelog - EKS Cluster for ADO Agents

This document tracks all significant changes, fixes, and improvements made to the infrastructure.

## [Unreleased] - 2025-10-20

### Enhancement: Dynamic Configuration from Terraform

**7. Config Layer Reads Values from Terraform Outputs** ✅

**Enhancement:**
- Config layer now dynamically reads configuration from Terraform outputs
- No more hardcoded values - respects IaC variable customizations
- Production-ready for teams with varying configurations

**Implementation:**
- Added `eso_service_account_name` output to middleware layer
- Created `get_eso_config_from_tf()` helper function with fallback mechanism
- Updated `create_cluster_secret_store()` to use dynamic values
- Updated `deploy_config_layer()` to use dynamic namespace/secret names
- Added visibility logging showing detected configuration

**Dynamic Values:**
- ESO namespace (from `eso_namespace` output)
- ESO ServiceAccount name (from `eso_service_account_name` output)
- ClusterSecretStore name (from `cluster_secret_store_name` output)
- ADO agents namespace (from `ado_agents_namespace` output)
- ADO secret name (from `ado_secret_name` output)

**Fallback Strategy:**
1. Try to read from middleware layer Terraform outputs
2. Fall back to sensible defaults if outputs unavailable
3. Log which values are being used for transparency

**Files Modified:**
- `infrastructure-layered/middleware/outputs.tf` - Added `eso_service_account_name` output
- `infrastructure-layered/deploy.sh` - Added dynamic configuration functions (~60 lines)

**Files Created:**
- `docs/DYNAMIC_CONFIG_FROM_TERRAFORM.md` - Complete enhancement documentation

**Benefits:**
- Teams can customize via terraform.tfvars without code changes
- Respects actual deployed configuration from Terraform state
- Better debugging with configuration visibility logging
- Production-ready for diverse team environments

**Example Output:**
```
[INFO] ESO Configuration:
[INFO]   Namespace: external-secrets-system
[INFO]   ServiceAccount: external-secrets
[INFO]   ClusterSecretStore: aws-secrets-manager
```

---

### Bug Fix: ClusterSecretStore Configuration

**6. ClusterSecretStore InvalidProviderConfig Error** ✅

**Problem:**
- ClusterSecretStore was failing with `InvalidProviderConfig` status
- Error: "ServiceAccount 'external-secrets-sa' not found"
- Config layer deployment appeared successful but ClusterSecretStore wasn't ready

**Root Cause:**
- `create_cluster_secret_store()` function had hardcoded incorrect values
- Wrong ServiceAccount name: `external-secrets-sa` (actual: `external-secrets`)
- Wrong namespace: `external-secrets-operator` (actual: `external-secrets-system`)
- Hardcoded values didn't match actual ESO deployment from middleware layer

**Solution:**
- Updated ClusterSecretStore manifest to use correct ServiceAccount reference:
  - ServiceAccount: `external-secrets`
  - Namespace: `external-secrets-system`
- Values now match the ESO module deployment from middleware layer

**Files Modified:**
- `infrastructure-layered/deploy.sh` - Lines 1008-1028 (ClusterSecretStore manifest)

**Files Created:**
- `docs/FIX_CLUSTERSECRETSTORE_CONFIG.md` - Detailed troubleshooting and fix documentation

**Verification:**
- ✅ ClusterSecretStore Status: Valid
- ✅ Ready: True
- ✅ Capabilities: ReadWrite
- ✅ Successfully connects to AWS Secrets Manager

**Impact:**
- External Secrets Operator can now access AWS Secrets Manager
- ExternalSecret resources can sync secrets properly
- ADO PAT secret can be synchronized to Kubernetes

---

### Enhancement: Config Layer Integration

**5. Post-Deployment Configuration as "Config" Layer** ✅

**Change:**
- Integrated post-deployment configuration steps as a fourth "config" layer in `deploy.sh`
- Unified deployment workflow: `base → middleware → application → config`
- Eliminated need for separate `post-deploy.sh` script

**Implementation:**
- Added `deploy_config_layer()` function with full post-deployment logic
- Created `detect_cluster_name_from_tf()` with multiple fallback mechanisms
- Added kubectl configuration automation via `configure_kubectl_for_cluster()`
- Implemented `create_cluster_secret_store()` for ESO integration
- Added `inject_ado_secret()` for ADO PAT token management

**New Command-Line Flags:**
- `--skip-ado-secret`: Skip Azure DevOps PAT secret injection
- `--pat TOKEN`: Provide ADO PAT token non-interactively
- `--org-url URL`: Provide Azure DevOps organization URL

**Special Handling:**
- Config layer skips Terraform validation and planning (no Terraform files)
- Validates all infrastructure layers are deployed before running
- Provides informational-only destroy guidance
- Auto-skips ADO secret injection when using `--auto-approve`

**Usage Examples:**
```bash
# Deploy only config layer
./deploy.sh --layer config deploy

# Deploy with credentials
./deploy.sh --layer config --pat "token" --org-url "url" deploy

# Deploy full stack (includes config)
./deploy.sh deploy
```

**Benefits:**
- Single script for all deployment phases
- Consistent error handling and logging
- Automatic cluster detection from Terraform or AWS EKS
- Better user experience with integrated workflow
- Flexible - can run config layer independently or skip interactively

**Files Modified:**
- `infrastructure-layered/deploy.sh` - Added ~250 lines for config layer support

**Files Created:**
- `docs/CONFIG_LAYER_INTEGRATION.md` - Complete integration documentation

**Testing:**
- ✅ Syntax validation passed
- ✅ Config layer validation passed
- ✅ Config layer deployment successful
- ✅ ClusterSecretStore created and verified
- ✅ kubectl configured automatically
- ✅ Cluster detection working via AWS EKS fallback

---

### Refactoring: Region Propagation and CRD Fixes

#### Issues Resolved

**4. Environment Variable Preservation** ✅

**Problem:**
- Scripts were overwriting environment variables (AWS_REGION, etc.) with hardcoded defaults
- direnv configurations were being ignored
- `post-deploy.sh` failed with "Invalid endpoint" error due to empty AWS_REGION
- Inconsistent behavior between deploy.sh and post-deploy.sh

**Root Cause:**
- `deploy.sh`: `AWS_REGION="$DEFAULT_REGION"` unconditionally overwrote environment variable
- `post-deploy.sh`: `AWS_REGION=""` unconditionally set to empty string
- AWS CLI config region always took precedence over environment variables

**Solution:**
- Changed variable initialization to `${VAR:-default}` pattern to preserve existing values
- Updated deploy.sh region detection to prioritize: environment → CLI config → default
- Made post-deploy.sh preserve CLUSTER_NAME, AWS_REGION, ADO_PAT_TOKEN, ADO_ORG_URL

**Files Modified:**
- `infrastructure-layered/deploy.sh` - Lines 68, 250-262
- `infrastructure-layered/post-deploy.sh` - Lines 50-53, 189-204

**Files Created:**
- `docs/FIX_ENVIRONMENT_VARIABLE_PRESERVATION.md` - Detailed fix documentation

**Impact:**
- direnv and other environment management tools now work correctly
- Better developer experience with consistent configuration
- Backward compatible - no breaking changes
- Clear logging shows which region source is used

---

**1. AWS Region Propagation Fixed** ✅

**Problem:**
- AWS region was not consistently propagated across infrastructure layers
- `aws eks get-token` commands in Kubernetes/Helm providers were missing `--region` flag
- Hard-coded `AWS_DEFAULT_REGION = "us-east-1"` in agent pool configurations

**Root Causes:**
- Missing `--region` flag in provider exec blocks (middleware and application layers)
- Hard-coded region in IaC agent pool default configuration
- No dynamic region injection mechanism

**Solution:**
- Added `--region data.aws_region.current.name` to all Kubernetes/Helm provider exec blocks
- Created `agent_pools_with_region` local value to dynamically inject AWS region
- Removed hard-coded region from agent pool configurations
- Region now flows from single source of truth: `aws_region` variable in `terraform.tfvars`

**Files Modified:**
- `infrastructure-layered/middleware/main.tf` - Added `--region` to provider exec blocks
- `infrastructure-layered/application/main.tf` - Added `--region` to provider exec blocks
- `infrastructure-layered/application/locals.tf` - Created `agent_pools_with_region` local
- `infrastructure-layered/application/variables.tf` - Removed hard-coded region

**Impact:**
- All AWS operations now use the correct configured region
- Agent pods receive correct `AWS_DEFAULT_REGION` environment variable
- Kubernetes authentication works correctly in any region

---

**2. KEDA CRDs Circular Dependency Resolved** ✅

**Problem:**
- ClusterSecretStore could not be created during middleware Terraform apply
- Terraform validation fails during plan phase if CRDs don't exist
- Manual kubectl intervention was required after deployment

**Root Cause:**
- Terraform's `kubernetes_manifest` resource validates against K8s API during **plan phase**
- External Secrets Operator installs CRDs during Helm chart deployment (apply phase)
- Validation happens before CRDs are available, causing plan to fail
- `time_sleep` resources don't help because validation is during plan, not apply

**Solution Implemented:**
- Documented CRD timing limitation as fundamental Terraform constraint
- Created comprehensive post-deployment automation script: `post-deploy-middleware.sh`
- Script handles ClusterSecretStore creation after ESO CRDs are available
- Script also automates ADO PAT secret injection

**Files Created:**
- `infrastructure-layered/middleware/post-deploy-middleware.sh` - 700+ line automation script
- `docs/MIDDLEWARE_POST_DEPLOYMENT_STEPS.md` - Manual process documentation
- `docs/ADO_PAT_SECRET_INJECTION.md` - Comprehensive PAT injection guide
- `docs/QUICK_REF_ADO_PAT_SECRET.md` - Quick reference commands

**Files Modified:**
- `infrastructure-layered/middleware/main.tf` - Set `create_cluster_secret_store = false`
- `infrastructure-layered/middleware/README.md` - Added post-deployment section

**Impact:**
- Clear separation between Terraform and post-deployment steps
- Automated solution reduces manual intervention
- Better documentation of CRD timing constraints

---

**3. ESO ClusterSecretStore Externalization Cleanup** ✅

**Problem:**
- Confusing conditional logic for `create_cluster_secret_store` in middleware layer
- Variable existed with default `true`, but was always set to `false` in module call
- Created confusion about which component handles ClusterSecretStore creation

**Solution:**
- Removed `create_cluster_secret_store` variable from middleware layer
- Hardcoded `create_cluster_secret_store = false` in ESO module call
- Added clear comments explaining post-deployment script handles this
- Updated `terraform.tfvars` and `terraform.tfvars.sample` to remove obsolete setting
- Kept `cluster_secret_store_name` variable (needed by application layer for reference)

**Files Modified:**
- `infrastructure-layered/middleware/variables.tf` - Removed variable, added explanatory comment
- `infrastructure-layered/middleware/main.tf` - Removed parameter, hardcoded to false
- `infrastructure-layered/middleware/terraform.tfvars` - Removed setting, added comment
- `infrastructure-layered/middleware/terraform.tfvars.sample` - Removed setting, added comment

**Files Created:**
- `docs/CLEANUP_ESO_EXTERNALIZATION.md` - Cleanup documentation

**Impact:**
- Eliminated confusion about ClusterSecretStore creation responsibility
- Made it explicit that post-deployment script handles this
- Cleaner configuration with no misleading variables

---

### Documentation Consolidation

**Created:**
- `docs/OPERATIONS.md` - Consolidated operational procedures and how-to guides
- `docs/CHANGELOG.md` - This file - consolidated change history

**Removed:**
- `docs/ADO_PAT_SECRET_INJECTION.md` - Merged into OPERATIONS.md
- `docs/QUICK_REF_ADO_PAT_SECRET.md` - Merged into OPERATIONS.md
- `docs/MIDDLEWARE_POST_DEPLOYMENT_STEPS.md` - Merged into OPERATIONS.md
- `docs/REFACTORING_SUMMARY.md` - Merged into CHANGELOG.md
- `docs/REFACTOR_REGION_AND_CRD_FIXES.md` - Merged into CHANGELOG.md
- `docs/CLEANUP_ESO_EXTERNALIZATION.md` - Merged into CHANGELOG.md

**Impact:**
- Clearer organization: operational vs. historical documentation
- Easier to find relevant information
- Reduced documentation sprawl

---

## [Previous] - Historical Changes

### EKS Addon Dependency Resolution

**Problem:**
- EKS addons had complex dependency chains
- vpc-cni requires IRSA configuration before installation
- Circular dependencies between addons and node groups

**Solution:**
- Split addon configuration into separate layers
- Implemented proper dependency ordering
- Created dedicated IRSA roles for vpc-cni

**Files:**
- `docs/EKS_ADDON_DEPENDENCY_RESOLUTION.md` - Detailed analysis
- `docs/EKS_ADDON_CORRECT_APPROACH.md` - Solution documentation
- `docs/EKS_ADDON_SPLIT_SOLUTION.md` - Implementation approach

---

### VPC CNI IRSA Configuration

**Problem:**
- VPC CNI addon requires IRSA role for proper functionality
- Missing or incorrect IRSA configuration causes networking issues

**Solution:**
- Created dedicated IAM role for vpc-cni with correct trust policy
- Configured addon to use IRSA role ARN
- Properly configured OIDC provider integration

**Files:**
- `docs/VPC_CNI_IRSA_FIX.md` - Fix documentation

---

### EKS Authentication Solutions

**Problem:**
- Multiple approaches to EKS authentication causing confusion
- Access entry management vs. aws-auth ConfigMap

**Solution:**
- Documented various authentication approaches
- Provided guidance on access entry management
- Clarified when to use each method

**Files:**
- `docs/EKS_AUTH_SOLUTIONS.md` - Authentication approaches

---

### Deployment Script Improvements

**Improvements:**
- Added `--auto-approve` flag for non-interactive deployments
- Improved error handling and validation
- Better S3 bucket name substitution
- Enhanced plan/apply workflow

**Files:**
- `docs/DEPLOY_SCRIPT_IMPROVEMENTS.md` - Script improvements documentation
- `docs/DEPLOY_SCRIPT_PLAN_AND_LAYER_IMPROVEMENTS.md` - Layer workflow improvements

---

### Cluster Autoscaler Implementation

**Added:**
- AWS Cluster Autoscaler for EC2 node groups
- Proper IAM roles and policies
- Configurable autoscaling parameters
- Deployment script for autoscaler

**Configuration:**
- Parameterized autoscaler settings
- Support for multiple node groups
- Fargate + EC2 hybrid scaling

**Files:**
- `docs/CLUSTER_AUTOSCALER_README.md` - Implementation documentation
- `infrastructure/deploy-cluster-autoscaler.sh` - Deployment script

---

### ECR Multiple Repositories

**Added:**
- Support for multiple ECR repositories
- Per-repository IAM policies
- Cross-account pull permissions

**Files:**
- `docs/ECR_Multiple_Repositories_Example.md` - Configuration examples

---

### OCI Image Cross-Build

**Added:**
- Multi-architecture image build support
- Cross-platform Docker builds
- BuildKit configuration for ARM64/AMD64

**Files:**
- `docs/OCI_IMAGE_CROSS_BUILD_README.md` - Build documentation

---

### Infrastructure Layering

**Implemented:**
- Three-layer infrastructure architecture (base/middleware/application)
- Remote state dependencies between layers
- Clear separation of concerns

**Layers:**
1. **Base**: VPC, EKS cluster, node groups, core infrastructure
2. **Middleware**: KEDA, ESO, Buildkitd, namespaces
3. **Application**: ADO agents, ECR repositories, ExternalSecrets

**Benefits:**
- Independent layer lifecycle management
- Reduced blast radius for changes
- Better state management
- Clearer dependency relationships

---

## Version History

### Key Milestones

- **2025-10-20**: Region propagation and CRD fixes, documentation consolidation
- **2024-Q4**: Infrastructure layering implementation
- **2024-Q3**: Cluster autoscaler integration
- **2024-Q2**: Initial EKS cluster setup with ADO agents

---

## Migration Notes

### From Single-Layer to Layered Infrastructure

If migrating from the single-layer infrastructure to layered:

1. **State Migration**: Use `terraform state mv` to reorganize resources
2. **Remote State**: Configure S3 backend for each layer
3. **Dependencies**: Update data sources to reference layer outputs
4. **Sequential Deployment**: Deploy base → middleware → application

### From Manual to Automated Post-Deployment

If previously using manual kubectl commands for ClusterSecretStore:

1. **Validation**: Ensure `post-deploy-middleware.sh` has execute permissions
2. **Existing Resources**: Script detects existing ClusterSecretStore and offers to update
3. **Automation**: Replace manual kubectl commands with script invocation
4. **Verification**: Script includes comprehensive verification steps

---

## Breaking Changes

### 2025-10-20 Refactoring

**Middleware Layer:**
- Removed `create_cluster_secret_store` variable (breaking if you override this)
- ClusterSecretStore now **must** be created via post-deployment script
- Existing deployments: Run `post-deploy-middleware.sh` after upgrading

**Application Layer:**
- `agent_pools` variable now has dynamic region injection
- Removed hard-coded `AWS_DEFAULT_REGION` from defaults
- Existing agent pools will get region from `aws_region` variable

**Required Actions:**
1. Update middleware `terraform.tfvars` to remove `create_cluster_secret_store`
2. Run `terraform plan` to verify no unexpected changes
3. After middleware apply, run `post-deploy-middleware.sh`
4. Verify agent pools receive correct region environment variable

---

## Known Issues

### Terraform Limitations

**CRD Timing:**
- Terraform cannot create kubernetes_manifest resources for CRDs installed in same apply
- Workaround: External post-deployment script (automated)

**Provider Authentication:**
- Kubernetes provider exec auth tokens expire after 15 minutes
- Workaround: Terraform automatically refreshes tokens during operations

### External Secrets Operator

**Refresh Interval:**
- ExternalSecret default refresh interval is 1 hour
- Secret updates in AWS may take up to 1 hour to sync
- Workaround: Delete K8s secret to force immediate resync

### KEDA Scaling

**Cold Start:**
- First agent in pool takes ~60 seconds to provision on Fargate
- Subsequent agents scale faster using cached images
- Workaround: Configure `minReplicaCount` > 0 for critical pools

---

## Future Improvements

### Planned

- [ ] Terraform module for post-deployment automation
- [ ] Helm chart for ADO agents (replace Kubernetes manifests)
- [ ] Multi-region deployment support
- [ ] GitOps integration (ArgoCD/Flux)

### Under Consideration

- [ ] Spot instance support for EC2 node groups
- [ ] Horizontal Pod Autoscaler integration with KEDA
- [ ] Cost optimization analysis tools
- [ ] Automated backup and disaster recovery

---

## Contributing

When making changes:
1. Update relevant documentation (OPERATIONS.md or CHANGELOG.md)
2. Test changes in non-production environment first
3. Update version numbers and migration notes as needed
4. Include rollback procedures for breaking changes
