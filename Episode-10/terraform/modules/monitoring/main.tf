# ═══════════════════════════════════════════════════════════════════
# Monitoring Module — Prometheus + Grafana via ArgoCD (Helm + Git values)
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

# kube-prometheus-stack — prometheus-community.github.io + values from Git
resource "kubectl_manifest" "argocd_monitoring" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "monitoring", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      sources = [
        {
          repoURL        = "https://github.com/${var.github_username}/${var.github_repo}"
          targetRevision = var.github_branch
          ref            = "values"
        },
        {
          repoURL        = "https://prometheus-community.github.io/helm-charts"
          chart          = "kube-prometheus-stack"
          targetRevision = "62.3.0"
          helm = {
            valueFiles = ["$values/Episode-10/k8s/monitoring/kube-prometheus-stack-values.yaml"]
            parameters = [
              { name = "grafana.adminPassword", value = random_password.grafana.result },
              { name = "grafana.ingress.hosts[0]", value = "grafana.${var.domain_name}" },
            ]
          }
        }
      ]
      destination = { server = "https://kubernetes.default.svc", namespace = "monitoring" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true", "ServerSideApply=true"] }
    }
  })
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
