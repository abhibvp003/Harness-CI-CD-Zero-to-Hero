# ═══════════════════════════════════════════════════════════════════
# AWS Load Balancer Controller — Single ALB for ALL services
# MNC Pattern: 1 ALB + Ingress per service (not 4 LoadBalancers)
# Requires: domain_name variable set + Route53 + ACM cert already configured
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# IAM Policy for AWS Load Balancer Controller
# ─────────────────────────────────────────
resource "aws_iam_policy" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "ec2:Describe*",
          "ec2:Get*",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "elasticloadbalancing:*",
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:*",
          "wafv2:*",
          "shield:*",
          "tag:GetResources",
          "tag:TagResources"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = aws_iam_role.eks_nodes.name
}

# ─────────────────────────────────────────
# Install AWS Load Balancer Controller (Helm)
# ─────────────────────────────────────────
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  values = [
    yamlencode({
      clusterName = aws_eks_cluster.main.name
      region      = var.aws_region
      vpcId       = aws_vpc.main.id
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
      }
    })
  ]

  depends_on = [aws_eks_cluster.main, aws_iam_role_policy_attachment.alb_controller]
}
