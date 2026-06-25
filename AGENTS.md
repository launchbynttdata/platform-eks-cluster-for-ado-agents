# AGENTS.md

## Ways of Working

- Read the live code before making changes. This repo has accumulated several deployment paths and deprecated docs; prefer the current `infrastructure-layered` stack unless the user explicitly asks about deprecated material.
- Keep changes scoped to the requested behavior. Avoid broad formatting passes across HCL files; Terragrunt formatting can touch unrelated files and create noisy diffs.
- Treat `infrastructure-layered/env.hcl` as local-only unless the user explicitly asks to edit their ignored test config. It is gitignored and may contain account, subnet, ADO, or cluster-specific values.
- Use `env.sample.hcl` and committed reference docs for reusable examples. Do not copy private/local values from `env.hcl` into tracked files.
- Assume deployments are layered and stateful. Changes to one layer can affect later layers through remote state, Terragrunt dependency ordering, generated providers, and deploy script orchestration.
- Prefer `mise exec -- <tool>` or existing Make targets when running Terraform, Terragrunt, BATS, or shell tooling.
- When validating deploy script behavior, use BATS. The deploy script is intentionally tested as shell logic, including dry-run ordering and non-interactive credential handling.

## Current Stack Shape

- The active deployment entrypoint is `infrastructure-layered/deploy.sh`.
- Layer order is `base -> networking -> middleware -> application`, with an optional kubectl-based `config` layer after Terraform layers.
- Destroy order is the reverse: `application -> middleware -> networking -> base`.
- `base` owns EKS, IAM, KMS, VPC endpoints, node groups, and CNI bootstrap behavior.
- `networking` currently validates selected pod networking mode and remains a valid no-op for VPC CNI mode.
- `middleware` owns platform operators such as KEDA, External Secrets Operator, BuildKit, observability, and autoscaler components.
- `application` owns ECR repositories, ADO secrets, ADO agent IAM roles, and the ADO agent Helm release.

## CNI Mode Lessons

- Amazon VPC CNI is the default and the only mode compatible with Fargate.
- `cilium-overlay` is EC2-only and is intended to relieve subnet pod IP exhaustion by using Cilium cluster-pool overlay IPAM.
- Do not use Cilium AWS ENI IPAM for this goal; it still consumes VPC subnet IPs for pods.
- In `cilium-overlay`, `fargate_profiles` must be `{}`, at least one EC2 node group must exist, and `vpc-cni` must be removed from `eks_addons`.
- Cilium must be bootstrapped before EKS managed node groups come up. If node groups start without a working CNI, EKS node group creation can fail with `cni plugin not initialized`.
- The base layer patches an existing `aws-node` DaemonSet away from nodes in `cilium-overlay` mode. Be careful when changing this: two CNIs fighting over nodes is worse than a cleanly failed apply.
- Existing VPC CNI clusters should be treated as disruptive conversions, not transparent migrations. For this repo’s intended ephemeral clusters, stopping workload intake and recreating application/middleware workloads is usually cleaner than preserving running pods.
- Private clusters without NAT need reachable Cilium images. The default Cilium chart images are not available through AWS VPC endpoints; mirror images to reachable ECR or configure another accessible registry.

## ADO Agent and Helm Lessons

- The ADO agent Helm release creates placeholder registration Jobs as Helm hooks for enabled autoscaled pools with template-agent creation enabled.
- Helm marks the whole release failed if any hook Job fails, even when other pools deployed successfully.
- When debugging a failed ADO agent Helm release, inspect the exact failed placeholder job, not just any completed placeholder job:
  - `kubectl get jobs,pods -n ado-agents`
  - `kubectl describe job -n ado-agents <failed-placeholder-job>`
  - `kubectl logs -n ado-agents job/<failed-placeholder-job> --all-containers=true`
- Failed hook resources may disappear if TTL cleanup has already run. Preserve failed hook resources while debugging by keeping Helm `atomic` and `cleanup_on_fail` disabled.
- `ADO_PAT` and `ADO_ORG_URL` are deployment-time inputs. The deploy script maps them to Terraform variables and secret update behavior; do not assume `env.hcl` should contain test credentials.
- The Kubernetes bootstrap secret is used before ESO has reconciled. If ADO URL/PAT values change, make sure the bootstrap secret data can update before Helm hooks run.
- Pool-level `image_repository` is only used when no managed ECR repositories are configured. When `ecr_repositories` is non-empty, the application layer uses the managed ECR module outputs keyed by `ecr_repository_key`.

## Testing and Validation

- Useful focused checks:
  - `mise exec -- bats infrastructure-layered/tests/test_credentials.bats infrastructure-layered/tests/test_init.bats infrastructure-layered/tests/test_validation.bats infrastructure-layered/tests/test_noninteractive_workflow.bats`
  - `TF_STATE_BUCKET=test-bucket mise exec -- terragrunt hcl validate --working-dir infrastructure-layered/base`
  - `TF_STATE_BUCKET=test-bucket mise exec -- terragrunt hcl validate --working-dir infrastructure-layered/networking`
  - `TF_STATE_BUCKET=test-bucket mise exec -- terragrunt hcl validate --working-dir infrastructure-layered/application`
- `terragrunt hcl validate` needs `TF_STATE_BUCKET` because the root config requires it.
- Dry-run deploy-script tests are valuable because they catch layer-order regressions without touching AWS.
- Live cluster checks still matter for CNI changes. A successful local validation does not prove Cilium agents are Ready, pods get overlay IPs, or ADO/KEDA workloads can run.

## Documentation Expectations

- Update `docs/terragrunt/TERRAGRUNT_CONFIGURATION_REFERENCE.md` for public `env.hcl` interface changes.
- Update `docs/terragrunt/LAYER_DEPENDENCY_REFERENCE.md` when layer order, remote-state usage, or dependency assumptions change.
- Update `docs/reference/CNI_MODES.md` when changing pod networking behavior or Cilium settings.
- Keep deployment docs aligned with `deploy.sh` flags and layer order.
- If a change is feature enablement rather than a migration, document migration/conversion notes separately as operational guidance rather than making Terraform perform an opaque migration workflow.

## Source Control Hygiene

- Check `git status --short` before and after edits.
- Do not revert user edits or ignored local configuration unless the user explicitly asks.
- `local_code_review.md` is a local peer-review artifact and should not be committed. If the user asks to work from it, validate each finding directly in the codebase, fix confirmed issues, and append a follow-up section without rewriting existing review text.
- Be careful with commands that rewrite formatting across the repo; if they touch unrelated tracked files, either justify the churn or revert only the accidental formatting changes.
- Local `main` should be kept current with `origin/main` before judging whether work is branch-only.
