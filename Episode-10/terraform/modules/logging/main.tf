# ═══════════════════════════════════════════════════════════════════
# Logging Module — EFK Stack via ArgoCD (Helm + Git values)
# ═══════════════════════════════════════════════════════════════════

# Auto-generate EFK password and store in AWS SM
resource "random_password" "efk" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "efk" {
  name                    = "online-boutique/efk-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "efk" {
  secret_id = aws_secretsmanager_secret.efk.id
  secret_string = jsonencode({
    username = "elastic"
    password = random_password.efk.result
  })
}

# Elasticsearch — helm.elastic.co + values from Git
resource "kubectl_manifest" "argocd_elasticsearch" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "elasticsearch", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      sources = [
        {
          repoURL        = "https://github.com/${var.github_username}/${var.github_repo}"
          targetRevision = var.github_branch
          ref            = "values"
        },
        {
          repoURL        = "https://helm.elastic.co"
          chart          = "elasticsearch"
          targetRevision = "8.5.1"
          helm = {
            valueFiles = ["$values/Episode-10/k8s/logging/elasticsearch-values.yaml"]
            parameters = [
              { name = "secret.password", value = random_password.efk.result },
              { name = "extraEnvs[0].value", value = random_password.efk.result },
            ]
          }
        }
      ]
      destination = { server = "https://kubernetes.default.svc", namespace = "logging" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  })
}

# Kibana — helm.elastic.co + values from Git
resource "kubectl_manifest" "argocd_kibana" {
  depends_on = [kubectl_manifest.argocd_elasticsearch]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "kibana", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      sources = [
        {
          repoURL        = "https://github.com/${var.github_username}/${var.github_repo}"
          targetRevision = var.github_branch
          ref            = "values"
        },
        {
          repoURL        = "https://helm.elastic.co"
          chart          = "kibana"
          targetRevision = "8.5.1"
          helm = {
            valueFiles = ["$values/Episode-10/k8s/logging/kibana-values.yaml"]
            parameters = [
              { name = "extraEnvs[1].value", value = random_password.efk.result },
              { name = "ingress.hosts[0].host", value = "kibana.${var.domain_name}" },
            ]
          }
        }
      ]
      destination = { server = "https://kubernetes.default.svc", namespace = "logging" }
      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true", "Replace=true"]
      }
    }
  })
}

# Fluentd — fluent.github.io + values from Git
resource "kubectl_manifest" "argocd_fluentd" {
  depends_on = [kubectl_manifest.argocd_elasticsearch]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "fluentd", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      sources = [
        {
          repoURL        = "https://github.com/${var.github_username}/${var.github_repo}"
          targetRevision = var.github_branch
          ref            = "values"
        },
        {
          repoURL        = "https://fluent.github.io/helm-charts"
          chart          = "fluentd"
          targetRevision = "0.5.2"
          helm = {
            valueFiles = ["$values/Episode-10/k8s/logging/fluentd-values.yaml"]
            parameters = [
              { name = "env[3].value", value = random_password.efk.result },
            ]
          }
        }
      ]
      destination = { server = "https://kubernetes.default.svc", namespace = "logging" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  })
}
