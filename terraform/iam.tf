# IRSA (IAM Roles for Service Accounts) Example
# This demonstrates the secure way to grant AWS permissions to Kubernetes pods
# without embedding credentials or using node-level IAM roles

# Example: IAM role for demo-app ServiceAccount
# This role can be assumed by pods in the demo-app namespace
resource "aws_iam_role" "demo_app_irsa" {
  name = "${var.cluster_name}-demo-app-irsa"

  # Trust policy: Allow the OIDC provider to assume this role
  # Only pods with the specific ServiceAccount can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # This condition ensures only the demo-app ServiceAccount can assume the role
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:demo-app:demo-app-sa"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-demo-app-irsa"
  }
}

# Example policy: Grant S3 read access
# Replace this with actual permissions needed by your workload
resource "aws_iam_role_policy" "demo_app_s3_read" {
  name = "s3-read-access"
  role = aws_iam_role.demo_app_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::example-bucket",
          "arn:aws:s3:::example-bucket/*"
        ]
      }
    ]
  })
}

# IRSA for AWS Load Balancer Controller
# This role allows the controller to create and manage ALBs/NLBs
data "aws_iam_policy_document" "aws_lb_controller_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${var.cluster_name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_lb_controller_assume_role.json

  tags = {
    Name = "${var.cluster_name}-aws-lb-controller"
  }
}

# Attach the AWS-managed policy for Load Balancer Controller
resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

# For production, use a more restrictive custom policy instead:
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
