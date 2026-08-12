# Installs External Secrets Operator via Helm to sync secrets into K8s
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
}

# ClusterSecretStore that connects to AWS Secrets Manager
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "aws-secrets-manager" }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = { name = "external-secrets", namespace = "external-secrets" }
            }
          }
        }
      }
    }
  }
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
    REDIS_ADDR       = "CHANGE_ME"
    OTEL_ENDPOINT    = "CHANGE_ME"
    ANY_OTHER_SECRET = "CHANGE_ME"
  })

  # Ignore changes — you update values manually in AWS Console
  lifecycle {
    ignore_changes = [secret_string]
  }
}
