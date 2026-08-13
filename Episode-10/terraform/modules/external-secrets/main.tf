# ═══════════════════════════════════════════════════════════════════
# External Secrets Operator — Syncs AWS Secrets Manager → K8s Secrets
# EKS Pod Identity grants SecretsManager access (no IMDS in Auto Mode)
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# IAM Role for External Secrets (EKS Pod Identity)
# EKS Auto Mode blocks IMDS — pods need Pod Identity for AWS creds
# ─────────────────────────────────────────
resource "aws_iam_role" "external_secrets" {
  name = "external-secrets-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# SecretsManager permissions — read/write secrets for the operator
resource "aws_iam_role_policy" "external_secrets_sm" {
  name = "external-secrets-sm"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
          "secretsmanager:GetResourcePolicy",
        ]
        Resource = ["*"]
      }
    ]
  })
}

# EKS Pod Identity Association — binds IAM role to external-secrets SA
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}

# ─────────────────────────────────────────
# External Secrets Operator Helm Release
# ─────────────────────────────────────────
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.9.20"

  values = [
    yamlencode({
      installCRDs    = true
      serviceAccount = { create = true, name = "external-secrets" }
    })
  ]

  depends_on = [aws_eks_pod_identity_association.external_secrets]
}

# ClusterSecretStore that connects to AWS Secrets Manager
# Uses Pod Identity (no explicit auth needed — EKS injects creds automatically)
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "aws-secrets-manager" }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
        }
      }
    }
  })
  depends_on = [helm_release.external_secrets]
}

# Creates AWS SM secret with key names pre-filled (you edit values in AWS Console)
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = var.secret_name
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    REDIS_ADDR    = "CHANGE_ME"
    OTEL_ENDPOINT = "CHANGE_ME"
  })

  # Ignore changes — you update values manually in AWS Console
  lifecycle {
    ignore_changes = [secret_string]
  }
}
