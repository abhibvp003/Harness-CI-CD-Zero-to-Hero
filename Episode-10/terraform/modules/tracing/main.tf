# ═══════════════════════════════════════════════════════════════════
# Tracing Module — Jaeger + OTel Collector via ArgoCD (Helm)
# Self-contained: registers its own Helm repos + creates Harness apps
# ═══════════════════════════════════════════════════════════════════

# Register Helm repos in Harness GitOps
resource "harness_platform_gitops_repository" "jaeger" {
  identifier = "helm_jaeger"
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  agent_id   = var.gitops_agent_id
  upsert     = true
  repo {
    repo            = "https://jaegertracing.github.io/helm-charts"
    name            = "jaeger"
    type_           = "helm"
    insecure        = true
    connection_type = "HTTPS_ANONYMOUS"
  }
}

resource "harness_platform_gitops_repository" "otel" {
  identifier = "helm_otel"
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  agent_id   = var.gitops_agent_id
  upsert     = true
  repo {
    repo            = "https://open-telemetry.github.io/opentelemetry-helm-charts"
    name            = "opentelemetry"
    type_           = "helm"
    insecure        = true
    connection_type = "HTTPS_ANONYMOUS"
  }
}

# Jaeger — Harness GitOps Application
resource "harness_platform_gitops_applications" "jaeger" {
  identifier = "jaeger"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = harness_platform_gitops_repository.jaeger.identifier
  agent_id   = var.gitops_agent_id
  name       = "jaeger"

  application {
    metadata {
      name   = "jaeger"
      labels = {}
    }
    spec {
      sync_policy {
        automated {
          prune     = true
          self_heal = true
        }
        sync_options = ["CreateNamespace=true"]
      }
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
            name  = "jaeger.ingress.pathType"
            value = "Prefix"
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

  depends_on = [harness_platform_gitops_repository.jaeger]
}

# OTel Collector — Harness GitOps Application
resource "harness_platform_gitops_applications" "otel_collector" {
  identifier = "otelcollector"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = harness_platform_gitops_repository.otel.identifier
  agent_id   = var.gitops_agent_id
  name       = "otel-collector"

  application {
    metadata {
      name   = "otel-collector"
      labels = {}
    }
    spec {
      sync_policy {
        automated {
          prune     = true
          self_heal = true
        }
        sync_options = ["CreateNamespace=true"]
      }
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
          values = <<-EOT
            config:
              receivers:
                otlp:
                  protocols:
                    grpc:
                      endpoint: 0.0.0.0:4317
                    http:
                      endpoint: 0.0.0.0:4318
                zipkin:
                  endpoint: 0.0.0.0:9411
              exporters:
                otlp/jaeger:
                  endpoint: jaeger-collector:4317
                  tls:
                    insecure: true
                debug:
                  verbosity: basic
              processors:
                batch:
                  timeout: 5s
                  send_batch_size: 1024
              service:
                pipelines:
                  traces:
                    receivers: [otlp, zipkin]
                    processors: [batch]
                    exporters: [otlp/jaeger, debug]
                  metrics:
                    receivers: [otlp]
                    processors: [batch]
                    exporters: [debug]
            ports:
              zipkin:
                enabled: true
                containerPort: 9411
                servicePort: 9411
          EOT
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "tracing"
      }
    }
  }

  depends_on = [harness_platform_gitops_repository.otel]
}

# Jaeger Ingress — chart v3.1.1 doesn't create it properly via parameters
resource "kubernetes_namespace" "tracing" {
  metadata { name = "tracing" }
  lifecycle { ignore_changes = all }
}

resource "kubectl_manifest" "jaeger_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "jaeger-query"
      namespace = "tracing"
      annotations = {
        "konghq.com/strip-path" = "false"
      }
    }
    spec = {
      ingressClassName = "kong"
      rules = [{
        host = "jaeger.${var.domain_name}"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "jaeger-query"
                port = { number = 80 }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [harness_platform_gitops_applications.jaeger, kubernetes_namespace.tracing]
}
