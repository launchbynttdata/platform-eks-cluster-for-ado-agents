# ADO Agent and BuildKit Reliability

This platform keeps each Azure DevOps agent pool schedulable with a registered offline template agent per enabled pool. Azure DevOps can queue jobs when matching offline agents remain registered, and KEDA uses those template agents for demand matching.

## Agent Job Isolation

The Helm chart runs real workers as KEDA `ScaledJob` resources:

- A Helm hook Job registers one stable offline template agent per pool, for example `dev-build-keda-template`.
- The KEDA Azure Pipelines trigger uses `parent` to match queued jobs against the template agent capabilities.
- Each queued job creates an independent Kubernetes Job pod.
- Worker pods run the Azure Pipelines agent with `--once`, unregister during cleanup, and exit.
- Completed and failed worker Jobs are retained only according to the configured history limits and TTL.

This avoids the Deployment downscale failure mode where Kubernetes can delete an active long-running agent pod because neither KEDA nor the ReplicaSet can identify which pod is busy with an Azure DevOps job.

## CloudWatch Logs

The middleware layer creates CloudWatch log groups under `/aws/containerinsights/<cluster-name>/...` and can install the Amazon CloudWatch Observability EKS add-on for EC2-backed pods. For Fargate-backed pods, it creates the required `aws-observability/aws-logging` ConfigMap.

Set `enable_ado_agent_cloudwatch_log_groups = false` in `env.hcl` to skip Terraform creation of the ADO agent log group when the deploy role lacks CloudWatch Logs permissions or KMS key policy blocks log group creation.

Dashboards and alarms are intentionally separate follow-up work. This phase only makes logs available.

## BuildKit Reliability

BuildKit remains a ClusterIP service, with these reliability controls:

- dedicated node selectors and tolerations from environment configuration,
- optional topology spread across zones,
- a PodDisruptionBudget,
- HPA support,
- configurable OCI-worker garbage collection thresholds,
- automatic rolling restarts when the rendered BuildKit daemon configuration changes,
- optional node-level kernel keyring limits raised by a privileged init container,
- optional Kubernetes ephemeral-storage requests and limits,
- separate size limits for the cache and `/tmp` node-backed `emptyDir` volumes,
- optional TLS wiring when a Kubernetes secret with `ca.pem`, `cert.pem`, and `key.pem` is provided.

BuildKit garbage collection removes unused cache; it cannot reclaim records used
by an active build. Configure `buildkitd_gc.max_used_space` below
`buildkitd_storage_size` with enough remaining space for the largest expected
active build. The `emptyDir` size limits do not provision disk and can never
exceed the storage available on the selected node. Kubernetes also uses the same
node-local storage for container images, writable layers, logs, and system data.

Set `buildkitd_resources.requests.ephemeral_storage` so the scheduler and Cluster
Autoscaler account for expected pod disk use. Set
`buildkitd_resources.limits.ephemeral_storage` to bound total pod ephemeral
storage, including `emptyDir` volumes, writable layers, and logs.

Changes to `buildkitd_gc` are hashed into the BuildKit Deployment pod template.
Applying a GC change therefore performs a rolling restart so each new daemon
loads the updated `buildkitd.toml`; no manual `kubectl rollout restart` is
required. Schedule those updates outside active builds because restarting a pod
interrupts its in-flight builds and clears its node-local `emptyDir` cache.

runc allocates a Linux kernel session keyring per build container. The default
per-UID quota is 200 keys / 20000 bytes, and high-churn builds (for example
containerized .NET builds with many stages) can exhaust it, failing container
init with `unable to create session key: disk quota exceeded` — a keyring quota,
not a disk-space, error. This is distinct from the `emptyDir`/ephemeral-storage
controls above. Set `buildkitd_node_keyring_limits` to raise
`kernel.keys.maxkeys`/`maxbytes`; because that sysctl is node-level and not
namespaced, a privileged init container applies it on the host before buildkitd
starts. Raising the ceiling is a mitigation: if the per-UID key count keeps
climbing toward the new limit and never drains between builds (watch the
`qnkeys/maxkeys` field for the BuildKit UID in `/proc/key-users`), keyrings are
leaking rather than churning, which is a runtime-level issue to fix separately.

