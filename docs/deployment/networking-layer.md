# Networking Layer

The networking layer runs after the base layer and before middleware. It validates optional Kubernetes CNI configuration after the base layer has created the cluster.

## Responsibilities

- No-op in the default `vpc-cni` mode.
- No-op in `cilium-overlay` mode after validating the base layer mode.
- Validates that the requested networking mode matches the base layer output.

## Deploy

```bash
cd infrastructure-layered
./deploy.sh --layer networking deploy
```

For all-layer deploys, `deploy.sh` runs:

```text
base -> networking -> middleware -> application
```

## Cilium Overlay

When `pod_networking_mode = "cilium-overlay"`, the base layer bootstraps Cilium into `kube-system` using Helm and cluster-pool IPAM before EC2 managed node groups are created. This ordering prevents managed node group creation from failing with `cni plugin not initialized`. See [CNI_MODES.md](../reference/CNI_MODES.md) for configuration, constraints, and existing-cluster conversion notes.

## Validation

```bash
cd infrastructure-layered
./deploy.sh --layer networking validate
./deploy.sh --layer networking plan
```

The layer should validate and plan cleanly in both modes:

- `vpc-cni`: no Helm resources are created.
- `cilium-overlay`: no additional resources are created; the layer validates base/networking mode consistency.
