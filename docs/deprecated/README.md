# Deprecated Documentation

These documents are archived for historical reference. They describe superseded approaches (monolithic `infrastructure/` stack, per-layer `terraform.tfvars`, one-time migrations) and are **not maintained**.

For current guidance, start at the [documentation hub](../README.md).

| Document | Superseded by |
|----------|---------------|
| [legacy-infrastructure.md](./legacy-infrastructure.md) | [infrastructure-layered/deploy.sh](../../infrastructure-layered/deploy.sh) |
| [CLUSTER_AUTOSCALER_README.md](./CLUSTER_AUTOSCALER_README.md) | [cluster-autoscaler-middleware.md](../reference/cluster-autoscaler-middleware.md) |
| [EKS_AUTH_SOLUTIONS.md](./EKS_AUTH_SOLUTIONS.md) | Layered Terragrunt base layer |
| [EKS_ADDON_CORRECT_APPROACH.md](./EKS_ADDON_CORRECT_APPROACH.md) | [ADDONS_AND_COMPUTE.md](../reference/ADDONS_AND_COMPUTE.md) |
| [EKS_ADDON_DEPENDENCY_RESOLUTION.md](./EKS_ADDON_DEPENDENCY_RESOLUTION.md) | [ADDONS_AND_COMPUTE.md](../reference/ADDONS_AND_COMPUTE.md) |
| [TERRAGRUNT_MIGRATION.md](./TERRAGRUNT_MIGRATION.md) | [TERRAGRUNT_QUICKSTART.md](../terragrunt/TERRAGRUNT_QUICKSTART.md) |
| [primitive-collection-state-migration-runbook.md](./primitive-collection-state-migration-runbook.md) | N/A (one-time migration complete) |
| [refactor-project-prompt.md](./refactor-project-prompt.md) | N/A (pre-refactor planning artifact) |
