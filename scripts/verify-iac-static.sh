#!/usr/bin/env bash

# Runs the complete credential-free IaC quality contract used by GitHub Actions.
# Terraform and Terragrunt initialization occurs only in a disposable copy so
# this command never reads or modifies a developer's ignored env.hcl or caches.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
iac_dir="${repo_root}/infrastructure-layered"
modules_dir="${repo_root}/modules"
work_dir="$(mktemp -d /tmp/iac-static.XXXXXX)"

case "${work_dir}" in
  /tmp/iac-static.*) ;;
  *)
    echo "Refusing to clean an unexpected temporary directory: ${work_dir}" >&2
    exit 1
    ;;
esac

cleanup() {
  rm -rf -- "${work_dir}"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

for command in git make mktemp rsync; do
  require_command "${command}"
done

if [[ ! -f "${iac_dir}/env.sample.hcl" ]]; then
  echo "Missing committed Terragrunt validation fixture: ${iac_dir}/env.sample.hcl" >&2
  exit 1
fi

if [[ ! -f "${iac_dir}/ci/static-provider.tf" ]]; then
  echo "Missing Terraform static-validation fixture: ${iac_dir}/ci/static-provider.tf" >&2
  exit 1
fi

if [[ ! -d "${modules_dir}" ]]; then
  echo "Missing local Terraform modules directory: ${modules_dir}" >&2
  exit 1
fi

echo "==> Git diff whitespace"
git -C "${repo_root}" diff --check

echo "==> GitHub Actions workflow lint"
mise exec -- actionlint

echo "==> Terraform formatting"
mise exec -- terraform fmt -check -recursive "${iac_dir}"

echo "==> ShellCheck"
mise exec -- make -C "${iac_dir}" shellcheck

echo "==> BATS"
mise exec -- make -C "${iac_dir}" bats-test

echo "==> Checkov"
mise exec -- checkov \
  -d "${iac_dir}" \
  --framework terraform \
  --compact \
  --quiet \
  --skip-path .terraform \
  --skip-path .terragrunt-cache

echo "==> Preparing isolated Terragrunt workspace"
ci_iac_dir="${work_dir}/infrastructure-layered"
ci_modules_dir="${work_dir}/modules"
mkdir -p "${ci_iac_dir}"
rsync -a \
  --exclude env.hcl \
  --exclude .terraform \
  --exclude .terragrunt-cache \
  --exclude '*.tfstate' \
  --exclude '*.tfstate.*' \
  --exclude backend_generated.tf \
  --exclude provider_generated.tf \
  --exclude k8s_provider_generated.tf \
  "${iac_dir}/" "${ci_iac_dir}/"
rsync -a "${modules_dir}/" "${ci_modules_dir}/"
cp "${iac_dir}/env.sample.hcl" "${ci_iac_dir}/env.hcl"

for layer in base networking middleware application; do
  layer_dir="${ci_iac_dir}/${layer}"

  echo "==> Terragrunt HCL validation: ${layer}"
  TF_STATE_BUCKET=test-bucket mise exec -- terragrunt hcl validate --working-dir "${layer_dir}"

  echo "==> Terraform initialization and validation: ${layer}"
  cp "${iac_dir}/ci/static-provider.tf" "${layer_dir}/provider_generated.tf"
  mise exec -- terraform -chdir="${layer_dir}" init -backend=false -input=false
  mise exec -- terraform -chdir="${layer_dir}" validate

  echo "==> TFLint: ${layer}"
  mise exec -- tflint --chdir "${layer_dir}" --minimum-failure-severity=warning
done
