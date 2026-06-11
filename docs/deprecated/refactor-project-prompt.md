# EKS ADO Agent Cluster Refactor – Requirements Document

## Overview

The current EKS-based ADO agent cluster has reached operational maturity but suffers from technical debt that inhibits sustainable maintenance, reproducibility, and modular upgrades. This project aims to refactor the infrastructure and deployment codebase to meet the following key goals:

- **Eliminate internal circular dependencies**
- **Segment IaC into cleanly layered states**
- **Enable sustainable redeployments**
- **Support independent lifecycle management of cluster components**
- **Provide a turn-key orchestration mechanism for end-to-end deployment**

> **AI Implementation Context**  
This project will be implemented by an **AI coding agent**. To ensure a successful, accurate, and reliable implementation:
>
> 1. **No assumptions are permitted.** If an AI agent encounters an ambiguous instruction, conflicting dependency, or incomplete requirement, it must flag the issue and request clarification.  
> 2. **Guardrails must be enforced.** Each layer of infrastructure must define explicit dependencies, inputs, and outputs. No implicit dependency or hidden configuration should exist.
> 3. **Work incrementally and checkpoint frequently.** Each logical unit of work should conclude with a validation step (plan output, test pass, etc.) that confirms intent vs result.
> 4. **No hardcoded values.** Every configurable parameter (e.g., region, version, agent pool, secret name) must be abstracted to a variable and validated.
> 5. **All operations must be idempotent.** Repeated execution of any step should not produce errors, duplicates, or undesired side effects.
> 6. **Document assumptions inline.** Where interpretation is required, the agent must include an inline comment explaining its assumption and flag it for review.
> 7. **All changes must be reviewable.** Code should be committed in discrete units of work, with descriptive commit messages summarizing intent, changes made, and any unresolved decisions.

> **Clarification Protocol**  
If there are **questions**, **ambiguous requirements**, or **uncertainty about how something should be implemented**, the AI agent must:
>
> - Flag the problem in context
> - Propose a resolution based on best practices (if known)
> - Request explicit confirmation before proceeding
>
> Requirements must never be implemented based on assumption alone.

---

## 1. Infrastructure Segmentation

Refactor the Infrastructure-as-Code (IaC) and manifests into **three distinct deployment stages**, each with its own Terraform state and deployment lifecycle.

### 1.1 Base Infrastructure

- Deploys:
  - EKS Cluster
  - Node Groups (including any Fargate profiles if used)
  - IAM Roles & Policies for worker nodes
  - EKS-managed Add-ons (e.g., VPC CNI, CoreDNS, kube-proxy, metrics-server)
  - Cluster Autoscaler (if needed)
  - KMS Keys for EKS encryption
  - VPC Endpoints for AWS services
- Constraints:
  - No dependency on middleware or application layer resources
  - Fully self-contained state file
  - Uses remote state for sharing outputs with other layers

### 1.2 Middleware Layer

- Deploys:
  - KEDA Operator
  - Buildkitd service (as separate Kubernetes deployment with auto-scaling rules and standalone service for cluster-wide availability)
  - External Secrets Operator (ESO)
  - ADO agents namespace (shared by application layer)
  - Supporting IAM Roles/Policies, Kubernetes service accounts for middleware components
- Constraints:
  - Assumes base infrastructure is deployed (reads from base layer remote state)
  - Must not reference application layer resources
  - Abstracted configuration for software versions, scaling thresholds, secrets retrieval, etc.
  - Uses remote state for sharing outputs with application layer

### 1.3 Application Layer

- Deploys:
  - ECR repositories for ADO agent images
  - AWS Secrets Manager secrets for ADO PAT
  - ADO Agent Deployments (as Kubernetes workloads via Helm charts)
  - KEDA `ScaledObjects` and `TriggerAuthentications` (via Helm)
  - Kubernetes ServiceAccounts with IRSA annotations (via Helm)
  - ESO ExternalSecret and ClusterSecretStore resources for specific secrets
- Constraints:
  - No dependency on middleware implementation specifics (e.g., buildkit version)
  - Abstract agent pool configurations and trigger logic into parameterized variables
  - All Kubernetes resources deployed via Helm charts managed by Terraform
  - Reads configuration from base and middleware layer remote states

