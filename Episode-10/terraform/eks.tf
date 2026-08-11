# ═══════════════════════════════════════════════════════════════════
# Amazon EKS Cluster — AUTO MODE + HA (No node groups to manage!)
# Production: KMS encryption, audit logs, public+private endpoints
# Same exact pattern as kubernetes/terraform/eks.tf
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# IAM Role for EKS Cluster
# ─────────────────────────────────────────
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

resource "aws_iam_role_policy_attachment" "cluster_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
  ])

  policy_arn = each.value
  role       = aws_iam_role.eks_cluster.name
}

# ─────────────────────────────────────────
# IAM Role for EKS Auto Mode Nodes
# ─────────────────────────────────────────
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

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
  ])

  policy_arn = each.value
  role       = aws_iam_role.eks_nodes.name
}

# ECR full access for CI builds (create repos + push images from KubernetesDirect)
resource "aws_iam_role_policy_attachment" "node_ecr_full" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
  role       = aws_iam_role.eks_nodes.name
}

# ─────────────────────────────────────────
# Security Group for EKS Cluster
# ─────────────────────────────────────────
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-eks-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

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

  tags = { Name = "${var.cluster_name}-eks-sg" }
}

# ─────────────────────────────────────────
# KMS Key for Secrets Encryption
# ─────────────────────────────────────────
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "${var.cluster_name}-eks-kms" }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ─────────────────────────────────────────
# EKS Cluster (Auto Mode — HA, no managed node groups)
# ─────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.private_1.id,
      aws_subnet.private_2.id,
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
    ]
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Auto Mode: Compute (replaces managed node groups + Karpenter)
  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.eks_nodes.arn
  }

  # Auto Mode: Networking (replaces VPC CNI addon + AWS LB Controller)
  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  # Auto Mode: Storage (replaces EBS CSI driver addon)
  storage_config {
    block_storage {
      enabled = true
    }
  }

  # Envelope encryption for Kubernetes secrets
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  # Audit logging (production requirement)
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policies,
    aws_iam_role_policy_attachment.node_policies,
  ]

  tags = { Name = var.cluster_name }
}

# ─────────────────────────────────────────
# CloudWatch Log Group for EKS
# ─────────────────────────────────────────
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7
  tags              = { Name = "${var.cluster_name}-logs" }
}

# ─────────────────────────────────────────
# StorageClass (EKS Auto Mode needs this explicitly)
# ─────────────────────────────────────────
resource "kubernetes_storage_class" "ebs" {
  metadata {
    name = "auto-ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.eks.amazonaws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_cluster.main]
}
