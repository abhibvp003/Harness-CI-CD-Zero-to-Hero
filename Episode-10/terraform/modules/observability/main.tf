# Monitoring — kube-prometheus-stack via ArgoCD
resource "kubernetes_manifest" "argocd_monitoring" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "monitoring", namespace = "gitops" }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://prometheus-community.github.io/helm-charts"
        chart          = "kube-prometheus-stack"
        targetRevision = "62.3.0"
        helm = {
          valuesObject = {
            grafana = {
              enabled       = true
              adminPassword = var.grafana_admin_password
              service       = { type = "ClusterIP" }
              ingress = {
                enabled          = true
                ingressClassName = "alb"
                annotations = {
                  "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
                  "alb.ingress.kubernetes.io/target-type"     = "ip"
                  "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443},{\"HTTP\":80}]"
                  "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
                  "alb.ingress.kubernetes.io/certificate-arn" = "auto"
                  "alb.ingress.kubernetes.io/group.name"      = "ep10-shared-alb"
                }
                hosts = ["grafana.${var.domain_name}"]
              }
            }
            prometheus = {
              prometheusSpec = {
                retention                               = "15d"
                serviceMonitorSelectorNilUsesHelmValues = false
                podMonitorSelectorNilUsesHelmValues     = false
                storageSpec                             = { volumeClaimTemplate = { spec = { storageClassName = "auto-ebs-sc", resources = { requests = { storage = "50Gi" } } } } }
              }
            }
            alertmanager = { enabled = true }
          }
        }
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "monitoring" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true", "ServerSideApply=true"] }
    }
  }
}

# Logging — EFK from Git
resource "kubernetes_manifest" "argocd_logging" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "logging", namespace = "gitops" }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/${var.github_username}/Harness-CI-CD-Zero-to-Hero"
        path           = "Episode-10/k8s/logging"
        targetRevision = "main"
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "logging" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  }
}

# Jaeger — Helm
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
                ingressClassName = "alb"
                annotations = {
                  "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
                  "alb.ingress.kubernetes.io/target-type"     = "ip"
                  "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443},{\"HTTP\":80}]"
                  "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
                  "alb.ingress.kubernetes.io/certificate-arn" = "auto"
                  "alb.ingress.kubernetes.io/group.name"      = "ep10-shared-alb"
                }
                hosts = ["jaeger.${var.domain_name}"]
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

# OTel Collector — Git manifests
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

# Kibana Ingress
resource "kubernetes_ingress_v1" "kibana" {
  metadata {
    name      = "kibana-ingress"
    namespace = "logging"
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\":443},{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
      "alb.ingress.kubernetes.io/certificate-arn" = "auto"
      "alb.ingress.kubernetes.io/group.name"      = "ep10-shared-alb"
    }
  }
  spec {
    rule {
      host = "kibana.${var.domain_name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kibana"
              port { number = 5601 }
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_manifest.argocd_logging]
}
