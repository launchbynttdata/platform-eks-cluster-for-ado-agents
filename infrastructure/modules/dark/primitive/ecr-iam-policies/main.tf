# Minimal IAM policy that can be attached to roles which need to pull images from ECR repos
data "aws_iam_policy_document" "ecr_pull_policy" {
  count = var.create_pull_policy ? 1 : 0

  statement {
    sid = "ECRGetAuth"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECRPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid = "ECRPublicECRRead"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy"
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_pull_policy" {
  count  = var.create_pull_policy ? 1 : 0
  name   = "${var.cluster_name}-ecr-pull"
  policy = data.aws_iam_policy_document.ecr_pull_policy[0].json
  tags   = var.tags
}

# Comprehensive ECR policy for bastion host (push and pull permissions)
data "aws_iam_policy_document" "ecr_bastion_policy" {
  count = var.create_bastion_policy ? 1 : 0

  statement {
    sid = "ECRGetAuth"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid = "ECRDescribe"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeImages",
      "ecr:ListImages"
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_bastion_policy" {
  count  = var.create_bastion_policy ? 1 : 0
  name   = "${var.cluster_name}-ecr-bastion"
  policy = data.aws_iam_policy_document.ecr_bastion_policy[0].json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_pull_to_fargate" {
  count = var.attach_pull_to_fargate && var.create_pull_policy ? 1 : 0

  role       = var.fargate_role_name
  policy_arn = aws_iam_policy.ecr_pull_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "ecr_bastion_policy" {
  count = var.attach_bastion_policy && var.create_bastion_policy ? 1 : 0

  role       = var.bastion_role_name
  policy_arn = aws_iam_policy.ecr_bastion_policy[0].arn
}
