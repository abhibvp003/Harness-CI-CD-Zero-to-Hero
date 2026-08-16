# ═══════════════════════════════════════════════════════════════════
# EKS Cluster — Standard Managed (NOT Auto Mode)
# Production pattern: Managed Node Groups + Cluster Autoscaler
# High availability, auto-scaling, no taints on worker nodes
# ═══════════════════════════════════════════════════════════════════

# IAM role for the EKS control plane
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Control plane policies
resource "aws_iam_role_policy_attachment" "cluster_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ])
  policy_arn = each.value
  role       = aws_iam_role.eks_cluster.name
}

# IAM role for worker nodes
resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Worker node policies (standard set for managed node groups)
resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    "arn:aws:iam::aws:policy/AmazonRoute53FullAccess",
  ])
  policy_arn = each.value
  role       = aws_iam_role.eks_nodes.name
}

# Security group for EKS cluster
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-eks-sg"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-eks-sg" })
}

# KMS key for secrets encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.cluster_name}-eks-kms" })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ═══════════════════════════════════════════════════════════════════
# EKS Cluster (Standard — no Auto Mode)
# ═══════════════════════════════════════════════════════════════════
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  encryption_config {
    resources = ["secrets"]
    provider { key_arn = aws_kms_key.eks.arn }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [aws_iam_role_policy_attachment.cluster_policies]

  tags = merge(var.tags, { Name = var.cluster_name })
}

# ═══════════════════════════════════════════════════════════════════
# EKS Addons (required for managed node groups)
# ═══════════════════════════════════════════════════════════════════
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_node_group.workloads]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.workloads]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_node_group.workloads]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.eks_nodes.arn
  depends_on               = [aws_eks_node_group.workloads]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
  depends_on   = [aws_eks_node_group.workloads]
}

# ═══════════════════════════════════════════════════════════════════
# Managed Node Group — Application Workloads (Kong, Monitoring, GitOps, Apps)
# ═══════════════════════════════════════════════════════════════════
resource "aws_eks_node_group" "workloads" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-workloads"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.subnet_ids

  instance_types = ["t3a.large", "t3.large", "m5a.large"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 3
    min_size     = 2
    max_size     = 10
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "workloads"
  }

  tags = merge(var.tags, {
    Name                                            = "${var.cluster_name}-workloads"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
  })

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}

# ═══════════════════════════════════════════════════════════════════
# Managed Node Group — CI Builds (Harness pipelines run here)
# Separate node group: larger instances, auto-scales independently
# ═══════════════════════════════════════════════════════════════════
resource "aws_eks_node_group" "ci" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ci-builds"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.subnet_ids

  instance_types = ["t3a.xlarge", "t3.xlarge", "m5a.xlarge"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 8
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    purpose = "ci-builds"
  }

  tags = merge(var.tags, {
    Name                                            = "${var.cluster_name}-ci-builds"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
  })

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}

# ═══════════════════════════════════════════════════════════════════
# AWS Load Balancer Controller — creates NLB/ALB from K8s Service annotations
# Required for service.beta.kubernetes.io/aws-load-balancer-type: external
# ═══════════════════════════════════════════════════════════════════
resource "aws_iam_policy" "lb_controller" {
  name = "${var.cluster_name}-lb-controller-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "elasticloadbalancing:*",
          "iam:CreateServiceLinkedRole",
          "shield:GetSubscriptionState",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "waf-regional:GetWebACL",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  policy_arn = aws_iam_policy.lb_controller.arn
  role       = aws_iam_role.eks_nodes.name
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  values = [
    yamlencode({
      clusterName = aws_eks_cluster.main.name
      region      = var.region
      vpcId       = var.vpc_id
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
      }
    })
  ]

  depends_on = [aws_eks_node_group.workloads]
}

# ═══════════════════════════════════════════════════════════════════
# Cluster Autoscaler — auto-scales node groups when pods are pending
# Monitors pending pods → increases desired_size → new nodes join cluster
# ═══════════════════════════════════════════════════════════════════
resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${var.cluster_name}-autoscaler-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes",
          "eks:DescribeNodegroup",
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.eks_nodes.name
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = aws_eks_cluster.main.name
      }
      awsRegion = var.region
      extraArgs = {
        "balance-similar-node-groups"   = "true"
        "skip-nodes-with-local-storage" = "false"
        "scale-down-delay-after-add"    = "2m"
        "scale-down-unneeded-time"      = "2m"
      }
    })
  ]

  depends_on = [aws_eks_node_group.workloads]
}
