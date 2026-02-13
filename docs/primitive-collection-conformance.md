# Primitive and Collection Conformance

## Purpose
This document defines and records conformance for Terraform modules under `/modules` after the single-source-of-truth migration.

## Conformance Rules
A module is a **primitive** when all of the following are true:
- Manages one infrastructure concern/resource type.
- Has no environment-specific hard-coded resource bundles.
- Exposes behavior via inputs, with minimal opinionated orchestration.
- Is reusable without workload-specific assumptions.

A module is a **collection** when any of the following are true:
- Composes multiple primitives into a workflow or platform component.
- Encodes workload/platform behavior (for example KEDA, ESO, autoscaler, endpoint sets).
- Includes cross-resource orchestration and sequencing logic.

## Current Classification Matrix
| Module | Classification | Status | Notes |
|---|---|---|---|
| `modules/primitive/ecr-repository` | Primitive | Pass | Kept local. No resolvable upstream primitive found in registry. |
| `modules/primitive/eks-node-group` | Primitive | Pass | Kept local. No resolvable upstream primitive found in registry. |
| `modules/primitive/fargate-profile` | Primitive | Pass | Kept local. No resolvable upstream primitive found in registry. |
| `modules/collections/vpc-endpoints` | Collection | Pass | Reclassified from primitive due endpoint-set orchestration logic. |
| `modules/collections/keda-operator` | Collection | Pass | Reclassified from primitive. |
| `modules/collections/external-secrets-operator` | Collection | Pass | Reclassified from primitive. |
| `modules/collections/cluster-autoscaler` | Collection | Pass | Reclassified from primitive. |
| `modules/collections/metrics-server` | Collection | Pass | Reclassified from primitive. |
| `modules/collections/node-termination-handler` | Collection | Pass | Reclassified from primitive. |
| `modules/primitive/iam-roles` | N/A | Removed | Hard-coded role bundle (non-primitive behavior). |
| `modules/primitive/security-group` | N/A | Removed | Replaced by upstream `module_primitive/security_group/aws`. |
| `modules/primitive/eks-cluster` | N/A | Removed | Replaced by upstream `module_primitive/eks_cluster/aws`. |

## Upstream Primitive Adoption
Implemented in this repository:
- `terraform.registry.launch.nttdata.com/module_primitive/eks_cluster/aws` (`~> 0.1`)
- `terraform.registry.launch.nttdata.com/module_primitive/security_group/aws` (`~> 0.1`)

Unresolved in current registry (version endpoint returns internal error for tested names):
- ECR repository primitive
- EKS node group primitive
- EKS fargate profile primitive
- VPC endpoint primitive

These remain local for now to avoid deployment breakage.
