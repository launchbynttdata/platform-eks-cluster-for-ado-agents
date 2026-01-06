#!/usr/bin/env bats
# Unit tests for deploy.sh utility functions (Terragrunt-based)
#
# These tests verify the behavior of helper functions in the Terragrunt-based deploy.sh
# Run with: bats tests/test_utils.bats

# Load the functions from deploy.sh
setup() {
    # Set required environment variables for testing
    export TF_STATE_BUCKET="test-bucket"
    export TF_STATE_REGION="us-west-2"
    export AWS_REGION="us-west-2"
    export AUTO_APPROVE="false"
    export DRY_RUN="false"
    export VERBOSE="false"
    
    # Source the deploy.sh script to get function definitions
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    
    # Create a temporary version that doesn't call main
    TEST_DEPLOY_SH="${BATS_TMPDIR}/deploy.sh"
    sed '/^main /,$d' "${SCRIPT_DIR}/deploy.sh" > "${TEST_DEPLOY_SH}"
    
    # Source the functions (this sets readonly variables BASE_LAYER_DIR, etc.)
    source "${TEST_DEPLOY_SH}"
}

teardown() {
    # Clean up
    rm -f "${BATS_TMPDIR}/deploy.sh"
}

# Test: get_layer_dir function
@test "get_layer_dir: returns correct path for base" {
    run get_layer_dir "base"
    [ "$status" -eq 0 ]
    [[ "$output" =~ /base$ ]]
}

@test "get_layer_dir: returns correct path for middleware" {
    run get_layer_dir "middleware"
    [ "$status" -eq 0 ]
    [[ "$output" =~ /middleware$ ]]
}

@test "get_layer_dir: returns correct path for application" {
    run get_layer_dir "application"
    [ "$status" -eq 0 ]
    [[ "$output" =~ /application$ ]]
}

@test "get_layer_dir: returns base path for config layer" {
    run get_layer_dir "config"
    [ "$status" -eq 0 ]
    [[ "$output" =~ /base$ ]]
}

@test "get_layer_dir: rejects invalid layer name" {
    run get_layer_dir "invalid-layer"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown layer" ]]
}

# Test: log functions
@test "log_info: outputs message" {
    run log_info "Test message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test message" ]]
}

@test "log_success: outputs success message" {
    run log_success "Success test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Success test" ]]
}

@test "log_warning: outputs warning message" {
    run log_warning "Warning test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning test" ]]
}

@test "log_error: outputs error message" {
    run log_error "Error test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Error test" ]]
}

@test "log_debug: outputs when verbose is true" {
    export VERBOSE="true"
    run log_debug "Debug test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Debug test" ]]
}

@test "log_debug: no output when verbose is false" {
    export VERBOSE="false"
    run log_debug "Debug test"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# NOTE: The following functions are not present in the current deploy.sh:
# - version_compare
# - validate_layer_name  
# - get_layer_directory
# - calculate_skipped_layers
# - get_terraform_var_args
# These tests have been removed. If these functions are added in the future,
# corresponding tests should be added.
