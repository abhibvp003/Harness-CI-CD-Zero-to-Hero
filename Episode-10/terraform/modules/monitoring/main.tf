# ═══════════════════════════════════════════════════════════════════
# Monitoring Module — Prometheus + Grafana via ArgoCD (Helm)
# ═══════════════════════════════════════════════════════════════════

# Auto-generate Grafana password and store in AWS SM
resource "random_password" "grafana" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "online-boutique/grafana-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id = aws_secretsmanager_secret.grafana.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.grafana.result
  })
}

# Harness GitOps Application — creates ArgoCD app + shows in Harness UI
resource "harness_platform_gitops_applications" "monitoring" {
  identifier = "monitoring"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = var.gitops_repo_id
  agent_id   = var.gitops_agent_id
  name       = "monitoring"

  application {
    metadata {
      name   = "monitoring"
      labels = { "harness.io/envRef" = "production" }
    }
    spec {
      sync_policy { sync_options = ["CreateNamespace=true", "ServerSideApply=true"] }
      source {
        repo_url        = "https://prometheus-community.github.io/helm-charts"
        chart           = "kube-prometheus-stack"
        target_revision = "62.3.0"
        helm {
          parameters {
            name  = "grafana.adminPassword"
            value = random_password.grafana.result
          }
          parameters {
            name  = "grafana.ingress.hosts[0]"
            value = "grafana.${var.domain_name}"
          }
          parameters {
            name  = "grafana.ingress.enabled"
            value = "true"
          }
          parameters {
            name  = "grafana.ingress.ingressClassName"
            value = "kong"
          }
          parameters {
            name  = "prometheus.prometheusSpec.retention"
            value = "15d"
          }
          parameters {
            name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
            value = "auto-ebs-sc"
          }
          parameters {
            name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
            value = "50Gi"
          }
          parameters {
            name  = "alertmanager.enabled"
            value = "true"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "monitoring"
      }
    }
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
  lifecycle { ignore_changes = all }
}

# Grafana dashboard — Online Boutique Application metrics
resource "kubernetes_config_map" "grafana_dashboard_app" {
  metadata {
    name      = "grafana-dashboard-online-boutique"
    namespace = "monitoring"
    labels    = { grafana_dashboard = "1" }
  }
  depends_on = [kubernetes_namespace.monitoring]
  data = {
    "online-boutique.json" = jsonencode({
      title   = "Online Boutique - Application"
      uid     = "online-boutique-app"
      refresh = "30s"
      time    = { from = "now-1h", to = "now" }
      panels = [
        { title = "Request Rate (req/s)", type = "timeseries", gridPos = { h = 8, w = 12, x = 0, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum(rate(kong_http_requests_total[5m])) by (service)", legendFormat = "{{service}}" }] },
        { title = "Error Rate (%)", type = "timeseries", gridPos = { h = 8, w = 12, x = 12, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum(rate(kong_http_requests_total{status=~\"5..\"}[5m])) / sum(rate(kong_http_requests_total[5m])) * 100", legendFormat = "5xx %" }] },
        { title = "Latency p99 (ms)", type = "timeseries", gridPos = { h = 8, w = 12, x = 0, y = 8 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "histogram_quantile(0.99, sum(rate(kong_latency_bucket{type=\"request\"}[5m])) by (le, service))", legendFormat = "{{service}}" }] },
        { title = "Pod Count", type = "stat", gridPos = { h = 8, w = 12, x = 12, y = 8 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_status_phase{namespace=\"online-boutique\",phase=\"Running\"})", legendFormat = "Running" }] },
      ]
    })
  }
}

# Grafana dashboard — Kong Gateway metrics
resource "kubernetes_config_map" "grafana_dashboard_kong" {
  metadata {
    name      = "grafana-dashboard-kong-gateway"
    namespace = "monitoring"
    labels    = { grafana_dashboard = "1" }
  }
  depends_on = [kubernetes_namespace.monitoring]
  data = {
    "kong-gateway.json" = jsonencode({
      title   = "Kong Gateway"
      uid     = "kong-gateway"
      refresh = "30s"
      time    = { from = "now-1h", to = "now" }
      panels = [
        { title = "Total Requests/sec", type = "stat", gridPos = { h = 4, w = 6, x = 0, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum(rate(kong_http_requests_total[5m]))" }] },
        { title = "Active Connections", type = "stat", gridPos = { h = 4, w = 6, x = 6, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum(kong_nginx_connections_total{state=\"active\"})" }] },
        { title = "5xx Errors/sec", type = "stat", gridPos = { h = 4, w = 6, x = 12, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum(rate(kong_http_requests_total{status=~\"5..\"}[5m]))" }] },
        { title = "Latency by Route", type = "timeseries", gridPos = { h = 8, w = 24, x = 0, y = 4 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "histogram_quantile(0.95, sum(rate(kong_latency_bucket{type=\"request\"}[5m])) by (le, route))", legendFormat = "{{route}}" }] },
      ]
    })
  }
}
