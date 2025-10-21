# Security group for EKS cluster control plane
resource "aws_security_group" "eks_cluster" {
  # checkov:skip=CKV2_AWS_5:Security group is attached to EKS cluster via additional_security_group_ids in calling module. Checkov cannot trace attachment through module boundaries.
  count = var.create_cluster_sg ? 1 : 0

  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS cluster ${var.cluster_name}"

  # Security group rules are managed as separate aws_security_group_rule resources
  # below to avoid Terraform churn caused by mixing inline blocks and rule resources.

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
      Type = "EKS-Cluster"
    }
  )

}

# Security group for Fargate pods
resource "aws_security_group" "fargate_pods" {
  # checkov:skip=CKV2_AWS_5:Security group is attached to EKS cluster via additional_security_group_ids in calling module. Checkov cannot trace attachment through module boundaries.
  count = var.create_fargate_sg ? 1 : 0

  name_prefix = "${var.cluster_name}-fargate-pods-"
  vpc_id      = var.vpc_id
  description = "Security group for Fargate pods in EKS cluster ${var.cluster_name}"

  # Security group rules are managed as separate aws_security_group_rule resources
  # below to avoid Terraform churn caused by mixing inline blocks and rule resources.

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-fargate-pods-sg"
      Type = "EKS-Fargate-Pods"
    }
  )

}

# Security group rule to allow communication between cluster and Fargate pods
resource "aws_security_group_rule" "cluster_to_fargate" {
  count = var.create_cluster_sg && var.create_fargate_sg ? 1 : 0

  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster[0].id
  security_group_id        = aws_security_group.fargate_pods[0].id
  description              = "Allow communication from EKS cluster to Fargate pods"
}

resource "aws_security_group_rule" "fargate_to_cluster" {
  count = var.create_cluster_sg && var.create_fargate_sg ? 1 : 0

  # Use an ingress rule on the cluster SG that allows traffic from the Fargate
  # pods security group. This is more explicit and avoids egress/source parsing
  # differences that can cause Terraform to plan recreation on every run.
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.fargate_pods[0].id
  security_group_id        = aws_security_group.eks_cluster[0].id
  description              = "Allow Fargate pods to communicate with EKS cluster API"
}

### Explicit SG rules that replace the previous inline blocks

# Allow HTTPS traffic to the EKS API server from allowed CIDRs
resource "aws_security_group_rule" "eks_api_ingress" {
  count = var.create_cluster_sg ? 1 : 0

  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_cluster[0].id
  cidr_blocks       = var.allowed_cidr_blocks
  description       = "All TCP traffic from VPC"
}

# Allow all outbound traffic from EKS cluster
resource "aws_security_group_rule" "eks_egress_all" {
  # checkov:skip=CKV_AWS_382:Unrestricted egress required for EKS cluster operation - downloads from ECR/container registries, AWS API calls (EC2/ELB/S3), DNS resolution, and ADO connectivity. Restricting would require maintaining extensive allow-lists that break with new AWS services or third-party dependencies.
  count = var.create_cluster_sg ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_cluster[0].id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound traffic - required for EKS cluster operation"
}

# Allow all TCP traffic from VPC into fargate pods
resource "aws_security_group_rule" "fargate_ingress_vpc" {
  count = var.create_fargate_sg ? 1 : 0

  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.fargate_pods[0].id
  cidr_blocks       = [var.vpc_cidr]
  description       = "All TCP traffic from VPC"
}

# Allow all outbound traffic from fargate pods
resource "aws_security_group_rule" "fargate_egress_all" {
  # checkov:skip=CKV_AWS_382:Unrestricted egress required for Fargate pods - container image pulls from registries, AWS service communication, ADO agent connectivity, and application dependencies. Kubernetes workloads require dynamic internet access that cannot be effectively restricted without breaking functionality.
  count = var.create_fargate_sg ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.fargate_pods[0].id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound traffic - required for container image pulls and ADO connectivity"
}

# Explicit HTTPS egress from fargate pods (kept for clarity)
resource "aws_security_group_rule" "fargate_egress_https" {
  count = var.create_fargate_sg ? 1 : 0

  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.fargate_pods[0].id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS outbound for ADO API - redundant but more explicit"
}
