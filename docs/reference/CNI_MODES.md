# Pod Networking Modes

## Summary

The platform supports two pod networking modes:

| Mode | Compute support | Pod IP source | Primary use |
|------|-----------------|---------------|-------------|
| `vpc-cni` | EC2 and Fargate | VPC subnet IPs | Default mode and all Fargate workloads |
| `cilium-overlay` | EC2 only | Cilium cluster-pool CIDRs | Reduce pod IP pressure on cluster subnets |

Amazon VPC CNI remains the default because it is the only CNI mode supported with EKS Fargate. Cilium overlay is available for EC2-node clusters that need pod IPs to come from a non-VPC-routable overlay range.

## VPC CNI Mode

Use `pod_networking_mode = "vpc-cni"` when:

- Fargate profiles are enabled.
- Pods need VPC-routable IP addresses.
- You want the AWS-supported EKS CNI path.

In this mode, the base layer manages the `vpc-cni` EKS add-on, VPC CNI IRSA role, and VPC CNI IAM policy attachment.

## Cilium Overlay Mode

Use `pod_networking_mode = "cilium-overlay"` when:

- Fargate profiles are disabled.
- At least one EC2 node group is configured.
- Pod IP exhaustion in cluster subnets is the problem being solved.
- Workloads can tolerate pod traffic being SNATed through node IPs for destinations outside the cluster.

Required base-layer configuration:

```hcl
pod_networking_mode = "cilium-overlay"
fargate_profiles    = {}

eks_addons = {
  "coredns" = {
    version = "v1.14.2-eksbuild.4"
  }
  "kube-proxy" = {
    version = "v1.35.3-eksbuild.2"
  }
}
```

The base layer bootstraps Cilium with overlay cluster-pool IPAM before EC2 managed node groups are created:

```hcl
cilium_networking = {
  chart_version                   = "1.19.5"
  cluster_pool_ipv4_pod_cidr_list = ["100.64.0.0/10"]
  cluster_pool_ipv4_mask_size     = 24
  helm_values_override            = {}
}
```

Choose a Cilium pod CIDR that does not overlap the VPC CIDR, Kubernetes service CIDR, peered VPC CIDRs, on-premises routes, or other routed networks.

Private clusters without NAT must use a registry path reachable from the node subnets for Cilium images. The default Cilium chart images are not served by AWS VPC endpoints. Mirror the Cilium agent and operator images to private ECR or another reachable registry and set the Helm image repository overrides in `helm_values_override`.

## Operational Caveats

- EKS supports alternate CNI installation on EC2 nodes, but Amazon VPC CNI is the only CNI supported by Amazon EKS for EC2 nodes.
- Alternate CNIs cannot be used with Fargate nodes.
- Cilium overlay pod IPs are not directly routable from the VPC.
- Traffic from pods to VPC resources and AWS services is masqueraded through the EC2 node IP.
- The EKS API server cannot directly route to overlay pod IPs. Admission webhooks must use host networking or be exposed through a service path that works with this limitation.
- EC2 node groups receive the Cilium startup taint `node.cilium.io/agent-not-ready=true:NoExecute` so workloads wait until Cilium is ready.
- Cilium must be present before managed node groups bootstrap. If nodes start before any CNI is installed, managed node group creation can fail with `cni plugin not initialized`.
- The base layer patches any existing `kube-system/aws-node` DaemonSet so it does not schedule in `cilium-overlay` mode. Do not re-enable it unless switching back to `vpc-cni`.

## Existing Cluster Conversion Notes

This feature is designed as a selectable CNI mode, not an automated migration workflow. Existing clusters can be converted only as an operational maintenance activity.

For this platform, treating the cluster as mostly ephemeral is the simplest path. The safest operational posture is to expect application and middleware workloads to be interrupted, recreated, or manually restarted after the base layer changes CNI mode.

Important in-place caveats:

- Terraform does not perform an atomic CNI handoff. Switching from `vpc-cni` to `cilium-overlay` removes the managed VPC CNI resources from the desired state, patches any existing `aws-node` DaemonSet away from nodes, installs Cilium, and updates node group taints in one base-layer operation.
- Existing pods are not automatically recreated with Cilium pod IPs. Pods that were created under VPC CNI can keep their existing network namespace until they are deleted or rescheduled.
- If the apply fails after `aws-node` is disabled but before Cilium is healthy, existing and new pods can lose networking until the CNI state is repaired.
- Existing node groups may be updated in place, but replacing node groups is often cleaner for an ephemeral cluster because new nodes bootstrap directly with the intended CNI state.
- Rollback to `vpc-cni` after pods have been recreated under Cilium is another disruptive maintenance activity, not a trivial toggle.

High-level conversion notes:

1. Stop ADO/KEDA workload intake and allow active jobs to finish, or accept that active jobs may be interrupted.
2. Destroy or scale down the application layer first if preserving running workloads is not required. This avoids old Helm hooks, ScaledJobs, and agent pods confusing the CNI transition.
3. Destroy or scale down middleware if you want a cleaner cluster-side transition. For an ephemeral cluster, this is usually less risky than preserving all pods during the CNI handoff.
4. Disable Fargate profiles and ensure all required workloads can run on EC2 nodes.
5. Remove `vpc-cni` from `eks_addons` and set `pod_networking_mode = "cilium-overlay"`.
6. Apply the base layer so Cilium is bootstrapped, VPC CNI resources are no longer managed, and EC2 nodes receive the Cilium startup taint.
7. If reusing existing nodes, verify that `aws-node` is not running, Cilium pods are ready, and old workloads are restarted. If networking looks inconsistent, replacing the EC2 node groups is usually cleaner than debugging mixed CNI state in place.
8. Apply the networking layer to validate networking mode consistency.
9. Apply middleware, application, and config layers, then restore workload intake.

## References

- [AWS alternate CNI plugins for Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html)
- [AWS Fargate considerations](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
- [Cilium Helm installation for EKS](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
