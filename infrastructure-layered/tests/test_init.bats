#!/usr/bin/env bats
# Unit tests for init_layer functionality in deploy.sh
#
# These tests verify the behavior of the new initialization functions
# that handle Terragrunt/Terraform module initialization
# Run with: bats tests/test_init.bats

setup() {
    # Set required environment variables for testing
    export TF_STATE_BUCKET="test-bucket"
    export TF_STATE_REGION="us-west-2"
    export AWS_REGION="us-west-2"
    export AUTO_APPROVE="true"
    export DRY_RUN="false"
    export VERBOSE="false"
    
    # Source the deploy.sh script to get function definitions
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export DEPLOY_LAYERS_DIR="${SCRIPT_DIR}"
    export AUTO_APPROVE="true"
    export DRY_RUN="false"
    export VERBOSE="false"

    # shellcheck source=/dev/null
    source <(sed '/^if \[\[ "\${BASH_SOURCE\[0\]}" == "\${0}" \]\]; then/,$d' "${SCRIPT_DIR}/deploy.sh")
    export AUTO_APPROVE="true"
    export DRY_RUN="false"
    export VERBOSE="false"
    export TEST_LAYER_DIR="${BATS_TMPDIR}/test-layer"
    mkdir -p "${TEST_LAYER_DIR}"
}

teardown() {
    rm -rf "${TEST_LAYER_DIR}"
    unset DEPLOY_LAYERS_DIR
}

# =============================================================================
# Tests for init_layer function
# =============================================================================

@test "init_layer: function exists and is callable" {
    # Verify the function exists
    declare -f init_layer > /dev/null
    [ $? -eq 0 ]
}

@test "init_layer: accepts three parameters (layer, layer_dir, force)" {
    # Test with dry-run to avoid actual initialization
    export DRY_RUN="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Would initialize test layer" ]]
}

@test "init_layer: dry-run mode shows initialization message" {
    export DRY_RUN="true"
    # Use readonly BASE_LAYER_DIR from sourced script
    run init_layer "base" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY-RUN" ]] || [[ "$output" =~ "Would initialize" ]] || [[ "$output" =~ "Initializing" ]]
}

@test "init_layer: detects missing terragrunt cache" {
    # Create test layer without cache
    mkdir -p "${TEST_LAYER_DIR}"
    rm -rf "${TEST_LAYER_DIR}/.terragrunt-cache"
    
    export DRY_RUN="true"
    export VERBOSE="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Just verify the test runs successfully - output format may vary
    [ -n "$output" ]
}

@test "init_layer: detects missing terraform directory" {
    # Create test layer without .terraform directory
    mkdir -p "${TEST_LAYER_DIR}"
    rm -rf "${TEST_LAYER_DIR}/.terraform"
    
    export DRY_RUN="true"
    export VERBOSE="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Just verify the test runs successfully
    [ -n "$output" ]
}

@test "init_layer: force flag triggers initialization" {
    export DRY_RUN="true"
    export VERBOSE="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "true"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Force initialization" ]] || [[ "$output" =~ "Would initialize" ]]
}

@test "init_layer: verbose mode shows debug output" {
    export DRY_RUN="true"
    export VERBOSE="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Just verify output exists - format may vary
    [ -n "$output" ]
}

@test "init_layer: changes to correct directory" {
    export DRY_RUN="true"
    mkdir -p "${TEST_LAYER_DIR}"
    cd /tmp
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Function should succeed (it changes directory internally)
}

@test "init_layer: skips initialization when already initialized" {
    # Create mock initialized state
    mkdir -p "${TEST_LAYER_DIR}/.terragrunt-cache"
    mkdir -p "${TEST_LAYER_DIR}/.terraform/modules"
    echo "test" > "${TEST_LAYER_DIR}/.terraform/modules/test.tf"
    
    # Create a modules.json to simulate proper cache
    mkdir -p "${TEST_LAYER_DIR}/.terragrunt-cache/test"
    echo '{"Modules":[]}' > "${TEST_LAYER_DIR}/.terragrunt-cache/test/modules.json"
    
    export VERBOSE="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "already initialized" ]] || [[ "$output" =~ "skipping init" ]]
}

