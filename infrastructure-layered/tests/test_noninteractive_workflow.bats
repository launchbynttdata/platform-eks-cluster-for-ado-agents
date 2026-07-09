#!/usr/bin/env bats
# End-to-end workflow tests: --auto-approve must never block on stdin.

setup_file() {
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export SCRIPT_DIR
    export ADO_AGENT_AUTH_MODE="pat"
    if [[ ! -f "${SCRIPT_DIR}/env.hcl" ]]; then
        cp "${SCRIPT_DIR}/env.sample.hcl" "${SCRIPT_DIR}/env.hcl"
        export CREATED_ENV_HCL=1
    fi
}

teardown_file() {
    if [[ "${CREATED_ENV_HCL:-}" == "1" ]]; then
        rm -f "${SCRIPT_DIR}/env.hcl"
    fi
    unset ADO_AGENT_AUTH_MODE
}

run_deploy_timeout() {
    local timeout_seconds="${1}"
    shift
    local cmd="cd '${SCRIPT_DIR}' && $*"

    if command -v timeout >/dev/null 2>&1; then
        run timeout "${timeout_seconds}" bash -c "${cmd}" </dev/null
    elif command -v gtimeout >/dev/null 2>&1; then
        run gtimeout "${timeout_seconds}" bash -c "${cmd}" </dev/null
    else
        run bash -c "${cmd}" </dev/null
    fi
}

@test "auto-approve update-ado-secret: fails fast when ADO credentials missing" {
    run_deploy_timeout 5 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ./deploy.sh deploy --auto-approve --update-ado-secret --dry-run 2>&1"
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
    [[ "$output" =~ ADO_PAT ]]
    [[ "$output" =~ ADO_ORG_URL ]]
    [[ ! "$output" =~ "Enter Azure DevOps" ]]
}

@test "auto-approve update-ado-secret: fails fast when ADO_ORG_URL missing" {
    run_deploy_timeout 5 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ADO_PAT='abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd' ./deploy.sh deploy --auto-approve --update-ado-secret --dry-run 2>&1"
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
    [[ "$output" =~ ADO_ORG_URL ]]
}

@test "auto-approve update-ado-secret: fails fast when ADO_PAT is whitespace" {
    run_deploy_timeout 5 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ADO_PAT='   ' ADO_ORG_URL='https://dev.azure.com/myorg' ./deploy.sh deploy --auto-approve --update-ado-secret --dry-run 2>&1"
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
    [[ "$output" =~ ADO_PAT ]]
}

@test "auto-approve update-ado-secret: succeeds dry-run when credentials set" {
    run_deploy_timeout 10 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ADO_PAT='abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd' ADO_ORG_URL='https://dev.azure.com/myorg' ./deploy.sh deploy --auto-approve --update-ado-secret --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Enter Azure DevOps" ]]
}

@test "auto-approve: config layer dry-run does not hang without credentials when skip-ado-secret" {
    run_deploy_timeout 10 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ./deploy.sh deploy --layer config --auto-approve --skip-ado-secret --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [ "$status" -ne 124 ]
    [[ "$output" =~ "DRY-RUN" ]]
}

@test "auto-approve: config layer dry-run fails fast without credentials when update-ado-secret" {
    run_deploy_timeout 5 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ./deploy.sh deploy --layer config --auto-approve --update-ado-secret --dry-run 2>&1"
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
    [[ "$output" =~ ADO_PAT ]]
}

@test "auto-approve: application layer dry-run fails fast without credentials when update-ado-secret" {
    run_deploy_timeout 5 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ./deploy.sh deploy --layer application --auto-approve --update-ado-secret --dry-run 2>&1"
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
    [[ "$output" =~ ADO_PAT ]]
}

@test "auto-approve: deploy dry-run without update-ado-secret does not require ADO vars" {
    run_deploy_timeout 10 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ./deploy.sh deploy --auto-approve --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Enter Azure DevOps" ]]
}

@test "auto-approve: full deploy does not prompt for config layer" {
    run_deploy_timeout 10 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ./deploy.sh deploy --auto-approve --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Deploy config layer" ]]
    [[ "$output" =~ "Skipping config layer" ]]
}

@test "auto-approve: --layer all is accepted" {
    run_deploy_timeout 10 "cd '${SCRIPT_DIR}' && TF_STATE_BUCKET=test-bucket ./deploy.sh deploy --layer all --auto-approve --dry-run 2>&1"
    [ "$status" -eq 0 ]
}
