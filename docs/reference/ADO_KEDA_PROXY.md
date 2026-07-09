# ADO KEDA Proxy

The ADO KEDA proxy lets the platform keep the official KEDA image while using
service principal credentials for Azure DevOps queue polling.

Official KEDA currently supports Azure Pipelines PAT authentication and Azure
Workload Identity authentication. This proxy keeps KEDA on its PAT-shaped
configuration path, but KEDA talks only to an in-cluster service. The proxy
then obtains an Azure DevOps bearer token with the configured service principal
and forwards only the queue-inspection requests that KEDA needs.

## Image Release

The proxy is released from this repository with tags matching:

```text
ado-keda-proxy/vX.Y.Z
```

The release workflow publishes a public multi-architecture image to:

```text
ghcr.io/launchbynttdata/platform-eks-cluster-for-ado-agents/ado-keda-proxy
```

For a tag such as `ado-keda-proxy/v1.2.3`, the workflow publishes:

- `v1.2.3`
- `1.2.3`
- `1.2`
- `1`
- `sha-<shortsha>`

Production deployments should prefer digest pinning with
`ado_keda_proxy.image_digest = "sha256:..."`.

After the first release publish, confirm the GHCR package visibility is public
in the repository package settings if the organization default did not make the
linked package public automatically.

## Runtime Contract

The proxy requires:

- `ADO_ORG_URL`, for example `https://dev.azure.com/my-org`
- `AZP_CLIENTID`
- `AZP_CLIENTSECRET`
- `AZP_TENANTID`

The Helm chart sources those values from the same SPN Kubernetes secret used by
the ADO agent containers. That Kubernetes secret is synced by External Secrets
Operator from an externally managed AWS Secrets Manager secret containing
`ClientId`, `ClientSecret`, and `TenantId`.

## Security Boundary

The proxy is intentionally narrow:

- only `GET /_apis/distributedtask/pools` is allowed,
- only `GET /_apis/distributedtask/pools/<poolID>/jobrequests` is allowed,
- arbitrary hosts, paths, methods, and query keys are rejected,
- inbound authorization headers are ignored,
- only the service-principal bearer token is sent upstream,
- secret values are not logged or returned in errors.

The dummy `personalAccessToken` Secret rendered in SPN mode is not a credential.
It exists only because official KEDA requires that auth parameter when it is not
using Azure Workload Identity.
