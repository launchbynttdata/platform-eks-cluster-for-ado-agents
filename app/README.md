# Agent Application Images

Docker build contexts for Azure DevOps agent container images deployed by the platform.

## Directories

| Directory | Purpose |
|-----------|---------|
| `ado-agent/` | General-purpose build agent image |
| `ado-agent-iac/` | Infrastructure-as-code focused agent image |

## Build and push

Use the helper script to build and push to ECR:

```bash
./build-and-push-ecr.sh -r ado-agent -t v1.0.0 --context app/ado-agent
./build-and-push-ecr.sh -r ado-agent-iac -t v1.0.0 --context app/ado-agent-iac
```

For multi-arch builds, see [OCI image cross-build guide](../docs/guides/OCI_IMAGE_CROSS_BUILD_README.md).

Agent deployments are managed by Helm via the [application layer](../docs/deployment/application-layer.md), not raw Kubernetes manifests in this directory.
