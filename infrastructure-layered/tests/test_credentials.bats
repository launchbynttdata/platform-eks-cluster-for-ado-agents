#!/usr/bin/env bats
# Unit tests for ADO credential validation and helper functions.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export DEPLOY_LAYERS_DIR="${SCRIPT_DIR}"
    export TF_STATE_BUCKET="test-bucket"
    export AUTO_APPROVE="true"
    export DRY_RUN="false"
    export VERBOSE="false"
    export UPDATE_ADO_SECRET="true"

    # shellcheck source=/dev/null
    source <(sed '/^if \[\[ "\${BASH_SOURCE\[0\]}" == "\${0}" \]\]; then/,$d' "${SCRIPT_DIR}/deploy.sh")
    init_log_colors
}

teardown() {
    unset ADO_PAT ADO_ORG_URL TF_VAR_ado_pat_value TF_VAR_ado_url TF_VAR_ado_org DEPLOY_LAYERS_DIR
}

@test "is_non_empty: rejects whitespace-only values" {
    run is_non_empty "   "
    [ "$status" -eq 1 ]
}

@test "is_non_empty: accepts non-blank values" {
    run is_non_empty "value"
    [ "$status" -eq 0 ]
}

@test "require_ado_credentials: fails under auto-approve when credentials missing" {
    unset ADO_PAT ADO_ORG_URL TF_VAR_ado_pat_value
    run require_ado_credentials
    [ "$status" -eq 1 ]
    [[ "$output" =~ ADO_PAT ]]
}

@test "require_ado_credentials: succeeds when ADO_PAT and ADO_ORG_URL set" {
    export ADO_PAT="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd"
    export ADO_ORG_URL="https://dev.azure.com/myorg"
    require_ado_credentials
    [ $? -eq 0 ]
    [ "${TF_VAR_ado_pat_value}" = "${ADO_PAT}" ]
    [ "${TF_VAR_ado_url}" = "https://dev.azure.com/myorg" ]
    [ "${TF_VAR_ado_org}" = "myorg" ]
}

@test "prepare_ado_pat_for_terraform: maps ADO environment variables to Terraform variables" {
    export ADO_PAT="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd"
    export ADO_ORG_URL="https://dev.azure.com/myorg/"
    prepare_ado_pat_for_terraform
    [ "${TF_VAR_ado_pat_value}" = "${ADO_PAT}" ]
    [ "${TF_VAR_ado_url}" = "https://dev.azure.com/myorg" ]
    [ "${TF_VAR_ado_org}" = "myorg" ]
}

@test "validate_update_ado_secret_prerequisites: no-op when update flag false" {
    export UPDATE_ADO_SECRET="false"
    unset ADO_PAT ADO_ORG_URL
    run validate_update_ado_secret_prerequisites
    [ "$status" -eq 0 ]
}

@test "report_deployment_failure: emits grep-friendly banner" {
    run report_deployment_failure "application" "base" "middleware"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== DEPLOYMENT_FAILED layer=application succeeded=base,middleware ===" ]]
}
