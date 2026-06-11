# Legacy Infrastructure Path Deprecated

The `/infrastructure` stack is deprecated and is no longer supported for active deployments.

## Canonical deployment path

Use:
`${REPO_ROOT}/infrastructure-layered/deploy.sh`

## Canonical module path

Local Terraform modules are now sourced from:
`${REPO_ROOT}/modules`

## Notes

- `/infrastructure/modules` has been removed.
- Any existing automation that invoked `/infrastructure/deploy.sh` must be updated to use the layered deploy script.
