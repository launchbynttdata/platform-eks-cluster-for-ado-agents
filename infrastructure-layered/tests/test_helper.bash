# Shared BATS helpers for infrastructure-layered deploy.sh tests.

env_fixture_setup_file() {
    TEST_IAC_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

    if [[ ! -f "${TEST_IAC_DIR}/env.sample.hcl" ]]; then
        echo "Missing committed Terragrunt fixture: ${TEST_IAC_DIR}/env.sample.hcl" >&2
        return 1
    fi

    if [[ ! -f "${TEST_IAC_DIR}/env.hcl" ]]; then
        cp "${TEST_IAC_DIR}/env.sample.hcl" "${TEST_IAC_DIR}/env.hcl"
        export TEST_CREATED_ENV_HCL=1
    fi
}

env_fixture_teardown_file() {
    if [[ "${TEST_CREATED_ENV_HCL:-}" == "1" ]]; then
        rm -f "${TEST_IAC_DIR}/env.hcl"
        unset TEST_CREATED_ENV_HCL TEST_IAC_DIR
    fi
}
