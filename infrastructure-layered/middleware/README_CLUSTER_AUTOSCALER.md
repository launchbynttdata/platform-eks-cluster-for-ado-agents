## Cluster Autoscaler Deployment in Layered Infrastructure

### Overview

Cluster Autoscaler is now provisioned entirely through Terraform:

1. **Base layer** creates the IAM role, attaches autoscaling permissions, and tags every managed node group for auto-discovery.
2. **Middleware layer** installs the upstream Cluster Autoscaler deployment via the `modules/primitive/cluster-autoscaler` Terraform module. No manual YAML or `sed` substitution is required.

Autoscaler resources are only created when `enable_cluster_autoscaler = true` in the base layer.

### Base Layer Inputs

```hcl
enable_cluster_autoscaler     = true
cluster_autoscaler_namespace  = "kube-system"
cluster_autoscaler_version    = "v1.33.0"
cluster_autoscaler_extra_args = {
   "scan-interval"                   = "10s"
   "scale-down-utilization-threshold" = "0.5"
}
```

### Middleware Layer Controls

The middleware layer exposes optional tuning knobs via `variables.tf`:

```hcl
cluster_autoscaler_node_selector = {
   "workload-type" = "system"
}

cluster_autoscaler_tolerations = [{
   key      = "node-role.kubernetes.io/system"
   operator = "Exists"
   effect   = "NoSchedule"
}]

cluster_autoscaler_additional_args = {
   "skip-nodes-with-system-pods" = "false"
}
```

These values feed the Terraform module and are merged with any extra CLI arguments coming from the base layer, allowing platform teams to fine-tune behavior without editing manifests.

### Deployment Flow

```
cd infrastructure-layered
./deploy.sh --layer base        # creates IAM + node-group tags
./deploy.sh --layer middleware  # installs Autoscaler (and other operators)
```

The middleware apply automatically rolls the Deployment if configuration changes (version bump, new flags, scheduling rules, etc.).

### Verification Checklist

```bash
# Deployment available?
kubectl get deployment -n kube-system cluster-autoscaler

# Pod healthy?
kubectl get pods -n kube-system -l app=cluster-autoscaler -w

# Logs show ASG discovery?
kubectl logs -n kube-system deploy/cluster-autoscaler | grep "Discovered"
```

Expected log snippet:

```
I0106 12:00:00.000000       1 auto_scaling_groups.go:xxx] Discovered 3 ASGs
```

### Scaling Drills

**Scale Up**

```bash
kubectl create deployment autoscale-test --image=nginx --replicas=20
kubectl set resources deployment autoscale-test --requests=cpu=1,memory=1Gi
kubectl get nodes -w
```

**Scale Down**

```bash
kubectl delete deployment autoscale-test
# Wait for --scale-down-delay-after-add (default 10m)
kubectl get nodes -w
```

### Troubleshooting Tips

1. **No Deployment** – ensure `terraform output cluster_autoscaler_role_arn` in the base layer is non-null and re-run the middleware layer.
2. **Pods Pending** – verify `cluster_autoscaler_node_selector` matches a tainted system node group and that metrics-server add-on is healthy (`kubectl top nodes`).
3. **No Scaling Events** – check logs for `Failed to discover ASGs`; confirm EC2 node groups have the required tags and `max_size` accommodates growth.

### References

- [AWS Cluster Autoscaler Documentation](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)
- [Cluster Autoscaler GitHub](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
