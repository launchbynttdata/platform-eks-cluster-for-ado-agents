#!/usr/bin/env bash

set -euo pipefail

cat >&2 <<'MSG'
[DEPRECATED] The legacy /infrastructure deployment path is no longer supported.

Use the layered Terragrunt orchestrator instead:
  /Users/a267326/git_repos/launch/platform-eks-cluster-for-ado-agents/infrastructure-layered/deploy.sh

Examples:
  cd /Users/a267326/git_repos/launch/platform-eks-cluster-for-ado-agents/infrastructure-layered
  ./deploy.sh validate
  ./deploy.sh plan
  ./deploy.sh deploy
MSG

exit 1
