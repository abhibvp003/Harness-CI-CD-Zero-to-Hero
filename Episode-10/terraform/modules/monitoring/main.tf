# ═══════════════════════════════════════════════════════════════════
# Monitoring Module — Prometheus + Grafana via ArgoCD (Helm)
# Self-contained: registers its own Helm repo + creates Harness app
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

# Register Helm repo in Harness GitOps
resource "harness_platform_gitops_repository" "prometheus" {
  identifier = "helm_prometheus"
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  agent_id   = var.gitops_agent_id
  upsert     = true
  repo {
    repo            = "https://prometheus-community.github.io/helm-charts"
    name            = "prometheus-community"
    type_           = "helm"
    insecure        = true
    connection_type = "HTTPS_ANONYMOUS"
  }
}

# Harness GitOps Application — creates ArgoCD app + shows in Harness UI
resource "harness_platform_gitops_applications" "monitoring" {
  identifier = "monitoring"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = harness_platform_gitops_repository.prometheus.identifier
  agent_id   = var.gitops_agent_id
  name       = "monitoring"

  application {
    metadata {
      name   = "monitoring"
      labels = {}
    }
    spec {
      sync_policy {
        automated {
          prune     = true
          self_heal = true
        }
        sync_options = ["CreateNamespace=true", "ServerSideApply=true"]
      }
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

  depends_on = [harness_platform_gitops_repository.prometheus]
}

resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
  lifecycle { ignore_changes = all }
}

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
        { title = "Running Pods", type = "stat", gridPos = { h = 4, w = 6, x = 0, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_status_phase{namespace=\"online-boutique\",phase=\"Running\"})", legendFormat = "Running" }] },
        { title = "Failed Pods", type = "stat", gridPos = { h = 4, w = 6, x = 6, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_status_phase{namespace=\"online-boutique\",phase=\"Failed\"}) or vector(0)", legendFormat = "Failed" }], fieldConfig = { defaults = { color = { mode = "fixed", fixedColor = "red" } } } },
        { title = "Pending Pods", type = "stat", gridPos = { h = 4, w = 6, x = 12, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_status_phase{namespace=\"online-boutique\",phase=\"Pending\"}) or vector(0)", legendFormat = "Pending" }], fieldConfig = { defaults = { color = { mode = "fixed", fixedColor = "yellow" } } } },
        { title = "CrashLoopBackOff Pods", type = "stat", gridPos = { h = 4, w = 6, x = 18, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_container_status_waiting_reason{namespace=\"online-boutique\",reason=\"CrashLoopBackOff\"}) or vector(0)", legendFormat = "CrashLoop" }], fieldConfig = { defaults = { color = { mode = "fixed", fixedColor = "red" } } } },
        { title = "Pod Restarts (last 5 min)", type = "timeseries", gridPos = { h = 8, w = 12, x = 0, y = 4 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"online-boutique\"}[5m])) > 0", legendFormat = "{{pod}}" }] },
        { title = "CPU Usage per Pod", type = "timeseries", gridPos = { h = 8, w = 12, x = 12, y = 4 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"online-boutique\",container!=\"\"}[5m]))", legendFormat = "{{pod}}" }] },
        { title = "Memory Usage per Pod (MB)", type = "timeseries", gridPos = { h = 8, w = 12, x = 0, y = 12 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (container_memory_working_set_bytes{namespace=\"online-boutique\",container!=\"\"}) / 1024 / 1024", legendFormat = "{{pod}}" }] },
        { title = "OOMKilled Events", type = "stat", gridPos = { h = 4, w = 6, x = 12, y = 12 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_container_status_last_terminated_reason{namespace=\"online-boutique\",reason=\"OOMKilled\"}) or vector(0)", legendFormat = "OOMKilled" }], fieldConfig = { defaults = { color = { mode = "fixed", fixedColor = "red" } } } },
        { title = "ImagePullBackOff Pods", type = "stat", gridPos = { h = 4, w = 6, x = 18, y = 12 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_container_status_waiting_reason{namespace=\"online-boutique\",reason=\"ImagePullBackOff\"}) or vector(0)", legendFormat = "ImagePull" }], fieldConfig = { defaults = { color = { mode = "fixed", fixedColor = "orange" } } } },
        { title = "Network Received (bytes/s)", type = "timeseries", gridPos = { h = 8, w = 12, x = 0, y = 16 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (rate(container_network_receive_bytes_total{namespace=\"online-boutique\"}[5m]))", legendFormat = "{{pod}}" }] },
        { title = "Network Transmitted (bytes/s)", type = "timeseries", gridPos = { h = 8, w = 12, x = 12, y = 16 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (rate(container_network_transmit_bytes_total{namespace=\"online-boutique\"}[5m]))", legendFormat = "{{pod}}" }] },
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
        { title = "Kong Pod CPU", type = "timeseries", gridPos = { h = 8, w = 12, x = 0, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"kong\",container!=\"\"}[5m]))", legendFormat = "{{pod}}" }] },
        { title = "Kong Pod Memory (MB)", type = "timeseries", gridPos = { h = 8, w = 12, x = 12, y = 0 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (container_memory_working_set_bytes{namespace=\"kong\",container!=\"\"}) / 1024 / 1024", legendFormat = "{{pod}}" }] },
        { title = "Kong Pods Running", type = "stat", gridPos = { h = 4, w = 6, x = 0, y = 8 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "count(kube_pod_status_phase{namespace=\"kong\",phase=\"Running\"})", legendFormat = "Running" }] },
        { title = "Kong Pod Restarts", type = "timeseries", gridPos = { h = 8, w = 18, x = 6, y = 8 }, datasource = { type = "prometheus", uid = "prometheus" }, targets = [{ expr = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"kong\"}[5m]))", legendFormat = "{{pod}}" }] },
      ]
    })
  }
}
