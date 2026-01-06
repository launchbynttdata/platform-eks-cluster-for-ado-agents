# Documentation Structure

This directory contains documentation for the EKS cluster infrastructure for Azure DevOps agents.

## Primary Documentation

### [OPERATIONS.md](./OPERATIONS.md)
**Your go-to guide for using this infrastructure.**

Contains operational procedures and how-to guides:
- Deployment workflow (layered infrastructure)
- Post-deployment configuration steps
- ADO PAT secret management
- Cluster autoscaler operations
- Troubleshooting common issues

**Use this when:** You need to deploy, configure, or troubleshoot the infrastructure.

---

### [CHANGELOG.md](./CHANGELOG.md)
**History of changes, fixes, and improvements.**

Contains detailed change history:
- Recent refactoring (region propagation, CRD fixes)
- Breaking changes and migration notes
- Historical improvements
- Known issues and limitations
- Future roadmap

**Use this when:** You need to understand what changed, why, and how to migrate.

---

## Technical Deep-Dives

These documents provide detailed technical information about specific components or solutions:

### EKS Addons
- [EKS_ADDON_CORRECT_APPROACH.md](./EKS_ADDON_CORRECT_APPROACH.md) - Proper addon configuration
- [EKS_ADDON_DEPENDENCY_RESOLUTION.md](./EKS_ADDON_DEPENDENCY_RESOLUTION.md) - Addon dependency management
- [EKS_ADDON_SPLIT_SOLUTION.md](./EKS_ADDON_SPLIT_SOLUTION.md) - Layer-based addon approach
- [VPC_CNI_IRSA_FIX.md](./VPC_CNI_IRSA_FIX.md) - VPC CNI IRSA configuration

### Authentication
- [EKS_AUTH_SOLUTIONS.md](./EKS_AUTH_SOLUTIONS.md) - EKS authentication approaches

### Deployment
- [DEPLOY_SCRIPT_IMPROVEMENTS.md](./DEPLOY_SCRIPT_IMPROVEMENTS.md) - Deployment script enhancements
- [DEPLOY_SCRIPT_PLAN_AND_LAYER_IMPROVEMENTS.md](./DEPLOY_SCRIPT_PLAN_AND_LAYER_IMPROVEMENTS.md) - Layer workflow improvements

### Autoscaling
- [CLUSTER_AUTOSCALER_README.md](./CLUSTER_AUTOSCALER_README.md) - Cluster autoscaler implementation

### Container Management
- [OCI_IMAGE_CROSS_BUILD_README.md](./OCI_IMAGE_CROSS_BUILD_README.md) - Multi-arch image builds
- [ECR_Multiple_Repositories_Example.md](./ECR_Multiple_Repositories_Example.md) - ECR repository configuration

---

## Documentation Consolidation (2025-10-20)

The documentation was reorganized to separate operational guides from change history:

**Consolidated into OPERATIONS.md:**
- ADO_PAT_SECRET_INJECTION.md → PAT secret management section
- QUICK_REF_ADO_PAT_SECRET.md → Quick reference commands
- MIDDLEWARE_POST_DEPLOYMENT_STEPS.md → Post-deployment configuration section

**Consolidated into CHANGELOG.md:**
- REFACTORING_SUMMARY.md → Recent changes section
- REFACTOR_REGION_AND_CRD_FIXES.md → Detailed fix documentation
- CLEANUP_ESO_EXTERNALIZATION.md → ESO cleanup details

**Benefits:**
- ✅ Clear separation: "how to use" vs "what changed"
- ✅ Easier to find relevant information
- ✅ Reduced documentation sprawl
- ✅ Single source of truth for operational procedures

---

## Quick Navigation

**I want to...**

- **Deploy the infrastructure** → [OPERATIONS.md - Deployment Workflow](./OPERATIONS.md#deployment-workflow)
- **Run post-deployment steps** → [OPERATIONS.md - Post-Deployment Configuration](./OPERATIONS.md#post-deployment-configuration)
- **Inject ADO PAT secret** → [OPERATIONS.md - ADO PAT Secret Management](./OPERATIONS.md#ado-pat-secret-management)
- **Troubleshoot issues** → [OPERATIONS.md - Troubleshooting](./OPERATIONS.md#troubleshooting)
- **Understand recent changes** → [CHANGELOG.md - Unreleased](./CHANGELOG.md#unreleased---2025-10-20)
- **Learn about breaking changes** → [CHANGELOG.md - Breaking Changes](./CHANGELOG.md#breaking-changes)
- **Configure cluster autoscaler** → [CLUSTER_AUTOSCALER_README.md](./CLUSTER_AUTOSCALER_README.md)
- **Understand EKS addons** → [EKS_ADDON_CORRECT_APPROACH.md](./EKS_ADDON_CORRECT_APPROACH.md)

---

## Contributing to Documentation

When adding or updating documentation:

1. **Operational procedures** → Update [OPERATIONS.md](./OPERATIONS.md)
2. **Changes, fixes, improvements** → Update [CHANGELOG.md](./CHANGELOG.md)
3. **Technical deep-dives** → Create standalone document with descriptive name
4. **Update this README** → Add link to your new document in appropriate section

### Documentation Standards

- Use clear, descriptive headings
- Include code examples with context
- Explain the "why" not just the "how"
- Keep operational guides up-to-date with code changes
- Document breaking changes in CHANGELOG.md
- Include troubleshooting steps where applicable
