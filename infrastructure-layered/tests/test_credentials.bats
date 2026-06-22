#!/usr/bin/env bats
# Unit tests for ADO credential validation and helper functions.

setup() {
    export TF_STATE_BUCKET="test-bucket"
    export AUTO_APPROVE="true"
    export DRY_RUN="false"
    export VERBOSE="false"
    export UPDATE_ADO_SECRET="true"

    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    TEST_DEPLOY_SH="${BATS_TMPDIR}/deploy.sh"
    sed '/^main /,$d' "${SCRIPT_DIR}/deploy.sh" > "${TEST_DEPLOY_SH}"
    # shellcheck source=/dev/null
    source "${TEST_DEPLOY_SH}"
    export AUTO_APPROVE="true"
    export UPDATE_ADO_SECRET="true"
    init_log_colors
}

teardown() {
    rm -f "${BATS_TMPDIR}/deploy.sh"
    unset ADO_PAT ADO_ORG_URL TF_VAR_ado_pat_value
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