---

## 2. Decoupled Lifecycle & Upgrade Tolerance

Each layer must support updates and operations without requiring upstream layer redeployments:

- **Base Layer Flexibility**:
  - Node group scaling and Kubernetes version upgrades must not affect middleware or application layer
- **Middleware Decoupling**:
  - Middleware version upgrades must not trigger application layer redeploys
- **Application Portability**:
  - Application deployment must be environment-agnostic and parameter-driven
  - Variables should support overrides via environment or CLI to allow flexible deployment scenarios

---

## 3. Turn-Key Orchestration

Develop a single **orchestration script or tool** that supports full end-to-end deployment of the EKS ADO Agent cluster.

### 3.1 Script Features

- Executable from CLI (Makefile or Bash)
- Supports:
  - Fresh cluster bootstrap (all 3 layers in order)
  - Partial re-deployments (e.g., just middleware)
  - Dry run / plan mode
- Environment variable and/or CLI argument support for configuration overrides
- Detects and handles existing state with safety checks (idempotency, minimal downtime)
- Uses Terraform remote state for each layer with proper locking
- Logs each stage of the deployment with summary output

### 3.2 Script Requirements

- Compatible with CI/CD pipelines (headless execution)
- Clear documentation and README for usage
- Validates prerequisites:
  - Terraform version constraints: `<~ 1.5`
  - kubectl within 3 minor revisions of deployed Kubernetes version
  - AWS CLI managed externally (no validation required)
- Does not support migration from existing state (clean deployment approach)
- Retry-safe and restartable for robust deployment experience

---

## 4. Code Quality & Structure

- Refactor configuration to use input variables for all environment-, region-, and app-specific values
- Minimize hardcoded values in Terraform and manifests
- Split large objects into composable modules or Helm charts (where applicable)
- Iteratively process resources (e.g., for multiple agents) rather than static definitions
- **Configuration Management Strategy**: Use Terraform to manage Helm chart deployments with all configuration passed from a top-level variables file, cascaded through modules
- **Variable Granularity Guidelines**:
  - Tags: Configurable with base set inherited from top-level module
  - Kubernetes resource limits: Defaults based on current implementation, overrideable via variables
  - KEDA scaling configuration: Defaults based on current settings, overrideable via variables
  - Focus on common configurability without requiring full Kubernetes specs via variables
- **IAM Abstraction**: Extract IAM roles and policies to configurable variable maps with current values as defaults, enabling "upward" reference via service accounts using matching keys

---

## 5. Testing and Validation

- Add local validation (linting, plan checks, schema validation)
- **Integration Testing**: Deferred to Phase 2 of the project
- Implement validation scenarios to verify:
  - Successful base cluster setup
  - Middleware operator function (e.g., KEDA + External Secrets)
  - Basic infrastructure connectivity and component health
- Focus on infrastructure deployment validation rather than end-to-end pipeline testing

---

## 6. Deliverables

- Fully modular Terraform codebase with 3 independent state directories using remote state
- Parameterized Helm charts for application layer deployments managed via Terraform
- Orchestration script with README and usage instructions
- Documentation describing architecture, layering assumptions, and lifecycle expectations
- **Feature Parity**: Maintain high-level feature compatibility with current implementation
- **Optimization Opportunities**: Implement security and architecture improvements as defaults
  - Update to latest stable versions of KEDA, ESO, and other components
  - Enhance security configurations following best practices
  - Maintain backward compatibility for variable interfaces where possible

---

## 7. Requirements Clarifications & Decisions

This section documents the clarified requirements and architectural decisions made during the requirements review process.

### 7.1 Infrastructure Layer Boundaries

**Base Infrastructure Layer:**
- **Components**: EKS Cluster, Node Groups, Fargate profiles, IAM roles for worker nodes, EKS add-ons, Cluster Autoscaler, KMS keys for EKS encryption, VPC endpoints
- **State Management**: Uses remote state for sharing outputs with middleware and application layers
- **Decision**: KMS keys and VPC endpoints belong with EKS cluster in base layer for logical grouping

