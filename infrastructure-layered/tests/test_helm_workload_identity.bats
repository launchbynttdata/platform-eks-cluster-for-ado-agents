#!/usr/bin/env bats
# Helm rendering tests for ADO agent authentication modes.

setup() {
    CHART_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../helm/ado-agent-cluster" && pwd)"
}

@test "helm template keeps PAT auth as the default" {
    run helm template ado-agents "${CHART_DIR}"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "personalAccessTokenFromEnv: \"AZP_TOKEN\"" ]]
    [[ "$output" =~ "secretTargetRef:" ]]
    [[ "$output" =~ "parameter: personalAccessToken" ]]
    [[ "$output" =~ "name: AZP_TOKEN" ]]
}

@test "helm template renders Azure Workload Identity auth for KEDA and agent pods" {
    values_file="${BATS_TMPDIR}/azure-workload-values.yaml"
    cat > "${values_file}" <<'YAML'
agentPools:
  dev-build:
    enabled: true
    name: dev-build
    ado:
      poolName: ADO-Pool
      secretName: ado-pat
    image:
      repository: repo.example.com/ado-agent
      tag: latest
      pullPolicy: IfNotPresent
    serviceAccount:
      name: ado-agent
      roleArn: arn:aws:iam::123456789012:role/ado-agent
    autoscaling:
      enabled: true
      minReplicas: 0
      maxReplicas: 2
      targetPipelinesQueueLength: 1
    kedaAuth:
      mode: azure_workload
      clientId: keda-client-id
      tenantId: tenant-id
    agentAuth:
      mode: azure_workload
      clientId: agent-client-id
      tenantId: tenant-id
    resources: {}
    tolerations: []
    nodeSelector: {}
    affinity: {}
  iac:
    enabled: false
YAML

    run helm template ado-agents "${CHART_DIR}" -f "${values_file}"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "provider: azure-workload" ]]
    [[ "$output" =~ "identityId: \"keda-client-id\"" ]]
    [[ "$output" =~ "identityTenantId: \"tenant-id\"" ]]
    [[ "$output" =~ "azure.workload.identity/client-id: \"agent-client-id\"" ]]
    [[ "$output" =~ "azure.workload.identity/use: \"true\"" ]]
    [[ "$output" =~ "name: AZP_AUTH_MODE" ]]
    [[ "$output" =~ "value: \"azure_workload\"" ]]
    [[ ! "$output" =~ "personalAccessTokenFromEnv" ]]
    [[ ! "$output" =~ "name: AZP_TOKEN" ]]
}
