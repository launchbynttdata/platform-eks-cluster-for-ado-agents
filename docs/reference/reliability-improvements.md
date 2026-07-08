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
- optional TLS wiring when a Kubernetes secret with `ca.pem`, `cert.pem`, and `key.pem` is provided.

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
