# ═══════════════════════════════════════════════════════════════════
# Tracing Module — Jaeger + OTel Collector via ArgoCD (Helm)
# ═══════════════════════════════════════════════════════════════════

# Jaeger — Harness GitOps Application
resource "harness_platform_gitops_applications" "jaeger" {
  identifier = "jaeger"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = var.gitops_repo_id
  agent_id   = var.gitops_agent_id
  name       = "jaeger"

  application {
    metadata {
      name   = "jaeger"
      labels = { "harness.io/envRef" = "production" }
    }
    spec {
      sync_policy { sync_options = ["CreateNamespace=true"] }
      source {
        repo_url        = "https://jaegertracing.github.io/helm-charts"
        chart           = "jaeger"
        target_revision = "3.1.1"
        helm {
          parameters {
            name  = "jaeger.ingress.enabled"
            value = "true"
          }
          parameters {
            name  = "jaeger.ingress.ingressClassName"
            value = "kong"
          }
          parameters {
            name  = "jaeger.ingress.hosts[0]"
            value = "jaeger.${var.domain_name}"
          }
          parameters {
            name  = "provisionDataStore.cassandra"
            value = "false"
          }
          parameters {
            name  = "storage.type"
            value = "badger"
          }
          parameters {
            name  = "spark.enabled"
            value = "false"
          }
          parameters {
            name  = "esIndexCleaner.enabled"
            value = "false"
          }
          parameters {
            name  = "esRollover.enabled"
            value = "false"
          }
          parameters {
            name  = "esLookback.enabled"
            value = "false"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "tracing"
      }
    }
  }
}

# OTel Collector — Harness GitOps Application
resource "harness_platform_gitops_applications" "otel_collector" {
  identifier = "otelcollector"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = var.gitops_repo_id
  agent_id   = var.gitops_agent_id
  name       = "otel-collector"

  application {
    metadata {
      name   = "otel-collector"
      labels = { "harness.io/envRef" = "production" }
    }
    spec {
      sync_policy { sync_options = ["CreateNamespace=true"] }
      source {
        repo_url        = "https://open-telemetry.github.io/opentelemetry-helm-charts"
        chart           = "opentelemetry-collector"
        target_revision = "0.97.1"
        helm {
          parameters {
            name  = "mode"
            value = "deployment"
          }
          parameters {
            name  = "image.repository"
            value = "otel/opentelemetry-collector-contrib"
          }
          parameters {
            name  = "image.tag"
            value = "0.104.0"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "tracing"
      }
    }
  }
}