**Middleware Layer:**
- **Components**: KEDA Operator, External Secrets Operator (ESO), Buildkitd service (standalone deployment), ADO agents namespace
- **Buildkitd Service**: Separate Kubernetes deployment with auto-scaling rules, available as standalone service for cluster-wide use
- **Namespace Strategy**: ADO agents namespace created in middleware layer since the overall project purpose is ADO agent hosting
- **Dependencies**: Reads from base layer remote state, shares outputs via remote state to application layer

**Application Layer:**
- **Components**: ECR repositories, AWS Secrets Manager secrets for ADO PAT, ADO agent deployments (via Helm), KEDA ScaledObjects and TriggerAuthentications (via Helm), ServiceAccounts with IRSA (via Helm), ESO ExternalSecret and ClusterSecretStore resources
- **Decision**: ECR and ADO PAT secrets moved to application layer for better logical separation
- **ESO Integration**: Configurable ESO objects defined in application layer for accessing specific secrets

### 7.2 Configuration Management Strategy

**Unified Configuration Approach:**
- **Single Source**: All configuration managed through one top-level variables file
- **Terraform-Managed Helm**: Terraform manages Helm chart deployments with variable cascading
- **Configuration Flow**: Top-level variables → Terraform modules → Helm chart values

**Variable Granularity:**
- **Tags**: Configurable with mandatory base set inherited from top-level
- **Resource Limits**: Current implementation as defaults, overrideable via variables
- **KEDA Configuration**: Current settings as defaults, overrideable via variables
- **Scope**: Focus on common configurability without requiring full Kubernetes specifications

**IAM Abstraction:**
- **Current Values as Defaults**: Extract existing IAM roles and policies to variable maps
- **Upward Reference Pattern**: Service accounts reference IAM roles via matching keys in variable maps
- **Configurability**: All IAM policies configurable via variable maps

### 7.3 Orchestration & State Management

**Remote State Strategy:**
- **Storage Backend**: Remote state stored in S3 bucket (provided externally)
- **State Organization**: Each layer uses sub-paths within the S3 bucket for state separation
  - Base Layer: `s3://bucket-name/base/terraform.tfstate`
  - Middleware Layer: `s3://bucket-name/middleware/terraform.tfstate`
  - Application Layer: `s3://bucket-name/application/terraform.tfstate`
- **Per-Layer States**: Each layer maintains independent remote state
- **State Locking**: Rely on Terraform remote state locking mechanisms (S3 lockfile)
- **Inter-Layer Communication**: Use remote state data sources for passing information between layers

**Deployment Approach:**
- **Clean Deployment**: No migration support from existing infrastructure
- **Fresh Start**: New deployments for refactor validation and testing
- **Tear-Down Friendly**: Infrastructure designed for easy deployment and destruction during development

**Prerequisites:**
- **Terraform**: Version constraint `<~ 1.5`
- **kubectl**: Within 3 minor revisions of deployed Kubernetes version
- **AWS CLI**: Managed externally, no validation required

### 7.4 Application Layer Architecture

**Helm Chart Strategy:**
- **Comprehensive Coverage**: Include all necessary components for KEDA-managed ADO agent deployments
- **Included Components**: ServiceAccounts, TriggerAuthentication, ScaledObject, Deployments, etc.
- **Terraform Management**: Helm charts deployed and managed via Terraform

**Configuration Integration:**
- **Terraform Outputs to Helm**: IRSA role ARNs and other infrastructure outputs passed to Helm charts
- **Environment Specific**: Support for environment-specific overrides via Terraform variables

### 7.5 Feature Parity & Optimization

**Compatibility Requirements:**
- **High-Level Features**: Maintain same feature set as current implementation
- **IAM Roles**: Preserve existing roles and policies as defaults with configurable overrides
- **Kubernetes Resources**: Maintain same resource types and configurations as defaults

**Optimization Opportunities:**
- **Version Updates**: Update to latest stable versions of KEDA, ESO, and other components
- **Security Enhancements**: Implement security best practices as defaults
- **Architecture Improvements**: Enhance overall architecture while maintaining compatibility

### 7.6 Testing Strategy