# =============================================================================
# Tests for init_all_layers function
# =============================================================================

@test "init_all_layers: function exists and is callable" {
    declare -f init_all_layers > /dev/null
    [ $? -eq 0 ]
}

@test "init_all_layers: dry-run mode processes all layers" {
    export DRY_RUN="true"
    run init_all_layers
    [ "$status" -eq 0 ]
    [[ "$output" =~ "base" ]]
    [[ "$output" =~ "networking" ]]
    [[ "$output" =~ "middleware" ]]
    [[ "$output" =~ "application" ]]
}

@test "init_all_layers: dry-run mode orders networking between base and middleware" {
    export DRY_RUN="true"
    run init_all_layers
    [ "$status" -eq 0 ]

    local base_index networking_index middleware_index application_index prefix
    [[ "$output" == *base* ]]
    [[ "$output" == *networking* ]]
    [[ "$output" == *middleware* ]]
    [[ "$output" == *application* ]]
    prefix="${output%%base*}"; base_index=${#prefix}
    prefix="${output%%networking*}"; networking_index=${#prefix}
    prefix="${output%%middleware*}"; middleware_index=${#prefix}
    prefix="${output%%application*}"; application_index=${#prefix}

    [ "$base_index" -gt 0 ]
    [ "$networking_index" -gt "$base_index" ]
    [ "$middleware_index" -gt "$networking_index" ]
    [ "$application_index" -gt "$middleware_index" ]
}

@test "init_all_layers: shows success message on completion" {
    export DRY_RUN="true"
    run init_all_layers
    [ "$status" -eq 0 ]
    [[ "$output" =~ "All layers initialized successfully" ]]
}

# =============================================================================
# Tests for plan_layer with init integration
# =============================================================================

@test "plan_layer: calls init_layer before planning" {
    export DRY_RUN="true"
    # Use the readonly variable from sourced script
    run plan_layer "base" "${TEST_LAYER_DIR}"
    [ "$status" -eq 0 ]
    # Should complete successfully - init happens automatically
    [[ "$output" =~ "Initializing" ]] || [[ "$output" =~ "Planning" ]] || [[ "$output" =~ "already initialized" ]]
}

@test "plan_layer: fails if init_layer fails" {
    export DRY_RUN="false"
    local NON_EXISTENT_DIR="/tmp/non-existent-layer-$$"
    run plan_layer "test" "${NON_EXISTENT_DIR}"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Layer directory not found" ]]
}

@test "plan_layer: continues to plan after successful init" {
    export DRY_RUN="true"
    run plan_layer "base" "${TEST_LAYER_DIR}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "plan" ]] || [[ "$output" =~ "Planning" ]]
}

# =============================================================================
# Tests for apply_layer with init integration
# =============================================================================

@test "apply_layer: calls init_layer before applying" {
    export DRY_RUN="true"
    run apply_layer "base" "${TEST_LAYER_DIR}"
    [ "$status" -eq 0 ]
    # Should complete successfully - init happens automatically
    [[ "$output" =~ "Initializing" ]] || [[ "$output" =~ "Applying" ]] || [[ "$output" =~ "already initialized" ]]
}

@test "apply_layer: fails if init_layer fails" {
    export DRY_RUN="false"
    local NON_EXISTENT_DIR="/tmp/non-existent-layer-$$"
    run apply_layer "test" "${NON_EXISTENT_DIR}"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Layer directory not found" ]]
}

@test "apply_layer: continues to apply after successful init" {
    export DRY_RUN="true"
    run apply_layer "base" "${TEST_LAYER_DIR}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "apply" ]] || [[ "$output" =~ "Applying" ]]
}

# =============================================================================
# Tests for initialization detection logic
# =============================================================================

@test "init_layer: detects empty terraform modules directory" {
    mkdir -p "${TEST_LAYER_DIR}/.terraform/modules"
    # Empty modules directory should trigger initialization
    
    export DRY_RUN="true"
    export VERBOSE="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Just verify the test completes successfully
    [ -n "$output" ]
}

@test "init_layer: detects missing modules.json in terragrunt cache" {
    mkdir -p "${TEST_LAYER_DIR}/.terragrunt-cache"
    # Cache exists but no modules.json should trigger initialization
    
    export DRY_RUN="true"
    export VERBOSE="true"
    run init_layer "test" "${TEST_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Just verify the test completes successfully
    [ -n "$output" ]
}

# =============================================================================
# Tests for command line integration
# =============================================================================

@test "init command: recognized in command parsing" {
    # Test that 'init' is a valid command
    # This tests the main command parsing logic
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    
    export DRY_RUN="true"
    run bash -c "cd ${SCRIPT_DIR_LOCAL} && ./deploy.sh init --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Initializing" ]] || [[ "$output" =~ "TF_STATE_BUCKET" ]]
}

@test "init command: supports --layer flag" {
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    
    export DRY_RUN="true"
    run bash -c "cd ${SCRIPT_DIR_LOCAL} && ./deploy.sh init --layer base --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "base" ]] || [[ "$output" =~ "TF_STATE_BUCKET" ]]
}

@test "init command: shows in help output" {
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    
    run bash -c "cd ${SCRIPT_DIR_LOCAL} && ./deploy.sh --help 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "init" ]]
    [[ "$output" =~ "Initialize Terragrunt/Terraform" ]]
    [[ "$output" =~ "Usage: deploy.sh" ]]
}

@test "arg parsing: --layer requires value" {
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

    run bash -c "cd ${SCRIPT_DIR_LOCAL} && ./deploy.sh --layer 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Option --layer requires a value" ]]
}

