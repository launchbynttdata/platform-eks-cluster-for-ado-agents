# Documentation Hub

Documentation for the EKS cluster platform with Azure DevOps self-hosted agents.

## Start here

| I want to... | Go to |
|--------------|-------|
| Deploy or operate the platform | [deployment/OPERATIONS.md](./deployment/OPERATIONS.md) |
| Quick Terragrunt setup | [terragrunt/TERRAGRUNT_QUICKSTART.md](./terragrunt/TERRAGRUNT_QUICKSTART.md) |
| Configure `env.hcl` | [terragrunt/TERRAGRUNT_CONFIGURATION_REFERENCE.md](./terragrunt/TERRAGRUNT_CONFIGURATION_REFERENCE.md) |
| See what changed | [CHANGELOG.md](../CHANGELOG.md) |
| Understand repo layout | [deployment/PROJECT_STRUCTURE.md](./deployment/PROJECT_STRUCTURE.md) |

---

## Deployment

- [OPERATIONS.md](./deployment/OPERATIONS.md) - Deployment workflow, PAT management, troubleshooting
- [base-layer.md](./deployment/base-layer.md) - EKS cluster, VPC, IAM
- [networking-layer.md](./deployment/networking-layer.md) - Optional CNI deployment layer
- [middleware-layer.md](./deployment/middleware-layer.md) - KEDA, ESO, buildkitd, cluster autoscaler
- [application-layer.md](./deployment/application-layer.md) - ECR, secrets, Helm agents
- [ado-agent-cluster-helm.md](./deployment/ado-agent-cluster-helm.md) - ADO agent Helm chart
- [PROJECT_STRUCTURE.md](./deployment/PROJECT_STRUCTURE.md) - Repository directory layout

---

## Terragrunt

- [TERRAGRUNT_QUICKSTART.md](./terragrunt/TERRAGRUNT_QUICKSTART.md) - Tool install and first deployment
- [TERRAGRUNT_CONFIGURATION_REFERENCE.md](./terragrunt/TERRAGRUNT_CONFIGURATION_REFERENCE.md) - Full `env.hcl` variable reference
- [CONFIG_LAYER_IN_TERRAGRUNT.md](./terragrunt/CONFIG_LAYER_IN_TERRAGRUNT.md) - Post-Terraform config layer (ClusterSecretStore, kubectl)
- [LAYER_DEPENDENCY_REFERENCE.md](./terragrunt/LAYER_DEPENDENCY_REFERENCE.md) - Layer order, remote state, dependencies

---

## Reference

- [IAM_ADO_AGENTS.md](./reference/IAM_ADO_AGENTS.md) - IAM roles and policies for ADO agents
- [FARGATE_CONFIGURATION.md](./reference/FARGATE_CONFIGURATION.md) - Fargate profile configuration
- [ADO_SECRET_MANAGEMENT.md](./reference/ADO_SECRET_MANAGEMENT.md) - ADO PAT lifecycle and ESO sync
- [ADO_KEDA_PROXY.md](./reference/ADO_KEDA_PROXY.md) - SPN-backed proxy for KEDA Azure Pipelines scaling
- [CNI_MODES.md](./reference/CNI_MODES.md) - VPC CNI and optional Cilium overlay networking modes
- [cluster-autoscaler-middleware.md](./reference/cluster-autoscaler-middleware.md) - Cluster autoscaler in layered infra
- [ADDONS_AND_COMPUTE.md](./reference/ADDONS_AND_COMPUTE.md) - EKS addon ordering and compute dependencies
- [reliability-improvements.md](./reference/reliability-improvements.md) - ScaledJob isolation, BuildKit, ECR pull-through cache
- [codebuild-image-build-requirements.md](./reference/codebuild-image-build-requirements.md) - Requirements for optional CodeBuild image build backend

---

## Guides

- [OCI_IMAGE_CROSS_BUILD_README.md](./guides/OCI_IMAGE_CROSS_BUILD_README.md) - Multi-arch image builds
- [ECR_Multiple_Repositories_Example.md](./guides/ECR_Multiple_Repositories_Example.md) - Multiple ECR repositories
- [TESTING.md](./guides/TESTING.md) - ShellCheck, BATS, Checkov
- [infrastructure-tests.md](./guides/infrastructure-tests.md) - BATS test structure

---

## Deprecated

Historical documents are in [deprecated/](./deprecated/). Do not use them for new deployments.

---

## Contributing to documentation

1. **Operational procedures** - Update [deployment/OPERATIONS.md](./deployment/OPERATIONS.md)
2. **Changes and breaking changes** - Update [CHANGELOG.md](../CHANGELOG.md)
3. **Technical deep-dives** - Add under the appropriate section above
4. **Update this hub** - Add links when adding new documents