**Phase 1 Scope:**
- **Infrastructure Validation**: Focus on deployment success and component health
- **Component Connectivity**: Verify middleware and application layer components are properly deployed
- **Deferred Integration**: End-to-end pipeline testing deferred to Phase 2

**Validation Approach:**
- **Local Validation**: Linting, plan checks, schema validation
- **Deployment Verification**: Confirm successful deployment of all three layers
- **Health Checks**: Basic connectivity and component status verification

---

## 8. Guidelines for AI Agent Implementation

### 8.1 General Rules

| Rule | Description |
|------|-------------|
| No Assumptions | Do not implement logic based on incomplete context. Always ask. |
| Explicit Inputs and Outputs | Every module, script, or deployment must define and document its inputs/outputs. |
| Idempotency | All Terraform and Kubernetes operations must be idempotent. |
| No Hardcoded Values | All configuration must be passed via variables or values.yaml |
| Reviewable Commits | Use small, descriptive commits. |
| Inline Comments | All inferred logic must be tagged with `REVIEW:` and documented. |
| No Cross-Layer Reach | Lower layers may not depend on higher ones. Only pass data via outputs/inputs. |

### 8.2 Deployment Protocol

- Base Layer: Terraform module `eks-base`, validates via `kubectl get nodes`
- Middleware Layer: Terraform + Helm/Kustomize, validate pods + CRDs
- Application Layer: Agent deployments, KEDA ScaledObjects, etc.

### 8.3 Orchestration Script

| Item | Description |
|------|-------------|
| Language | Bash, Makefile, or Python |
| Features | Partial deploy, dry run, env overrides |
| Safe | Must be retry-safe and restartable |

### 8.4 Decision Review Tags

```hcl
# REVIEW: Clarified interpretation of X — requires confirmation
# REVIEW: Assumed Y based on best practice Z — confirm
# NOTE: Abstracted value for future portability
# TODO: Pending confirmation on integration behavior
```

### 8.5 Pre-Delivery Checklist

- [ ] `terraform fmt` and `validate` pass
- [ ] All inputs/outputs documented
- [ ] README complete
- [ ] No unresolved `REVIEW:` tags
- [ ] Sample plan/test attached (when feasible)

---

## 9. Terraform Module Conventions

### ✅ Primitive Modules

Primitive modules model individual resources or small groups.

#### Structure

```
infrastructure/modules/primitives/<name>/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md
├── examples/
└── terraform.tfvars.sample
```

#### Requirements

- No hardcoded values
- Expose all important resource arguments
- Include runnable `examples/`
- Include `README.md`, `terraform.tfvars.sample`, `versions.tf`
- Pass `terraform validate` and `fmt`

#### Updating Existing Primitives

- Prefer non-breaking changes
- Document breaking changes in `README` and MR
- Add missing files and test plans

---

### 🧱 Collection Modules

Compose primitives into complete services.

#### Structure

```
infrastructure/modules/collections/<name>/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md
├── remote_state.tf
└── terraform.tfvars.sample
```

#### Requirements

- Compose primitives
- Use `remote_state.tf` to pull from dependent outputs
- Document dependencies and usage

---

## 10. Application Deployment Packaging

### 🎯 Objective

All "naked" Kubernetes YAMLs used for agent deployments and KEDA objects must be refactored into a Helm chart.

### 📁 Chart Structure

```
infrastructure/helm/ado-agent-cluster/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── agent-deployment.yaml
│   ├── keda-scaledobject.yaml
│   ├── serviceaccount.yaml
│   └── _helpers.tpl
├── values.schema.json
└── README.md
```

### ✅ Requirements

| Requirement | Description |
|------------|-------------|
| Templated Deployment | Use Helm templates for all manifests |
| Configurable | All values via `values.yaml` |
| Schema Validated | Include `values.schema.json` |
| CI Compatible | Support `helm lint` and `helm template` |
| Extensible | Support future expansion (e.g., multiple agent pools) |

### 🧪 Testing

- Provide `values.override.yaml`
- Validate with:

  ```bash
  helm template ./infrastructure/helm/ado-agent-cluster/ -f values.override.yaml
  ```
