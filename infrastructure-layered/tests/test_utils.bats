#!/usr/bin/env bats
# Unit tests for deploy.sh utility functions
#
# These tests verify the behavior of helper functions in deploy.sh
# Run with: bats tests/test_utils.bats

# Load the functions from deploy.sh
# We need to source it in a way that doesn't execute the main() function
setup() {
    # Set required environment variables for testing
    export TF_STATE_BUCKET="test-bucket"
    export TF_STATE_REGION="us-west-2"
    export AWS_REGION="us-west-2"
    export LOG_LEVEL="ERROR"  # Suppress output during tests
    export DRY_RUN="false"
    export VAR_FILE=""  # Initialize to empty string to avoid unbound variable errors
    
    # Source the deploy.sh script to get function definitions
    # We'll need to create a test helper that sources only functions
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    
    # Create a temporary version that doesn't call main
    TEST_DEPLOY_SH="${BATS_TMPDIR}/deploy.sh"
    sed '/^main /,$d' "${SCRIPT_DIR}/deploy.sh" > "${TEST_DEPLOY_SH}"
    
    # Source the functions
    source "${TEST_DEPLOY_SH}"
}

teardown() {
    # Clean up
    rm -f "${BATS_TMPDIR}/deploy.sh"
}

# Test: version_compare function
# Returns 0 if version1 >= version2, 1 if version1 < version2
@test "version_compare: equal versions return 0" {
    run version_compare "1.5.0" "1.5.0"
    [ "$status" -eq 0 ]
}

@test "version_compare: first version greater returns 0" {
    run version_compare "1.6.0" "1.5.0"
    [ "$status" -eq 0 ]
}

@test "version_compare: first version less returns 1" {
    run version_compare "1.4.0" "1.5.0"
    [ "$status" -eq 1 ]
}

@test "version_compare: handles patch versions greater" {
    run version_compare "1.5.1" "1.5.0"
    [ "$status" -eq 0 ]
}

@test "version_compare: handles patch versions less" {
    run version_compare "1.5.0" "1.5.1"
    [ "$status" -eq 1 ]
}

# Test: validate_layer_name function
@test "validate_layer_name: accepts valid layer 'base'" {
    run validate_layer_name "base"
    [ "$status" -eq 0 ]
}

@test "validate_layer_name: accepts valid layer 'middleware'" {
    run validate_layer_name "middleware"
    [ "$status" -eq 0 ]
}

@test "validate_layer_name: accepts valid layer 'application'" {
    run validate_layer_name "application"
    [ "$status" -eq 0 ]
}

@test "validate_layer_name: accepts valid layer 'config'" {
    run validate_layer_name "config"
    [ "$status" -eq 0 ]
}

@test "validate_layer_name: rejects invalid layer name" {
    run validate_layer_name "invalid-layer"
    [ "$status" -ne 0 ]
}

# Test: get_layer_directory function
@test "get_layer_directory: returns correct path for base" {
    run get_layer_directory "base"
    [ "$status" -eq 0 ]
    [[ "$output" =~ /base$ ]]
}

@test "get_layer_directory: returns correct path for middleware" {
    run get_layer_directory "middleware"
    [ "$status" -eq 0 ]
    [[ "$output" =~ /middleware$ ]]
}

@test "get_layer_directory: returns correct path for application" {
    run get_layer_directory "application"
    [ "$status" -eq 0 ]
    [[ "$output" =~ /application$ ]]
}

# Test: calculate_skipped_layers function
# This function takes a nameref to an array and prints output
@test "calculate_skipped_layers: no layers skipped when all processed" {
    local processed_layers=("base" "middleware" "application" "config")
    run calculate_skipped_layers processed_layers
    [ "$status" -eq 0 ]
    # When all layers are processed, no output is generated
    [ -z "$output" ]
}

@test "calculate_skipped_layers: shows skipped layers" {
    local processed_layers=("base")
    run calculate_skipped_layers processed_layers
    [ "$status" -eq 0 ]
    [[ "$output" =~ "middleware" ]]
    [[ "$output" =~ "application" ]]
    [[ "$output" =~ "config" ]]
}

# Test: get_terraform_var_args function
# This function always returns args (at minimum the aws_region)
@test "get_terraform_var_args: returns aws_region when no VAR_FILE set" {
    export VAR_FILE=""  # Empty string, not unset
    run get_terraform_var_args "base"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "-var=aws_region=" ]]
}

@test "get_terraform_var_args: includes var-file when VAR_FILE is set and exists" {
    export VAR_FILE="${BATS_TMPDIR}/test.tfvars"
    echo 'test_var = "value"' > "$VAR_FILE"
    
    run get_terraform_var_args "base"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "-var-file=" ]]
    
    rm -f "$VAR_FILE"
}

@test "get_terraform_var_args: fails when VAR_FILE doesn't exist" {
    export VAR_FILE="/nonexistent/file.tfvars"
    run get_terraform_var_args "base"
    [ "$status" -ne 0 ]
}