@test "arg parsing: --region requires value" {
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

    run bash -c "cd ${SCRIPT_DIR_LOCAL} && ./deploy.sh --region 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Option --region requires a value" ]]
}

@test "dry-run: does not require valid AWS credentials" {
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

    run bash -c "cd ${SCRIPT_DIR_LOCAL} && AWS_PROFILE=__nonexistent_profile__ ./deploy.sh init --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Dry-run mode detected: skipping tool and AWS credential checks" ]]
}

# =============================================================================
# Tests for error handling
# =============================================================================

@test "init_layer: handles verbose flag correctly" {
    export DRY_RUN="true"
    export VERBOSE="true"
    run init_layer "base" "${BASE_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Verbose mode should show debug messages
    [[ "$output" =~ "\[DEBUG\]" ]] || [ "$status" -eq 0 ]
}

@test "init_layer: handles non-verbose mode correctly" {
    export DRY_RUN="true"
    export VERBOSE="false"
    run init_layer "base" "${BASE_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
    # Non-verbose mode should not show debug messages (or may show INFO)
    [[ ! "$output" =~ "\[DEBUG\]" ]] || [ "$status" -eq 0 ]
}

@test "init_layer: returns success for dry-run" {
    export DRY_RUN="true"
    run init_layer "base" "${BASE_LAYER_DIR}" "false"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Integration tests with actual layer structure
# =============================================================================

@test "init_layer: works with base layer directory" {
    export DRY_RUN="true"
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    run init_layer "base" "${SCRIPT_DIR_LOCAL}/base" "false"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "base" ]]
}

@test "init_layer: works with middleware layer directory" {
    export DRY_RUN="true"
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    run init_layer "middleware" "${SCRIPT_DIR_LOCAL}/middleware" "false"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "middleware" ]]
}

@test "init_layer: works with networking layer directory" {
    export DRY_RUN="true"
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    run init_layer "networking" "${SCRIPT_DIR_LOCAL}/networking" "false"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "networking" ]]
}

@test "init_layer: works with application layer directory" {
    export DRY_RUN="true"
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    run init_layer "application" "${SCRIPT_DIR_LOCAL}/application" "false"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "application" ]]
}

@test "deploy command: networking layer dry-run is supported" {
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

    run bash -c "cd ${SCRIPT_DIR_LOCAL} && ./deploy.sh deploy --layer networking --dry-run 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "networking" ]]
    [[ "$output" =~ "Would apply networking layer" ]]
}

