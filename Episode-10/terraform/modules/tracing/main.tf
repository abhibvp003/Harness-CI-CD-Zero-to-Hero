# ═══════════════════════════════════════════════════════════════════
# Tracing Module — Jaeger (Helm) + OTel Collector (Git manifests)
# Shows service-to-service request flow with timing per hop
# ═══════════════════════════════════════════════════════════════════

# Jaeger — Helm chart via ArgoCD (stores + visualizes traces)
resource "kubernetes_manifest" "argocd_jaeger" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "jaeger", namespace = "gitops" }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://jaegertracing.github.io/helm-charts"
        chart          = "jaeger"
        targetRevision = "3.1.1"
        helm = {
          valuesObject = {
            provisionDataStore = { cassandra = false }
            allInOne = {
              enabled = true
              tag     = "1.58"
              ingress = {
                enabled          = true
                ingressClassName = "kong"
                annotations      = { "konghq.com/strip-path" = "false" }
                hosts            = ["jaeger.${var.domain_name}"]
              }
            }
            storage   = { type = "badger" }
            collector = { enabled = false }
            query     = { enabled = false }
          }
        }
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "tracing" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  }
}

# OTel Collector — raw manifests from Git (custom pipeline config)
resource "kubernetes_manifest" "argocd_otel" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "otel-collector", namespace = "gitops" }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/${var.github_username}/Harness-CI-CD-Zero-to-Hero"
        path           = "Episode-10/k8s/tracing"
        targetRevision = "main"
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "tracing" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  }
}
