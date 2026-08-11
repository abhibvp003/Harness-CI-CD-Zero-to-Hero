data "aws_acm_certificate" "wildcard" {
  domain      = "*.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_iam_policy" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:CreateServiceLinkedRole", "ec2:Describe*", "ec2:Get*",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
        "ec2:CreateTags", "ec2:DeleteTags", "elasticloadbalancing:*",
        "acm:ListCertificates", "acm:DescribeCertificate",
        "waf-regional:*", "wafv2:*", "shield:*", "tag:GetResources", "tag:TagResources"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = var.node_role_name
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  values = [
    yamlencode({
      clusterName    = var.eks_cluster_name
      region         = var.aws_region
      vpcId          = var.vpc_id
      serviceAccount = { create = true, name = "aws-load-balancer-controller" }
    })
  ]
}