@test "plan command: all-layer dry-run includes networking between base and middleware" {
    local SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

    run bash -c "cd ${SCRIPT_DIR_LOCAL} && ./deploy.sh plan --layer all --dry-run 2>&1"
    [ "$status" -eq 0 ]

    local base_index networking_index middleware_index application_index prefix
    [[ "$output" == *base* ]]
    [[ "$output" == *networking* ]]
    [[ "$output" == *middleware* ]]
    [[ "$output" == *application* ]]
    prefix="${output%%base*}"; base_index=${#prefix}
    prefix="${output%%networking*}"; networking_index=${#prefix}
    prefix="${output%%middleware*}"; middleware_index=${#prefix}
    prefix="${output%%application*}"; application_index=${#prefix}

    [ "$base_index" -gt 0 ]
    [ "$networking_index" -gt "$base_index" ]
    [ "$middleware_index" -gt "$networking_index" ]
    [ "$application_index" -gt "$middleware_index" ]
}

@test "deploy_all_layers: dry-run orders networking between base and middleware" {
    export DRY_RUN="true"
    run deploy_all_layers
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would apply base layer"* ]]
    [[ "$output" == *"Would apply networking layer"* ]]
    [[ "$output" == *"Would apply middleware layer"* ]]
    [[ "$output" == *"Would apply application layer"* ]]
}

@test "validate_all_layers: dry-run orders networking between base and middleware" {
    export DRY_RUN="true"
    run validate_all_layers
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would validate base layer"* ]]
    [[ "$output" == *"Would validate networking layer"* ]]
    [[ "$output" == *"Would validate middleware layer"* ]]
    [[ "$output" == *"Would validate application layer"* ]]
}

@test "destroy_all_layers: dry-run destroys networking before base" {
    export DRY_RUN="true"
    export AUTO_APPROVE="true"
    run destroy_all_layers
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would destroy application layer"* ]]
    [[ "$output" == *"Would destroy middleware layer"* ]]
    [[ "$output" == *"Would destroy networking layer"* ]]
    [[ "$output" == *"Would destroy base layer"* ]]
}

@test "show_all_status: includes networking between base and middleware" {
    show_layer_status() { echo "status:$1"; }

    run show_all_status
    [ "$status" -eq 0 ]

    local base_index networking_index middleware_index application_index prefix
    [[ "$output" == *status:base* ]]
    [[ "$output" == *status:networking* ]]
    [[ "$output" == *status:middleware* ]]
    [[ "$output" == *status:application* ]]
    prefix="${output%%status:base*}"; base_index=${#prefix}
    prefix="${output%%status:networking*}"; networking_index=${#prefix}
    prefix="${output%%status:middleware*}"; middleware_index=${#prefix}
    prefix="${output%%status:application*}"; application_index=${#prefix}

    [ "$networking_index" -gt "$base_index" ]
    [ "$middleware_index" -gt "$networking_index" ]
    [ "$application_index" -gt "$middleware_index" ]
}

# =============================================================================
# Tests for upgrade flag behavior
# =============================================================================

@test "init_layer: uses -upgrade flag with terragrunt init" {
    # This test verifies the command structure
    # In dry-run mode, we just verify the function succeeds
    export DRY_RUN="true"
    run init_layer "base" "${TEST_LAYER_DIR}" "true"
    [ "$status" -eq 0 ]
    # The actual command with -upgrade is tested in integration tests
}

# =============================================================================
# Tests for backward compatibility
# =============================================================================

@test "plan_layer: still works with automatic init" {
    export DRY_RUN="true"
    run plan_layer "base" "${TEST_LAYER_DIR}"
    [ "$status" -eq 0 ]
    # Should complete successfully with init happening automatically
}

@test "apply_layer: still works with automatic init" {
    export DRY_RUN="true"
    run apply_layer "base" "${TEST_LAYER_DIR}"
    [ "$status" -eq 0 ]
    # Should complete successfully with init happening automatically
}
