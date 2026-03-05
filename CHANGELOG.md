# Changelog

This document tracks significant changes, fixes, and improvements. Entries are ordered by date (most recent first). Dates reflect last significant update per source document.

## 2026-03-05

- **IAM documentation**: Updated IAM roles and policies documentation for ADO agents
- **Documentation consolidation**: User/developer docs consolidated into docs/; working docs distilled into root CHANGELOG
- **modules/dark**: Primitives staged for cleanup after Launch registry migration (historical reference)

## 2026-02-13

- **kubectl configuration**: Fixed kubectl not configured for fresh deployments; validation failures now stop deployment; base layer waits for cluster ACTIVE before proceeding
- **ClusterSecretStore fix**: Corrected ServiceAccount/namespace references (external-secrets, external-secrets-system) to match ESO deployment
- **Dynamic config from Terraform**: Config layer reads ESO namespace, ServiceAccount, ClusterSecretStore from Terraform outputs instead of hardcoded values
- **Deploy script refactoring**: Summary and phase 1 results; improved error handling and layer workflow
- **KEDA CloudEventSource fix**: Disabled CloudEventSource controllers by default to prevent CrashLoopBackOff when CRDs not installed; configurable via `keda_enable_cloudeventsource` and `keda_enable_cluster_cloudeventsource`
- **Terragrunt configuration**: Updated configuration reference documentation
- **Primitive-collection conformance**: Module conformance rules and classification matrix

## 2026-02-12

- **Environment variable preservation**: Scripts no longer overwrite AWS_REGION and other env vars; use `${VAR:-default}` pattern; direnv and similar tools now work correctly
- **EKS addon split**: Split VPC CNI from other addons to prevent CoreDNS degraded state; proper dependency ordering

## 2026-01-06

- **Terraform backend refactoring**: Migrated from sed file rewriting to Terraform partial backend configuration (`-backend-config` flags); removed substitute/restore logic; cross-platform compatible
- **Config layer integration**: Post-deployment configuration as fourth "config" layer in deploy.sh; unified workflow base → middleware → application → config; ClusterSecretStore creation via kubectl
- **Cluster autoscaler**: Fixed deployment automation; validation now runs even when no Terraform changes; removed duplicate code causing syntax error
- **VPC CNI IRSA**: Created dedicated IAM role for vpc-cni with correct trust policy; proper OIDC provider integration
- **Region propagation**: AWS region now flows from single source; added `--region` to Kubernetes/Helm provider exec blocks; removed hard-coded region from agent pools
- **KEDA CRD timing**: Documented CRD timing limitation; ClusterSecretStore created via config layer after ESO CRDs available
- **ESO externalization cleanup**: Removed `create_cluster_secret_store` variable; explicit that config layer handles ClusterSecretStore
- **Terragrunt migration**: Refactored to Terragrunt; single env.hcl for configuration; deploy.sh now Terragrunt-based; config layer with feature parity
- **Init command enhancement**: Terragrunt init improvements
- **Post-deploy restructure**: Moved post-deploy from middleware to infrastructure-layered root
- **Config layer secret update**: ADO secret injection opt-in by default; credential handling via environment variables
- **Deploy script**: Analysis, improvements (auto-approve, fail-fast), plan-file and layer-mode changes, cleanup and testing setup

## Historical (pre-2026)

- **EKS addon dependency resolution**: vpc-cni requires IRSA before installation; proper dependency ordering
- **EKS authentication**: Documented access entry vs aws-auth ConfigMap approaches
- **Cluster autoscaler**: IAM roles, policies, configurable parameters; Fargate + EC2 hybrid
- **ECR**: Multiple repository support, per-repo IAM policies, cross-account pull
- **OCI image cross-build**: Multi-arch (ARM64/AMD64), BuildKit configuration
- **Infrastructure layering**: Three-layer architecture (base/middleware/application), remote state dependencies

## Breaking Changes

- **Middleware**: ClusterSecretStore must be created via config layer (`./deploy.sh --layer config deploy`), not Terraform
- **Application**: `agent_pools` has dynamic region injection; removed hard-coded `AWS_DEFAULT_REGION`

## Known Issues

- **CRD timing**: Terraform cannot create kubernetes_manifest for CRDs installed in same apply; config layer handles ClusterSecretStore
- **External Secrets**: Default refresh 1 hour; delete K8s secret to force immediate resync
- **KEDA cold start**: First agent ~60s on Fargate; consider `minReplicaCount` > 0 for critical pools
