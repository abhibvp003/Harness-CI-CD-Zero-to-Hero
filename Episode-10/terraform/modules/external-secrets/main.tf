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

resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = var.secret_name
  recovery_window_in_days = 0
  tags                    = var.tags
}
