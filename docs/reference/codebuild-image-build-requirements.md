# CodeBuild Image Build Requirements

## Purpose

This document defines requirements for adding AWS CodeBuild as an optional container image build backend for Azure DevOps (ADO) pipelines that run on this platform.

The current platform deploys:

- an EKS cluster,
- KEDA-scaled ADO agent jobs,
- optional EC2 node groups,
- a BuildKit daemon in Kubernetes for container image builds,
- ECR pull-through cache support for selected public registries.

BuildKit must remain supportable. The new work should allow platform operators to choose BuildKit-based builds, CodeBuild-based builds, or both at the same time.

The ADO pipeline changes that call CodeBuild are separate work. This document still defines the expected integration shape so the infrastructure and pipeline work fit together.

## Background

The current BuildKit model exposes a shared Kubernetes BuildKit service to ADO agent pods through `BUILDKIT_HOST`. This keeps image builds close to the EKS platform, but it also puts build reliability inside the Kubernetes worker capacity and the BuildKit daemon's pod resources.

Observed failure modes include:

- builds fail when the BuildKit pod runs out of ephemeral storage,
- builds fail when the underlying node runs out of temporary disk,
- builds fail when Kubernetes CPU or memory limits are reached,
- builds appear blocked behind other builds without useful ADO pipeline feedback.

AWS CodeBuild is a better fit for on-demand build execution because each build can run in isolated AWS-managed build compute with explicit CPU, memory, and disk choices. ADO should remain in control by starting the CodeBuild build, polling status, streaming CloudWatch Logs back into the ADO task output, and failing the ADO job if CodeBuild fails.

## Goals

- Keep BuildKit as a supported image build backend.
- Add CodeBuild as an optional image build backend.
- Allow environments to disable BuildKit and BuildKit-only EC2 node capacity when CodeBuild is used instead.
- Allow environments to run both BuildKit and CodeBuild during migration.
- Provide infrastructure outputs and IAM permissions that make the ADO pipeline implementation straightforward.
- Make queueing, build phases, and build logs visible in ADO pipeline output.
- Keep CodeBuild build resources isolated from EKS pod and node resource limits.

## Non-Goals

- Do not replace KEDA-based ADO agent scaling.
- Do not remove External Secrets Operator, metrics server, observability, or other middleware just because BuildKit is disabled.
- Do not implement the ADO pipeline wrapper in this infrastructure change.
- Do not require all application teams to use one shared CodeBuild project if their build requirements differ.
- Do not make CodePipeline the primary orchestration layer. ADO is already the pipeline orchestrator.

## Deployment Modes

### BuildKit-only

The platform deploys BuildKit in Kubernetes and injects `BUILDKIT_HOST` into ADO agent jobs.

Requirements:

- `enable_buildkitd = true`.
- BuildKit Kubernetes resources, service account, IAM role, service, HPA, PDB, and optional TLS stay managed.
- BuildKit node selectors, tolerations, and storage settings remain configurable.
- BuildKit-specific EC2 node groups remain optional, not mandatory.
- Existing documentation for BuildKit setup and operation remains accurate.

### CodeBuild-only

The platform does not deploy BuildKit, and ADO pipelines send image build work to CodeBuild.

Requirements:

- `enable_buildkitd = false` disables all BuildKit Kubernetes resources and BuildKit IAM resources.
- ADO agent Helm values set `buildkit.enabled = false`, so `BUILDKIT_HOST` is not injected.
- BuildKit-only EC2 node groups can be omitted from `ec2_node_groups`.
- `enable_cluster_autoscaler` can be disabled when no EC2 node groups remain.
- ECR pull-through cache can remain enabled if useful for other workloads, but it is not required only because CodeBuild is enabled.
- CodeBuild resources and ADO agent IAM permissions are available through this repo or through documented external prerequisites.

### Hybrid

The platform deploys BuildKit and CodeBuild support at the same time.

Requirements:

- `enable_buildkitd = true` remains valid.
- CodeBuild projects or project factory resources can also be created.
- ADO pipeline authors choose the backend per pipeline, repository, image, or stage.
- Documentation explains that hybrid mode is useful for migration, fallback, or different build profiles.
- The two backends must not require conflicting IAM assumptions or Helm values.

## CodeBuild Resource Ownership

There are two viable infrastructure patterns: a concrete CodeBuild project and a CodeBuild project factory.

### CodeBuild Project

A CodeBuild project is one AWS CodeBuild build definition. It has a service role, environment image, compute type, source behavior, buildspec, logging configuration, timeout, cache configuration, and optional VPC settings.

Use direct projects when:

- there are only one or two standardized image build jobs,
- platform operators want tight central control,
- each project has a stable buildspec and compute profile,
- application teams do not need to create many variants.

Advantages:

- simplest implementation,
- easier to reason about least-privilege IAM,
- clearer outputs for ADO pipelines,
- less Terraform schema surface.

