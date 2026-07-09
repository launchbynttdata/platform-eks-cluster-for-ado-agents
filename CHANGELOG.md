# Changelog

This document tracks significant changes, fixes, and improvements. Entries are ordered by date (most recent first). Dates reflect last significant update per source document.

## 2026-07-09

- **KEDA SPN authentication**: Added `app/ado-keda-proxy`, a first-class Go proxy that lets the official KEDA Azure Pipelines scaler poll Azure DevOps with SPN-backed bearer tokens instead of a real PAT in SPN mode. The proxy is allowlist-only, strips sensitive headers, pins token acquisition to Microsoft login hosts, exposes health/readiness endpoints, runs as a non-root distroless container, and is covered by focused security-negative tests.
- **Proxy release and image publishing**: Added GitHub Actions workflows for proxy PR validation and tag-based releases from `ado-keda-proxy/vX.Y.Z`, publishing multi-architecture images to `ghcr.io/launchbynttdata/platform-eks-cluster-for-ado-agents/ado-keda-proxy` with OCI metadata and semver-derived tags.
- **ADO agent SPN mode**: Added `ado_agent_auth_mode = "spn"` support using an externally managed AWS Secrets Manager SPN secret containing `ClientId`, `ClientSecret`, and `TenantId`. Terraform now reads and grants ESO access to that existing secret without creating or managing the secret value.
- **PAT removal in SPN mode**: Application-layer Terraform now removes real PAT desired state in SPN mode, including PAT AWS secret/version creation, PAT bootstrap secret rendering, PAT ExternalSecret rendering, PAT deploy-script injection, and PAT-oriented operational outputs. PAT mode remains unchanged.
- **KEDA proxy Helm integration**: The ADO agent chart renders the proxy Deployment, Service, optional NetworkPolicy, and dummy non-secret KEDA auth Secret only in SPN proxy mode. SPN-mode ScaledJobs point `organizationURL` at the proxy Service while agent pods keep the real Azure DevOps URL and SPN credential refs.
- **ScaledJob worker model**: ADO agent autoscaling uses KEDA `ScaledJob` workers with placeholder registration Jobs and offline template agents for queue matching. The deploy script refresh path now restarts KEDA after secret updates and notes that ScaledJob workers consume refreshed secrets on the next queued job.
- **CloudWatch observability**: Added middleware-layer CloudWatch log group management, optional Amazon CloudWatch Observability EKS add-on support, Fargate Fluent Bit logging ConfigMap support, Application Signals namespace exclusions, and an `enable_ado_agent_cloudwatch_log_groups` escape hatch for accounts where deploy roles or KMS policies cannot create the ADO agent log group.
- **Deploy script hardening**: ADO auth-mode detection is bash 3.2-compatible and fails closed when the mode cannot be determined. `--update-ado-secret` is rejected in SPN mode because SPN credential rotation is owned externally.
- **Layer initialization reliability**: Deploy, plan, and apply paths now clear local `.terragrunt-cache` and `.terraform` directories before each layer initialization so deployments do not trust stale local provider plugins, generated modules, or Terragrunt cache contents.
- **Deployment prerequisites**: Documented that ADO agent container images must exist in the configured repositories before the application layer deploys, because Terraform may create ECR repositories but does not build or push the image tags Helm references.
- **ADO image build workflow**: Updated `app/build-and-push-ecr.sh` so structure-tested image pushes do not rebuild after tests pass and do not publish temporary ECR tags before tests pass. Single-platform pushes now build, load, test, and push the same image; multi-platform pushes build and test each requested platform locally, then publish temporary per-platform tags only after all tests pass, promote those images to the requested manifest tag, and clean up the temporary tags.
- **Documentation and tests**: Added the ADO KEDA proxy reference, expanded Terragrunt configuration docs, pinned Go with `mise`, and added Go, Helm render, Terragrunt HCL, and BATS coverage for the SPN/KEDA migration paths.

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
