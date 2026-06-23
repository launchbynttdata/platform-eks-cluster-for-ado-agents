# Networking Layer

The networking layer runs after the base layer and before middleware. It manages optional Kubernetes CNI components that require a live EKS API server.

## Responsibilities

- No-op in the default `vpc-cni` mode.
- Installs Cilium in `cilium-overlay` mode.
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

When `pod_networking_mode = "cilium-overlay"`, the layer installs Cilium into `kube-system` using Helm and cluster-pool IPAM. See [CNI_MODES.md](../reference/CNI_MODES.md) for configuration, constraints, and existing-cluster conversion notes.

## Validation

```bash
cd infrastructure-layered
./deploy.sh --layer networking validate
./deploy.sh --layer networking plan
```

The layer should validate and plan cleanly in both modes:

- `vpc-cni`: no Helm resources are created.
- `cilium-overlay`: the Cilium Helm release is planned.