Tradeoffs:

- does not scale well when many teams need different Dockerfiles, build args, platforms, or compute sizes,
- changes to a shared project can affect unrelated builds,
- ADO may need many runtime overrides if one project is stretched too far.

### CodeBuild Project Factory

A project factory is a Terraform module or configuration map that creates multiple CodeBuild projects from repeatable defaults. For example, the platform could expose `codebuild_image_build_projects = { ... }` and create one project per entry.

Use a factory when:

- multiple image repositories need separate build projects,
- teams need different compute sizes, timeouts, buildspec paths, source modes, cache settings, or ECR targets,
- the platform should enforce common defaults while allowing controlled per-project overrides,
- migration will happen gradually across many pipelines.

Advantages:

- supports many builds without copy-paste Terraform,
- centralizes security, logging, naming, tags, and default build settings,
- allows per-image least-privilege ECR policies,
- creates stable project names and outputs for ADO pipeline consumers.

Tradeoffs:

- more schema design is required,
- validation matters more,
- documentation must explain defaults and override behavior,
- overly flexible inputs can become hard to maintain.

### Recommendation

Implement a small factory rather than a single hard-coded project if this platform is expected to support more than one image build over time.

The factory should still allow the simplest case: one map entry creates one image-builder project with platform defaults. Avoid a highly generic CodeBuild module on the first pass; model the image-build use case directly.

## Infrastructure Requirements

### Configuration

Add optional CodeBuild image build configuration. Exact variable names may change during implementation, but the configuration must support:

- global enablement, for example `enable_codebuild_image_builder`,
- zero or more project definitions,
- project name or name suffix,
- build description,
- compute type,
- environment type,
- build image,
- privileged mode,
- timeout and queued timeout,
- source mode,
- buildspec mode,
- CloudWatch Logs configuration,
- optional S3 source handoff bucket configuration,
- optional cache configuration,
- ECR repository ARNs the project can push to,
- optional KMS key ARNs needed for encrypted ECR repositories or S3 artifacts,
- tags.

### Source Handoff Modes

Support at least one source handoff mode. Prefer supporting both when practical.

S3 handoff:

- ADO zips the checked-out workspace.
- ADO uploads the archive to an encrypted S3 object.
- ADO starts CodeBuild using the S3 object as the build source or as an environment-provided input.
- This is the preferred mode for Azure Repos because CodeBuild does not natively list Azure Repos as a source provider.

Native Git source:

- CodeBuild reads source directly from a supported provider such as GitHub, GitLab, Bitbucket, or CodeCommit.
- ADO starts the build with a source version, branch, tag, or commit.
- This is useful when the source provider is already connected to CodeBuild.

### CodeBuild Project Defaults

Default project settings should be conservative:

- Linux container environment.
- Privileged mode enabled for Docker builds.
- No build artifacts unless explicitly requested.
- CloudWatch Logs enabled.
- A build timeout with a clear default.
- A queued timeout with a clear default.
- Explicit ECR permissions rather than broad account-wide push access where possible.
- Environment variables only for non-secret defaults.
- Secrets should use Secrets Manager, SSM Parameter Store, or ADO secret variables rather than plaintext Terraform values.

### IAM

The CodeBuild service role must allow:

- CloudWatch Logs stream creation and log event writes,
- ECR authorization,
- ECR pull and push actions for configured repositories,
- S3 read access for source archives when S3 handoff is used,
- S3 write access only if build artifacts or cache require it,
- KMS decrypt/encrypt access for configured S3, ECR, or log encryption keys,
- optional VPC permissions if CodeBuild projects run inside a VPC.

The ADO agent IAM role must allow the pipeline wrapper to:

- start an allowed CodeBuild project,
- read build status,
- stop the build on cancellation or timeout,
- read the associated CloudWatch log stream,
- upload and optionally delete S3 source archives when S3 handoff is used,
- use required KMS keys for the S3 source archive.

The ADO agent role should not receive broad CodeBuild administration permissions.

### Outputs

Expose outputs that ADO pipeline authors can consume:

- CodeBuild project names,
- CodeBuild project ARNs,
- optional S3 source bucket name and ARN,
- CloudWatch log group names,
- ADO agent policy ARNs or rendered permission guidance,
- backend enablement flags.

For a factory, outputs should be keyed by project key.

### BuildKit Compatibility

BuildKit variables and docs must continue to work.

Requirements:

- `enable_buildkitd = false` should not require deleting every `buildkitd_*` value from environment files unless the Terragrunt wiring is updated to provide defaults with `try(...)`.
- Documentation must clearly identify which BuildKit settings are ignored when BuildKit is disabled.
- Documentation must explain how to omit BuildKit-only EC2 node groups.
- Documentation must state that disabling BuildKit does not imply disabling KEDA, ESO, metrics server, observability, or the ADO application layer.

## Documentation Requirements

Update documentation so operators can understand and choose a build backend.

