output "node_group_id" {
  description = "The ID of the EKS Node Group"
  value       = aws_eks_node_group.this.id
}