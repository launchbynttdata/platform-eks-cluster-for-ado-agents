#!/usr/bin/env bats
# Integration tests for deploy.sh validation functions
#
# These tests verify the validation logic that checks deployment prerequisites
# Run with: bats tests/test_validation.bats

setup() {
    export TF_STATE_BUCKET="test-bucket"
    export TF_STATE_REGION="us-west-2"
    export AWS_REGION="us-west-2"
    export LOG_LEVEL="ERROR"
    export DRY_RUN="true"  # Use dry-run mode for validation tests
    
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    TEST_DEPLOY_SH="${BATS_TMPDIR}/deploy.sh"
    sed '/^main /,$d' "${SCRIPT_DIR}/deploy.sh" > "${TEST_DEPLOY_SH}"
    source "${TEST_DEPLOY_SH}"
}

teardown() {
    rm -f "${BATS_TMPDIR}/deploy.sh"
}

# Test: validate_layer_directory function
@test "validate_layer_directory: fails when directory doesn't exist" {
    run validate_layer_directory "/nonexistent/directory"
    [ "$status" -ne 0 ]
}

@test "validate_layer_directory: fails when main.tf missing" {
    local test_dir="${BATS_TMPDIR}/test_layer_no_main"
    mkdir -p "$test_dir"
    run validate_layer_directory "$test_dir"
    [ "$status" -ne 0 ]
    rm -rf "$test_dir"
}

@test "validate_layer_directory: succeeds with valid layer directory" {
    local test_dir="${BATS_TMPDIR}/test_layer_valid"
    mkdir -p "$test_dir"
    echo 'terraform {}' > "$test_dir/main.tf"
    echo 'variable "test" {}' > "$test_dir/variables.tf"
    echo 'output "test" { value = "test" }' > "$test_dir/outputs.tf"
    
    run validate_layer_directory "test" "$test_dir"
    [ "$status" -eq 0 ]
    
    rm -rf "$test_dir"
}

# Test: validate_layer_dependencies function
@test "validate_layer_dependencies: base layer has no dependencies" {
    # Base layer should always pass dependency check
    run validate_layer_dependencies "base"
    [ "$status" -eq 0 ]
}

@test "validate_layer_dependencies: config requires all other layers" {
    # Config layer requires base, middleware, and application
    # This test would need mocking of get_layer_status
    skip "Requires mocking of terraform state checks"
}