Required updates:

- Update the documentation hub to link to CodeBuild image build documentation.
- Update the middleware deployment docs to describe BuildKit as optional.
- Update the application or ADO agent Helm docs to explain when `BUILDKIT_HOST` is injected.
- Update the Terragrunt configuration reference with CodeBuild settings and with BuildKit-disabled examples.
- Add examples for:
  - BuildKit-only,
  - CodeBuild-only,
  - hybrid.
- Update operations docs with troubleshooting for:
  - CodeBuild queued too long,
  - CodeBuild failed,
  - missing CloudWatch logs,
  - ECR permission denied,
  - S3 source upload or download denied,
  - ADO cancellation should stop the CodeBuild build.

The docs should avoid implying that CodeBuild replaces ADO. CodeBuild replaces the build execution backend for container image builds; ADO remains the pipeline control plane.

## Expected ADO Pipeline Shape

The detailed ADO pipeline implementation is separate work, but it should follow this shape.

1. Checkout source in ADO.
2. Resolve image metadata:
   - ECR registry,
   - repository,
   - tag,
   - Dockerfile path,
   - build context path,
   - target platform,
   - build args.
3. If using S3 handoff:
   - create a source archive from the current workspace,
   - upload it to the configured S3 source bucket,
   - record bucket, key, and optional object version.
4. Start CodeBuild:
   - call `aws codebuild start-build`,
   - pass project name,
   - source version or S3 source location,
   - environment variable overrides for image metadata,
   - an idempotency token tied to the ADO run when practical.
5. Poll CodeBuild:
   - call `aws codebuild batch-get-builds`,
   - print queue and phase transitions,
   - discover CloudWatch log group and stream once available.
6. Stream logs:
   - call `aws logs get-log-events`,
   - print new log messages into the ADO task output,
   - continue until the build reaches a terminal state.
7. Handle cancellation:
   - if the ADO job is canceled or times out, call `aws codebuild stop-build`.
8. Complete:
   - fail the ADO task if CodeBuild status is not `SUCCEEDED`,
   - print the final image URI and digest when available,
   - delete temporary S3 source archives if the retention model requires explicit cleanup.

## Buildspec Shape

The CodeBuild buildspec should be owned by the image build workflow. It can live in the source repo, in this platform repo, or in S3 depending on the selected model.

At minimum, the buildspec should:

- log in to ECR,
- validate required environment variables,
- run the Docker or Buildx build,
- tag the image,
- push to ECR,
- print the resulting image URI,
- produce enough log output for ADO users to understand progress.

Multi-architecture builds may require Buildx and QEMU setup inside CodeBuild. That should be treated as a buildspec concern unless the platform owns a custom CodeBuild build image.

## Acceptance Criteria

- Existing BuildKit-only environments can still deploy without CodeBuild configured.
- CodeBuild-only environments can deploy without BuildKit Kubernetes resources.
- Hybrid environments can deploy both backends.
- ADO agent pods do not receive `BUILDKIT_HOST` when BuildKit is disabled.
- BuildKit-only EC2 node groups can be omitted without breaking non-BuildKit middleware.
- CodeBuild projects are created with least-privilege service roles.
- ADO agent IAM permissions allow starting, monitoring, logging, and stopping only approved CodeBuild projects.
- Documentation explains project vs factory and recommends the factory for multiple image build definitions.
- Documentation includes enough ADO pipeline shape for a separate agent to implement the pipeline wrapper.
- Validation covers at least Terraform formatting and validation for the affected layers.

## Open Questions

- Should CodeBuild projects be owned centrally by this platform repo, or should this repo only provide IAM permissions and documented external prerequisites?
- Is Azure Repos the expected source provider for all image builds, making S3 handoff mandatory for the first implementation?
- Should the platform create one shared source handoff bucket per environment, or one bucket/prefix per CodeBuild project?
- Should build caches use CodeBuild local cache, S3 cache, ECR cache exports, or no cache initially?
- Are multi-architecture builds required in the first CodeBuild implementation?
- Should the platform provide a custom CodeBuild image with Docker, Buildx, AWS CLI, and helper scripts preinstalled?

## References

- [AWS CodeBuild compute modes and types](https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-compute-types.html)
- [AWS CodeBuild Docker image to ECR sample](https://docs.aws.amazon.com/codebuild/latest/userguide/sample-docker.html)
- [AWS CodeBuild project source types](https://docs.aws.amazon.com/codebuild/latest/APIReference/API_ProjectSource.html)
- [AWS CodeBuild StartBuild API](https://docs.aws.amazon.com/codebuild/latest/APIReference/API_StartBuild.html)
- [AWS CodeBuild BatchGetBuilds API](https://docs.aws.amazon.com/codebuild/latest/APIReference/API_BatchGetBuilds.html)
- [Amazon CloudWatch Logs GetLogEvents API](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_GetLogEvents.html)
