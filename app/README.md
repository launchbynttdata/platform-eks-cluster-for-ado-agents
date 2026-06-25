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

### Container structure tests

When a build context includes `container-structure-test.yaml` at its root (for example `ado-agent/container-structure-test.yaml`), `build-and-push-ecr.sh` runs [container-structure-test](https://github.com/GoogleContainerTools/container-structure-test) against a locally loaded image before the build completes. Install the CLI via mise (`container-structure-test` is pinned in `.tool-versions`).

For multi-arch pushes, structure tests run against the first `--platforms` value. That image is built once, tested, and pushed; any additional platforms are built separately and combined into the final manifest with `buildx imagetools`. CST is invoked with `--platform` matching the built image (required on Apple Silicon when testing non-arm64 images).

Agent deployments are managed by Helm via the [application layer](../docs/deployment/application-layer.md), not raw Kubernetes manifests in this directory.
