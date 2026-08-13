# ═══════════════════════════════════════════════════════════════════
# Tracing Module — Jaeger + OTel Collector via ArgoCD (Helm + Git values)
# ═══════════════════════════════════════════════════════════════════

# Jaeger — jaegertracing.github.io + values from Git
resource "kubectl_manifest" "argocd_jaeger" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "jaeger", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      sources = [
        {
          repoURL        = "https://github.com/${var.github_username}/${var.github_repo}"
          targetRevision = var.github_branch
          ref            = "values"
        },
        {
          repoURL        = "https://jaegertracing.github.io/helm-charts"
          chart          = "jaeger"
          targetRevision = "3.1.1"
          helm = {
            valueFiles = ["$values/Episode-10/k8s/tracing-helm/jaeger-values.yaml"]
            parameters = [
              { name = "jaeger.ingress.hosts[0]", value = "jaeger.${var.domain_name}" },
            ]
          }
        }
      ]
      destination = { server = "https://kubernetes.default.svc", namespace = "tracing" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  })
}

# OTel Collector — open-telemetry.github.io + values from Git
resource "kubectl_manifest" "argocd_otel" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "otel-collector", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      sources = [
        {
          repoURL        = "https://github.com/${var.github_username}/${var.github_repo}"
          targetRevision = var.github_branch
          ref            = "values"
        },
        {
          repoURL        = "https://open-telemetry.github.io/opentelemetry-helm-charts"
          chart          = "opentelemetry-collector"
          targetRevision = "0.97.1"
          helm = {
            valueFiles = ["$values/Episode-10/k8s/tracing-helm/otel-collector-values.yaml"]
          }
        }
      ]
      destination = { server = "https://kubernetes.default.svc", namespace = "tracing" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  })
}
