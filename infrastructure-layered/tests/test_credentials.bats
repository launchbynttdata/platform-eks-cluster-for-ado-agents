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
    export ADO_AGENT_AUTH_MODE="pat"

    # shellcheck source=/dev/null
    source <(sed '/^if \[\[ "\${BASH_SOURCE\[0\]}" == "\${0}" \]\]; then/,$d' "${SCRIPT_DIR}/deploy.sh")
    init_log_colors
}

teardown() {
    unset ADO_PAT ADO_ORG_URL ADO_AGENT_AUTH_MODE TF_VAR_ado_agent_auth_mode TF_VAR_ado_pat_value TF_VAR_ado_url TF_VAR_ado_org DEPLOY_LAYERS_DIR
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

@test "require_ado_credentials: rejects unsupported ADO_ORG_URL shape" {
    export ADO_PAT="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd"
    export ADO_ORG_URL="https://myorg.visualstudio.com"
    run require_ado_credentials
    [ "$status" -eq 1 ]
    [[ "$output" =~ "https://dev.azure.com/<org>" ]]
}

@test "prepare_ado_pat_for_terraform: maps ADO environment variables to Terraform variables" {
    export ADO_PAT="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd"
    export ADO_ORG_URL="https://dev.azure.com/myorg/"
    prepare_ado_pat_for_terraform
    [ "${TF_VAR_ado_pat_value}" = "${ADO_PAT}" ]
    [ "${TF_VAR_ado_url}" = "https://dev.azure.com/myorg" ]
    [ "${TF_VAR_ado_org}" = "myorg" ]
}

@test "prepare_ado_pat_for_terraform: leaves invalid ADO org derivation unset" {
    export ADO_PAT="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd"
    export ADO_ORG_URL="https://myorg.visualstudio.com"
    prepare_ado_pat_for_terraform
    [ "${TF_VAR_ado_pat_value}" = "${ADO_PAT}" ]
    [ "${TF_VAR_ado_url}" = "${ADO_ORG_URL}" ]
    [ -z "${TF_VAR_ado_org:-}" ]
}

@test "prepare_ado_pat_for_terraform: skips PAT export in SPN mode" {
    export ADO_AGENT_AUTH_MODE="SPN"
    export ADO_PAT="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd"
    export ADO_ORG_URL="https://dev.azure.com/myorg/"
    export TF_VAR_ado_pat_value="old-value"
    prepare_ado_pat_for_terraform
    [ -z "${TF_VAR_ado_pat_value:-}" ]
}

@test "configured_ado_auth_mode: fails closed when mode cannot be determined" {
    unset ADO_AGENT_AUTH_MODE TF_VAR_ado_agent_auth_mode
    export DEPLOY_LAYERS_DIR="${BATS_TEST_TMPDIR}/missing-env"
    run configured_ado_auth_mode
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unable to determine ADO auth mode" ]]
}

@test "validate_update_ado_secret_prerequisites: no-op when update flag false" {
    export UPDATE_ADO_SECRET="false"
    unset ADO_PAT ADO_ORG_URL
    run validate_update_ado_secret_prerequisites
    [ "$status" -eq 0 ]
}

@test "validate_update_ado_secret_prerequisites: rejects PAT update in SPN mode" {
    export UPDATE_ADO_SECRET="true"
    export ADO_AGENT_AUTH_MODE="spn"
    run validate_update_ado_secret_prerequisites
    [ "$status" -eq 1 ]
    [[ "$output" =~ "only valid for PAT mode" ]]
}

@test "report_deployment_failure: emits grep-friendly banner" {
    run report_deployment_failure "application" "base" "middleware"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== DEPLOYMENT_FAILED layer=application succeeded=base,middleware ===" ]]
}
