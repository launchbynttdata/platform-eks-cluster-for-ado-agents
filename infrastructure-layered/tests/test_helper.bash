# Shared BATS helpers for infrastructure-layered deploy.sh tests.

# Source deploy.sh function definitions without executing main.
# deploy.sh assigns default globals (for example AUTO_APPROVE=false); pass the
# suite's intended values as NAME=value pairs after layers_dir.
source_deploy_sh() {
    local layers_dir="$1"
    shift

    export DEPLOY_LAYERS_DIR="${layers_dir}"
    # shellcheck source=/dev/null
    source <(sed '/^if \[\[ "\${BASH_SOURCE\[0\]}" == "\${0}" \]\]; then/,$d' "${layers_dir}/deploy.sh")
    init_log_colors

    local assignment
    for assignment in "$@"; do
        if [[ "${assignment}" != *"="* ]]; then
            echo "source_deploy_sh: expected NAME=value, got: ${assignment}" >&2
            return 1
        fi
        export "${assignment?}"
    done
}

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

# Clear caller-exported ADO credential env vars before invoking deploy.sh in a subshell.
ado_credential_env_clear_snippet() {
    echo "unset ADO_PAT ADO_ORG_URL TF_VAR_ado_pat_value TF_VAR_ado_url TF_VAR_ado_org;"
}

ado_org_url_env_clear_snippet() {
    echo "unset ADO_ORG_URL TF_VAR_ado_url TF_VAR_ado_org;"
}
