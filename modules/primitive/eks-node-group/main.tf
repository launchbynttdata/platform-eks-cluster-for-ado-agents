locals {
  cluster_autoscaler_tag_list = [
    for tag_key, tag_value in var.cluster_autoscaler_tags : {
      key   = tag_key
      value = tag_value
    }
  ]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types
  disk_size       = var.disk_size
  ami_type        = var.ami_type != null ? var.ami_type : null
  capacity_type   = var.capacity_type
  labels          = var.labels
  tags = merge(
    var.tags,
    { "Name" = var.node_group_name },
    var.enable_cluster_autoscaler ? {
      "k8s.io/cluster-autoscaler/enabled"             = "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    } : {},
    var.cluster_autoscaler_tags
  )

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  dynamic "taint" {
    for_each = var.taints
    iterator = taint
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  update_config {
    max_unavailable            = var.max_unavailable
    max_unavailable_percentage = var.max_unavailable_percentage != null ? var.max_unavailable_percentage : null
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }

}

resource "aws_autoscaling_group_tag" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? length(local.cluster_autoscaler_tag_list) : 0

  autoscaling_group_name = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name

  tag {
    key                 = local.cluster_autoscaler_tag_list[count.index].key
    value               = local.cluster_autoscaler_tag_list[count.index].value
    propagate_at_launch = true
  }
}