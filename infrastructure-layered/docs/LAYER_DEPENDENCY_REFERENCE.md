# Layer Dependency Reference

## Overview

This document captures how the layered Terragrunt stack shares information between components. It focuses on:

- Execution order and state hand-offs
- Remote state configuration for each layer
- Output contracts that downstream layers rely on
- Validation steps to confirm the data flow remains healthy

Keeping these contracts explicit makes it easier to troubleshoot empty remote-state reads (for example, when a layer is destroyed) and to reason about the impact of future refactors.

## Layer Execution Order

1. **Base** – provisions the EKS control plane, shared IAM roles, networking references, and the shared KMS key. All other Terraform layers depend on the state written here.
2. **Middleware** – installs KEDA, External Secrets Operator, and buildkitd. Reads base outputs to configure IRSA and encryption integration.
3. **Application** – deploys agent workloads, secrets, and Helm releases. Pulls from both base and middleware state.
4. **Config (post-Terraform)** – optional script-driven tasks (kubectl + AWS CLI) that finalize ESO configuration. This layer runs after Terraform completes and does not write Terraform state.

Terragrunt enforces base → middleware → application ordering through `dependency` blocks and the `deploy.sh` orchestrator.

## Remote State Wiring

Terragrunt stores Terraform state in `s3://${TF_STATE_BUCKET}/${environment}/${layer}/terraform.tfstate`, where `environment` comes from `env.hcl` (for example `dev`) and `layer` is `base`, `middleware`, or `application`.

Each Terraform layer also defines explicit `terraform_remote_state` data sources so the code still works if Terraform is executed directly (without Terragrunt). The resulting wiring looks like this:

| Layer | Produces State Key (default) | Consumes Remote State | Config Variables |
| --- | --- | --- | --- |
| Base | `${environment}/base/terraform.tfstate` | n/a | Managed entirely by Terragrunt |
| Middleware | `${environment}/middleware/terraform.tfstate` | `data.terraform_remote_state.base` | `remote_state_bucket`, `base_state_key` (default `base/terraform.tfstate`), `aws_region` |
| Application | `${environment}/application/terraform.tfstate` | `data.terraform_remote_state.base` and `data.terraform_remote_state.middleware` | `remote_state_bucket`, `remote_state_region` (from root inputs) |

> When running via Terragrunt, the `base_state_key` passed to Terraform must include the environment prefix (for example `dev/base/terraform.tfstate`). The helper inputs in the layer `terragrunt.hcl` files set these defaults. If you clone the repository for a new environment, adjust `env.hcl` or override the key via Terragrunt inputs so the data source points at the correct object.

### Terragrunt `dependency` Blocks vs. `terraform_remote_state`

- `dependency` blocks (defined in `terragrunt.hcl`) give Terragrunt direct access to upstream outputs. They are used to generate provider configuration (`k8s_provider_generated.tf`) and to allow `plan` to run with mock values even if upstream state does not exist yet.
- `terraform_remote_state` data sources live inside the Terraform code (`remote_state.tf`). They are used at runtime by modules and locals (for example, IRSA trust policies). Both mechanisms should point to the same state objects.

## Output Contracts

### Base Outputs Consumed by Downstream Layers

| Output | Meaning | Middleware Usage | Application Usage |
| --- | --- | --- | --- |
| `cluster_name` | Canonical EKS cluster identifier | Names IAM roles, Helm releases, and namespaces | Used in Helm values, IAM role names, and ECR naming |
| `common_tags` | Shared tag map | Merged into middleware `local.common_tags` | Merged into application `local.common_tags` |
| `cluster_oidc_issuer_url` | Public OIDC issuer for the cluster | Converted to host portion in IRSA trust policies | Used to build IRSA trust policy conditions for agent roles |
| `oidc_provider_arn` | IAM OIDC provider ARN | Federated principal for KEDA and ESO IAM roles | Federated principal for agent execution roles |
| `kms_key_arn` | Shared KMS CMK for encryption | Granted to ESO IAM policy for decrypt access | Referenced by Secrets Manager secrets and other encrypted resources |
| `fargate_role_name` | Fargate pod execution role name | Not consumed | Used by the ECR collection module to attach pull permissions |
| `cluster_endpoint`, `cluster_certificate_authority_data` | API endpoint and CA bundle | Injected into generated Kubernetes/Helm providers via Terragrunt | Same as middleware |

### Middleware Outputs Consumed by the Application Layer

| Output | Meaning | Application Usage |
| --- | --- | --- |
| `ado_agents_namespace` | Namespace where agents run | Helm values and scaled-object definitions use this namespace |
| `ado_secret_name` | Expected Kubernetes secret name for the ADO PAT | Referenced in Helm values and ESO integration |
| `cluster_secret_store_name` | ClusterSecretStore identifier | Used when creating ExternalSecret resources |
| `eso_role_arn` | IAM role assumed by ESO | Application attaches additional policy statements for PAT access |
| `keda_namespace` | Namespace where the KEDA operator runs | Ensures Helm release and RBAC target the correct namespace |
| `buildkitd_*` outputs | Buildkit enablement flags and endpoints | Optional integration for image builds (Helm values) |

If any of these outputs change shape (name or data type), all downstream references must be updated together to avoid runtime failures.

## Data Flow Highlights

- **IRSA Trust Chain:** Base publishes the OIDC issuer URL and provider ARN. Middleware and application layers both build IRSA trust policies from those values to grant pods AWS permissions.
- **Shared KMS Key:** Secrets Manager secrets and ESO decryption use the same customer-managed key exported by the base layer. Losing that output causes ESO to fail when fetching secrets.
- **Common Tagging:** Every layer merges the base `common_tags` to ensure resources remain traceable across AWS and Kubernetes components.
- **Namespace Coordination:** Middleware declares authoritative namespaces (KEDA, ESO, ADO). The application layer consumes those values to avoid hard-coded strings in Helm charts and IAM policies.

## Verification Checklist

Run these checks when diagnosing cross-layer issues or after refactoring outputs:

1. **Confirm state objects exist:**

   ```bash
   aws s3 ls "s3://${TF_STATE_BUCKET}/${ENVIRONMENT}/"
   aws s3 ls "s3://${TF_STATE_BUCKET}/${ENVIRONMENT}/base/" --recursive
   ```

2. **Inspect base outputs:**

   ```bash
   cd infrastructure-layered/base
   terragrunt output --json | jq 'keys'
   ```

3. **Inspect middleware outputs:**

   ```bash
   cd ../middleware
   terragrunt output --json | jq 'keys'
   ```

4. **Validate remote state data sources:**

   ```bash
   cd ../middleware
   terragrunt plan -refresh-only
   # Look for "terraform_remote_state.base" to confirm outputs resolve
   ```

5. **Re-run the dependent layer:** if remote state objects were missing (for example after a destroy), redeploy the upstream layer (`./deploy.sh --layer base deploy`) before applying middleware or application.

Export `ENVIRONMENT` to match `env.hcl` (for example `export ENVIRONMENT=dev`) when running the S3 commands above.

## Adding or Modifying Cross-Layer Data

1. Update the upstream Terraform module to expose a new `output` (or adjust an existing one).
2. Re-run `terragrunt apply` for the upstream layer so the state file contains the change.
3. Reference the output in downstream Terraform code (locals, modules, or Helm values) and update any `terragrunt.hcl` dependency mocks.
4. Plan and apply the downstream layer to validate the new data flow.
5. Update this document if the contract or key outputs change.

Keeping this checklist up to date helps avoid subtle cross-layer regressions during refactors.
