# Primitive and Collection Refactor State Migration Runbook

## Scope
This runbook applies to the canonical layered stack:
- `infrastructure-layered/base`
- `infrastructure-layered/middleware`
- `infrastructure-layered/application`

## What Changed
- Non-primitive modules were moved from `/modules/primitive` to `/modules/collections`.
- Base and collection EKS cluster usage switched from local `modules/primitive/eks-cluster` to upstream `module_primitive/eks_cluster/aws`.
- Middleware sources were updated to use collection module paths.

## Expected State Impact
For existing resources, module block names are unchanged and key resource addresses remain stable.
In the normal case, no manual `terraform state mv` is required.

## Safe Execution Sequence
1. Backup state before migration.
2. In each layer, run:
   - `terraform init -upgrade`
   - `terraform plan`
3. Review plans for unintended recreate/destroy actions.
4. Apply in layer order:
   - base
   - middleware
   - application

## Validation Gates
Proceed only when:
- No unexpected destroy on `aws_eks_cluster`, node groups, fargate profiles, IAM roles, or security groups.
- Endpoint, autoscaler, ESO, KEDA, and node-termination resources show no destructive drift beyond expected source-path refactor behavior.

## If Unexpected Recreation Appears
1. Stop and do not apply.
2. Capture the exact address diff from plan.
3. If address drift is due to module source/address translation, use targeted state moves.

Example pattern:
```bash
terraform state mv 'old.address' 'new.address'
```

4. Re-run `terraform plan` and confirm drift is resolved before apply.

## Post-Apply Checks
- `terraform output` in each layer succeeds.
- Remote-state consumers in middleware/application read expected outputs.
- Cluster access and add-on workloads remain healthy.
