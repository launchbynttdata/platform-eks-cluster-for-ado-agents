# Legacy Infrastructure Path Removed

The monolithic `/infrastructure` stack has been **removed** from this repository. It was superseded by the layered Terragrunt architecture.

## Canonical deployment path

Use:
`${REPO_ROOT}/infrastructure-layered/deploy.sh`

## Canonical module path

Local Terraform modules are sourced from:
`${REPO_ROOT}/modules`

## Notes

- The monolithic `ado-eks-cluster` collection module and `app/k8s/` manifests were removed with the legacy stack.
- Any automation that invoked `/infrastructure/deploy.sh` must use the layered deploy script.