### Known issue: BuildKit keyring leak (moby/buildkit#6247)

Rootless BuildKit runs every build under a single UID, and runc allocates one
kernel session keyring per build container ([opencontainers/runc#488](https://github.com/opencontainers/runc/pull/488)).
In this deployment those keyrings accumulate under the build UID and are not
reclaimed on container exit, so over days of uptime the per-UID quota is
exhausted and builds fail at container init with `unable to create session key:
disk quota exceeded`. This is tracked upstream in
[moby/buildkit#6247](https://github.com/moby/buildkit/issues/6247), which is open
with no fix as of this writing. The error text mentions "disk quota" but it is a
kernel keyring quota (`EDQUOT`), unrelated to disk space or the `emptyDir`/GC
controls above; a cache prune does not clear it, only a daemon restart does.

Two controls address it, and both are expected to become unnecessary once the
upstream bug is fixed:

- `buildkitd_node_keyring_limits` raises the per-UID key ceiling, which *delays*
  exhaustion but does not stop a genuine leak.
- `buildkitd_recycle` schedules a least-privilege CronJob that runs
  `kubectl rollout restart deployment/buildkitd` (default: 02:00 Sunday
  US/Pacific, weekly) to reclaim the leaked keyrings before the ceiling is hit.
  The CronJob's ServiceAccount is limited to `get`/`patch` on the single
  `buildkitd` Deployment. Because a restart interrupts in-flight builds and
  clears the node-local `emptyDir` cache, schedule it during a low-traffic
  window.

To confirm whether keys are still leaking on a given BuildKit/runc version, watch
the `qnkeys/maxkeys` field for the BuildKit UID across a sequence of builds:

```sh
while true; do printf '%s ' "$(date -u +%T)"; \
  kubectl -n <buildkit-namespace> exec deploy/buildkitd -- grep '^ *<uid>:' /proc/key-users; \
  sleep 10; done
```

A count that climbs across builds and never returns to baseline (well past
`kernel.keys.gc_delay`) indicates a leak; transient spikes that drain are normal
churn. **Revisit both controls when moby/buildkit#6247 is resolved** and the
fixed image is deployed — at that point keys should reclaim on container exit,
and the scheduled recycle plus raised ceiling can be removed.

## ECR Pull-Through Cache

The middleware layer creates anonymous-compatible ECR pull-through cache rules for:

- `public.ecr.aws`
- `registry.k8s.io`
- `quay.io`

For each enabled pull-through cache rule, the middleware layer also creates an ECR repository creation template. Repositories that ECR creates on first pull receive a lifecycle policy for untagged cache images and, by default, a pull policy for the cluster account. Set `create_ecr_pull_through_cache_repository_policies = false` to omit the repository policy from those templates when policy management is handled outside this stack or temporarily unavailable to the deploy role. The BuildKit role receives first-pull cache population permissions for the managed prefixes. BuildKit registry mirrors are derived automatically from the cache rules as `<account>.dkr.ecr.<region>.amazonaws.com/<prefix>`, so build users can keep normal `FROM public.ecr.aws/...`, `FROM registry.k8s.io/...`, and `FROM quay.io/...` references.

Docker Hub pull-through cache is intentionally not created in phase 1 because ECR requires Docker Hub credentials in Secrets Manager for that upstream. Docker Hub references remain anonymous fallback unless Dockerfiles or pipeline templates are rewritten to a cached public upstream.

Microsoft Container Registry (`mcr.microsoft.com`) is not currently one of the anonymous public upstreams supported by ECR pull-through cache. ECR supports Microsoft Azure Container Registry as an authenticated upstream for `<registry>.azurecr.io` registries, but authenticated cache rules require Secrets Manager credentials and are intentionally deferred to a later phase.

## Operational Checks

Useful commands after deployment:

- `kubectl get scaledjobs -n ado-agents`
- `kubectl get jobs -n ado-agents`
- `kubectl get pods -n ado-agents -l app.kubernetes.io/name=ado-agent-cluster`
- Confirm every pool has an offline template agent in Azure DevOps with the configured `templateAgentName`.
