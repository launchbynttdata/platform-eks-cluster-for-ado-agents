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

### [CHANGELOG.md](../CHANGELOG.md)
**History of changes, fixes, and improvements.**

Located at repository root. Contains date-ordered change history, breaking changes, and known issues.

**Use this when:** You need to understand what changed, why, and how to migrate.

---

## Layer Documentation

- [base-layer.md](./base-layer.md) - Base infrastructure layer (EKS cluster, VPC, IAM)
- [middleware-layer.md](./middleware-layer.md) - Middleware layer (KEDA, ESO, buildkitd)
- [application-layer.md](./application-layer.md) - Application layer (ECR, agents, Helm)
- [ado-agent-cluster-helm.md](./ado-agent-cluster-helm.md) - ADO agent Helm chart

---

## Technical Reference

### EKS and Addons
- [EKS_ADDON_CORRECT_APPROACH.md](./EKS_ADDON_CORRECT_APPROACH.md) - Proper addon configuration
- [EKS_ADDON_DEPENDENCY_RESOLUTION.md](./EKS_ADDON_DEPENDENCY_RESOLUTION.md) - Addon dependency management
- [ADDONS_AND_COMPUTE.md](./ADDONS_AND_COMPUTE.md) - Addon independence and compute resources

### Terragrunt
- [TERRAGRUNT_QUICKSTART.md](./TERRAGRUNT_QUICKSTART.md) - Quick start guide
- [TERRAGRUNT_MIGRATION.md](./TERRAGRUNT_MIGRATION.md) - Migration from Terraform
- [TERRAGRUNT_CONFIGURATION_REFERENCE.md](./TERRAGRUNT_CONFIGURATION_REFERENCE.md) - Configuration reference
- [CONFIG_LAYER_IN_TERRAGRUNT.md](./CONFIG_LAYER_IN_TERRAGRUNT.md) - Config layer (ClusterSecretStore, kubectl)

### Infrastructure
- [IAM_ADO_AGENTS.md](./IAM_ADO_AGENTS.md) - IAM roles and policies for ADO agents
- [FARGATE_CONFIGURATION.md](./FARGATE_CONFIGURATION.md) - Fargate profile configuration
- [LAYER_DEPENDENCY_REFERENCE.md](./LAYER_DEPENDENCY_REFERENCE.md) - Layer dependencies and data flow

### Authentication and Secrets
- [EKS_AUTH_SOLUTIONS.md](./EKS_AUTH_SOLUTIONS.md) - EKS authentication approaches
- [ADO_SECRET_MANAGEMENT.md](./ADO_SECRET_MANAGEMENT.md) - ADO secret architecture

### Autoscaling and Containers
- [CLUSTER_AUTOSCALER_README.md](./CLUSTER_AUTOSCALER_README.md) - Cluster autoscaler implementation
- [cluster-autoscaler-middleware.md](./cluster-autoscaler-middleware.md) - Cluster autoscaler in layered infra
- [OCI_IMAGE_CROSS_BUILD_README.md](./OCI_IMAGE_CROSS_BUILD_README.md) - Multi-arch image builds
- [ECR_Multiple_Repositories_Example.md](./ECR_Multiple_Repositories_Example.md) - ECR repository configuration

### Other
- [primitive-collection-state-migration-runbook.md](./primitive-collection-state-migration-runbook.md) - State migration runbook
- [DEPRECATED.md](./DEPRECATED.md) - Legacy infrastructure deprecation notice
- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - Repository directory layout
- [TESTING.md](./TESTING.md) - Testing guide (ShellCheck, BATS)
- [infrastructure-tests.md](./infrastructure-tests.md) - Infrastructure test structure

---

## Quick Navigation

**I want to...**

- **Deploy the infrastructure** → [OPERATIONS.md - Deployment Workflow](./OPERATIONS.md#deployment-workflow)
- **Run post-deployment steps** → [OPERATIONS.md - Post-Deployment Configuration](./OPERATIONS.md#post-deployment-configuration)
- **Inject ADO PAT secret** → [OPERATIONS.md - ADO PAT Secret Management](./OPERATIONS.md#ado-pat-secret-management)
- **Troubleshoot issues** → [OPERATIONS.md - Troubleshooting](./OPERATIONS.md#troubleshooting)
- **Understand recent changes** → [CHANGELOG.md](../CHANGELOG.md)
- **Configure cluster autoscaler** → [CLUSTER_AUTOSCALER_README.md](./CLUSTER_AUTOSCALER_README.md)
- **Understand EKS addons** → [EKS_ADDON_CORRECT_APPROACH.md](./EKS_ADDON_CORRECT_APPROACH.md)

---

## Contributing to Documentation

When adding or updating documentation:

1. **Operational procedures** → Update [OPERATIONS.md](./OPERATIONS.md)
2. **Changes, fixes, improvements** → Update [CHANGELOG.md](../CHANGELOG.md)
3. **Technical deep-dives** → Create standalone document with descriptive name
4. **Update this README** → Add link to your new document in appropriate section

### Documentation Standards

- Use clear, descriptive headings
- Include code examples with context
- Explain the "why" not just the "how"
- Keep operational guides up-to-date with code changes
- Document breaking changes in CHANGELOG.md
- Include troubleshooting steps where applicable
