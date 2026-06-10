#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SCRIPT_NAME="${0##*/}"
readonly PLAN_FILE=".harness.tfplan"
readonly DESTROY_CONFIRMATION="destroy test harness"

COMMAND="help"
AUTO_APPROVE=false
VERBOSE=false
VAR_FILE=""

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] COMMAND

Commands:
  init       Initialize the test harness Terraform root
  plan       Show a Terraform plan for the test harness
  deploy     Plan, apply, and show outputs for the test harness
  destroy    Plan and destroy the test harness after explicit confirmation
  output     Show Terraform outputs for the test harness
  help       Show this help text

Options:
  --var-file FILE     Pass a Terraform variable file to plan/deploy/destroy
  --auto-approve      Skip the destroy confirmation prompt
  --verbose           Print commands before running them
  --help              Show this help text

Examples:
  ./${SCRIPT_NAME} init
  ./${SCRIPT_NAME} plan --var-file terraform.tfvars
  ./${SCRIPT_NAME} deploy --var-file terraform.tfvars
  ./${SCRIPT_NAME} destroy --var-file terraform.tfvars
EOF
}

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

normalize_var_file() {
  local input_path="$1"
  local input_dir
  local input_base

  if [[ "${input_path}" = /* ]]; then
    VAR_FILE="${input_path}"
  else
    input_dir="$(dirname "${input_path}")"
    input_base="$(basename "${input_path}")"
    VAR_FILE="$(cd "${input_dir}" && pwd)/${input_base}"
  fi

  if [[ ! -f "${VAR_FILE}" ]]; then
    log_error "Variable file not found: ${VAR_FILE}"
    exit 1
  fi
}

terraform_cmd() {
  if command -v mise >/dev/null 2>&1; then
    mise exec -- terraform "$@"
  else
    terraform "$@"
  fi
}

run_terraform() {
  if [[ "${VERBOSE}" == "true" ]]; then
    printf '+ terraform -chdir=%q' "${SCRIPT_DIR}" >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
  fi

  terraform_cmd -chdir="${SCRIPT_DIR}" "$@"
}

require_harness_root() {
  if [[ ! -f "${SCRIPT_DIR}/main.tf" ]]; then
    log_error "Harness Terraform root is missing: ${SCRIPT_DIR}/main.tf"
    log_error "Create the optional test harness IaC before running ${COMMAND}."
    exit 1
  fi
}

cleanup_plan() {
  if [[ -f "${SCRIPT_DIR}/${PLAN_FILE}" ]]; then
    rm -f "${SCRIPT_DIR:?}/${PLAN_FILE}"
  fi
}

confirm_destroy() {
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    log "Auto-approve set; skipping destroy confirmation prompt."
    return 0
  fi

  printf 'Type "%s" to destroy the test harness: ' "${DESTROY_CONFIRMATION}" >&2
  local confirmation
  read -r confirmation

  if [[ "${confirmation}" != "${DESTROY_CONFIRMATION}" ]]; then
    log_error "Destroy cancelled. Confirmation phrase did not match."
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --var-file)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          log_error "--var-file requires a file path."
          exit 1
        fi
        normalize_var_file "$2"
        shift 2
        ;;
      --auto-approve)
        AUTO_APPROVE=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --help|-h)
        COMMAND="help"
        shift
        ;;
      init|plan|deploy|destroy|output|help)
        if [[ "${COMMAND}" != "help" ]]; then
          log_error "Only one command may be provided."
          exit 1
        fi
        COMMAND="$1"
        shift
        ;;
      *)
        log_error "Unknown argument: $1"
        usage >&2
        exit 1
        ;;
    esac
  done
}

cmd_init() {
  require_harness_root
  run_terraform init
}

cmd_plan() {
  require_harness_root
  local plan_args=()
  if [[ -n "${VAR_FILE}" ]]; then
    plan_args+=("-var-file=${VAR_FILE}")
  fi

  run_terraform init
  run_terraform plan "${plan_args[@]}"
}

cmd_deploy() {
  require_harness_root
  cleanup_plan
  trap cleanup_plan EXIT

  run_terraform init
  run_terraform validate
  local plan_args=()
  if [[ -n "${VAR_FILE}" ]]; then
    plan_args+=("-var-file=${VAR_FILE}")
  fi
  run_terraform plan "${plan_args[@]}" -out="${PLAN_FILE}"
  run_terraform apply "${PLAN_FILE}"
  cleanup_plan
  trap - EXIT

  log "Test harness deployed. Relevant outputs:"
  run_terraform output
}

cmd_destroy() {
  require_harness_root
  cleanup_plan
  trap cleanup_plan EXIT

  run_terraform init
  local plan_args=("-destroy")
  if [[ -n "${VAR_FILE}" ]]; then
    plan_args+=("-var-file=${VAR_FILE}")
  fi
  run_terraform plan "${plan_args[@]}" -out="${PLAN_FILE}"
  confirm_destroy
  run_terraform apply "${PLAN_FILE}"
  cleanup_plan
  trap - EXIT
}

cmd_output() {
  require_harness_root
  run_terraform output
}

main() {
  parse_args "$@"

  case "${COMMAND}" in
    init)
      cmd_init
      ;;
    plan)
      cmd_plan
      ;;
    deploy)
      cmd_deploy
      ;;
    destroy)
      cmd_destroy
      ;;
    output)
      cmd_output
      ;;
    help)
      usage
      ;;
    *)
      log_error "Unknown command: ${COMMAND}"
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
