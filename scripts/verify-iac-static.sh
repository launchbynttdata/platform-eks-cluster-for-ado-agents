#!/usr/bin/env bash

# Runs the complete credential-free IaC quality contract used by GitHub Actions.
# Terraform and Terragrunt initialization occurs only in a disposable copy so
# this command never reads or modifies a developer's ignored env.hcl or caches.
# Middleware additionally runs native Terraform plan tests with mocked providers
# and overridden base remote-state outputs to exercise configuration permutations.
# Base and application run similar credential-free mock-plan suites in the same
# disposable workspace.

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
checkov_version="$(mise exec -- checkov --version 2>/dev/null | head -1 || true)"
if [[ -z "${checkov_version}" ]]; then
  echo "Checkov is not available via mise. Pin checkov in .tool-versions and the IaC workflow tool_versions." >&2
  exit 1
fi
echo "Using Checkov ${checkov_version} (mise standalone binary; Python runtime not required)"
checkov_report="$(mktemp)"
if ! mise exec -- checkov \
  -d "${iac_dir}" \
  --framework terraform \
  --compact \
  --quiet \
  --skip-download \
  --skip-path .terraform \
  --skip-path .terragrunt-cache \
  -o json > "${checkov_report}" 2>&1; then
  cat "${checkov_report}" >&2
  rm -f "${checkov_report}"
  exit 1
fi
python3 - "${checkov_report}" <<'PY'
import json
import sys

report_path = sys.argv[1]
with open(report_path, encoding="utf-8") as handle:
    data = json.load(handle)

summary = data.get("summary", {})
parsing_errors = data.get("results", {}).get("parsing_errors", [])
failed = summary.get("failed", 0)
passed = summary.get("passed", 0)
skipped = summary.get("skipped", 0)
parsing_error_count = summary.get("parsing_errors", 0)

if parsing_error_count:
    print("Checkov parsing errors:", file=sys.stderr)
    for path in parsing_errors:
        print(f"  - {path}", file=sys.stderr)
    sys.exit(1)

if failed:
    print(
        f"Checkov failed checks: {failed} (passed={passed}, skipped={skipped})",
        file=sys.stderr,
    )
    sys.exit(1)

print(
    f"Checkov passed (passed={passed}, skipped={skipped}, parsing_errors={parsing_error_count})"
)
PY
rm -f "${checkov_report}"

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

  if [[ "${layer}" == "base" || "${layer}" == "middleware" || "${layer}" == "application" ]]; then
    echo "==> Terraform mock-plan tests: ${layer}"
    mise exec -- terraform -chdir="${layer_dir}" test -test-directory=tests
  fi

  echo "==> TFLint: ${layer}"
  mise exec -- tflint --chdir "${layer_dir}" --minimum-failure-severity=warning
done
