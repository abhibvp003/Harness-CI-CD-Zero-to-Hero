# ═══════════════════════════════════════════════════════════════════
# External Secrets Operator (ESO) — MNC Standard for GitOps + AWS SM
#
# WHY:
#   - ArgoCD can't resolve Harness <+secrets.getValue()>
#   - GitOps manifests are in Git — can't put secrets in Git
#   - ESO pulls secrets from AWS Secrets Manager → creates K8s Secrets
#   - Pods reference K8s Secrets normally (envFrom, valueFrom)
#   - Secrets auto-rotate (ESO polls AWS SM every 1h)
#
# FLOW:
#   AWS Secrets Manager → ESO → Kubernetes Secret → Pod env vars
#
# NO secrets in Git. NO Harness runtime resolution needed.
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# Install External Secrets Operator (Helm)
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
      installCRDs = true
      serviceAccount = {
        create = true
        name   = "external-secrets"
      }
    })
  ]

  depends_on = [aws_eks_cluster.main]
}

# ─────────────────────────────────────────
# ClusterSecretStore — Connects ESO to AWS Secrets Manager
# Uses EKS node IAM role (no access keys needed)
# ─────────────────────────────────────────
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

# ─────────────────────────────────────────
# AWS Secrets Manager — Terraform creates the SECRET (empty container)
# YOU add/update secret VALUES directly in AWS Console
# Terraform manages the name, YOU manage the content
#
# Go to: AWS Console → Secrets Manager → "online-boutique/app-secrets"
# Click "Set secret value" → Add your key-value pairs:
#   REDIS_ADDR=redis-cart:6379
#   DB_PASSWORD=yourpassword
#   API_KEY=your-api-key
#   etc.
#
# ESO pulls whatever you put there automatically every 1 hour
# ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "online-boutique/app-secrets"
  recovery_window_in_days = 0

  tags = {
    Application = "online-boutique"
    ManagedBy   = "terraform"
    Episode     = "10"
  }
}
