#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    CHART_DIR="${REPO_ROOT}/infrastructure-layered/helm/ado-agent-cluster"
    RENDERED="${BATS_TMPDIR}/ado-agent-cluster-rendered.yaml"
}

render_spn_chart() {
    mise exec -- helm template ado-agents "${CHART_DIR}" \
        --namespace ado-agents \
        --set auth.mode=spn \
        --set auth.adoOrg=launch-dso \
        --set auth.adoURL=https://dev.azure.com/launch-dso \
        --set adoKedaProxy.enabled=true > "${RENDERED}"
}

@test "spn mode renders KEDA organizationURL as auth parameter" {
    run render_spn_chart
    [ "$status" -eq 0 ]

    grep -q 'organizationURL: "http://ado-keda-proxy.ado-agents.svc.cluster.local:8080/launch-dso"' "${RENDERED}"
    grep -q "parameter: organizationURL" "${RENDERED}"
    grep -q "key: organizationURL" "${RENDERED}"
    grep -q "parameter: personalAccessToken" "${RENDERED}"
    ! grep -q "organizationURLFromEnv" "${RENDERED}"
}

@test "pat mode keeps KEDA organizationURL and PAT resolved from worker environment" {
    run mise exec -- helm template ado-agents "${CHART_DIR}" \
        --namespace ado-agents \
        --set auth.mode=pat \
        --set auth.adoOrg=launch-dso \
        --set auth.adoURL=https://dev.azure.com/launch-dso
    [ "$status" -eq 0 ]

    [[ "$output" == *'organizationURLFromEnv: "AZP_URL"'* ]]
    [[ "$output" == *'personalAccessTokenFromEnv: "AZP_TOKEN"'* ]]
    [[ "$output" != *"parameter: organizationURL"* ]]
}
