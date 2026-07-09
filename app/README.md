# Agent Application Images

Docker build contexts for Azure DevOps agent container images deployed by the platform.

## Directories

| Directory | Purpose |
|-----------|---------|
| `ado-agent/` | General-purpose build agent image |
| `ado-agent-iac/` | Infrastructure-as-code focused agent image |
| `ado-keda-proxy/` | Go proxy that lets official KEDA poll Azure DevOps with SPN-backed bearer auth |

## Build and push

Use the helper script to build and push to ECR:

```bash
./build-and-push-ecr.sh -r ado-agent -t v1.0.0 --context app/ado-agent
./build-and-push-ecr.sh -r ado-agent-iac -t v1.0.0 --context app/ado-agent-iac
```

For multi-arch builds, see [OCI image cross-build guide](../docs/guides/OCI_IMAGE_CROSS_BUILD_README.md).

### Container structure tests

When a build context includes `container-structure-test.yaml` at its root (for example `ado-agent/container-structure-test.yaml`), `build-and-push-ecr.sh` runs [container-structure-test](https://github.com/GoogleContainerTools/container-structure-test) before publishing the requested image tag. Install the CLI via mise (`container-structure-test` is pinned in `.tool-versions`).

Single-platform pushes build once with Buildx, load that image locally, test it, then push that same image with `docker push`.

For multi-arch pushes, the script builds once to a temporary ECR tag, pulls and tests the first `--platforms` value locally, then promotes the tested manifest to the requested tag with `docker buildx imagetools create`. The requested tag is not published until tests pass, and the temporary ECR tag is deleted after the run. CST is invoked with `--platform` matching the tested image (required on Apple Silicon when testing non-arm64 images).

Agent deployments are managed by Helm via the [application layer](../docs/deployment/application-layer.md), not raw Kubernetes manifests in this directory.

## ADO KEDA proxy releases

The `ado-keda-proxy` image is published by GitHub Actions when a tag matching
`ado-keda-proxy/vX.Y.Z` is pushed. Images are published to:

```text
ghcr.io/launchbynttdata/platform-eks-cluster-for-ado-agents/ado-keda-proxy
```

After the first publish, confirm the GHCR package is public if the organization
default did not make linked packages public automatically. See
[ADO_KEDA_PROXY.md](../docs/reference/ADO_KEDA_PROXY.md) for runtime and
security details.
