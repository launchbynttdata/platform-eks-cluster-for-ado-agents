#!/usr/bin/env bats
# Integration tests for deploy.sh validation functions (Terragrunt-based)
#
# These tests verify the validation logic for the Terragrunt-based deploy.sh
# Run with: bats tests/test_validation.bats

setup() {
    export TF_STATE_BUCKET="test-bucket"
    export TF_STATE_REGION="us-west-2"
    export AWS_REGION="us-west-2"
    export AUTO_APPROVE="false"
    export DRY_RUN="true"
    export VERBOSE="false"
    
    # Store script directory for use in tests
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export TEST_SCRIPT_DIR="${SCRIPT_DIR_LOCAL}"
    export DEPLOY_LAYERS_DIR="${SCRIPT_DIR_LOCAL}"

    # shellcheck source=/dev/null
    source <(sed '/^if \[\[ "\${BASH_SOURCE\[0\]}" == "\${0}" \]\]; then/,$d' "${TEST_SCRIPT_DIR}/deploy.sh")
    export AUTO_APPROVE="false"
    export DRY_RUN="true"
    export VERBOSE="false"
}

teardown() {
    unset TEST_SCRIPT_DIR DEPLOY_LAYERS_DIR
}

# Test: Layer directory structure
@test "base layer directory exists" {
    [ -d "${TEST_SCRIPT_DIR}/base" ]
}

@test "middleware layer directory exists" {
    [ -d "${TEST_SCRIPT_DIR}/middleware" ]
}

@test "networking layer directory exists" {
    [ -d "${TEST_SCRIPT_DIR}/networking" ]
}

@test "application layer directory exists" {
    [ -d "${TEST_SCRIPT_DIR}/application" ]
}

@test "base layer has terragrunt.hcl" {
    [ -f "${TEST_SCRIPT_DIR}/base/terragrunt.hcl" ]
}

@test "middleware layer has terragrunt.hcl" {
    [ -f "${TEST_SCRIPT_DIR}/middleware/terragrunt.hcl" ]
}

@test "networking layer has terragrunt.hcl" {
    [ -f "${TEST_SCRIPT_DIR}/networking/terragrunt.hcl" ]
}

@test "application layer has terragrunt.hcl" {
    [ -f "${TEST_SCRIPT_DIR}/application/terragrunt.hcl" ]
}

@test "networking layer has Terraform entrypoints" {
    [ -f "${TEST_SCRIPT_DIR}/networking/main.tf" ]
    [ -f "${TEST_SCRIPT_DIR}/networking/variables.tf" ]
    [ -f "${TEST_SCRIPT_DIR}/networking/remote_state.tf" ]
}

@test "root.hcl exists" {
    [ -f "${TEST_SCRIPT_DIR}/root.hcl" ]
}

@test "env.hcl configuration exists" {
    [ -f "${TEST_SCRIPT_DIR}/env.hcl" ]
}

@test "common.hcl configuration exists" {
    [ -f "${TEST_SCRIPT_DIR}/common.hcl" ]
}

@test "deploy_config_layer: fails early when base cluster_name output missing" {
    export DRY_RUN="false"
    get_terragrunt_output_raw() { :; }

    run deploy_config_layer "${BASE_LAYER_DIR}" "false"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Base layer output missing: cluster_name" ]]
}

@test "deploy_config_layer: fails when middleware outputs are missing" {
    export DRY_RUN="false"
    get_terragrunt_output_raw() {
        if [[ "$1:$2" == "base:cluster_name" ]]; then
            echo "demo-cluster"
            return 0
        fi
        return 0
    }

    run deploy_config_layer "${BASE_LAYER_DIR}" "false"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Middleware layer output missing: eso_role_arn" ]]
}

@test "deploy_config_layer: checks application secret output when update requested" {
    export DRY_RUN="false"
    get_terragrunt_output_raw() {
        case "$1:$2" in
            base:cluster_name) echo "demo-cluster" ;;
            middleware:eso_role_arn) echo "arn:aws:iam::123456789012:role/eso-role" ;;
            middleware:cluster_secret_store_name) echo "aws-secrets-manager" ;;
            middleware:eso_namespace) echo "external-secrets-system" ;;
            middleware:eso_service_account_name) echo "external-secrets" ;;
        esac
        return 0
    }
    get_terragrunt_output_json() { echo "{}"; }

    run deploy_config_layer "${BASE_LAYER_DIR}" "true"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Application layer output missing: ado_pat_secret.name" ]]
}

@test "report_deployment_failure: includes networking recovery guidance" {
    run report_deployment_failure "networking" "base"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Failed at: networking" ]]
    [[ "$output" =~ "Common networking layer issues" ]]
}
