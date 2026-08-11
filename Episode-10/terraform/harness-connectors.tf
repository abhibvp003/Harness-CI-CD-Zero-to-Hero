# ═══════════════════════════════════════════════════════════════════
# Harness Connectors — Created via Terraform (Zero UI Clicks)
# MNC Pattern: All connectors as code, reproducible across clusters
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# Prometheus Connector (for Continuous Verification)
# Points to Prometheus running inside the cluster (deployed by ArgoCD)
# ─────────────────────────────────────────
resource "harness_platform_connector_prometheus" "prometheus" {
  identifier         = "prometheus"
  name               = "prometheus"
  org_id             = var.harness_org_id
  project_id         = var.harness_project_id
  url                = "http://prometheus-server.monitoring.svc.cluster.local:9090"
  delegate_selectors = [var.delegate_name]

  depends_on = [helm_release.harness_delegate]
}

# ─────────────────────────────────────────
# AWS Secrets Manager Connector
# Uses IAM role on delegate (no access keys needed)
# ─────────────────────────────────────────
resource "harness_platform_connector_aws_secret_manager" "aws_sm" {
  identifier         = "aws_secrets_manager"
  name               = "aws-secrets-manager"
  org_id             = var.harness_org_id
  project_id         = var.harness_project_id
  region             = var.aws_region
  secret_name_prefix = "harness/"
  delegate_selectors = [var.delegate_name]

  credentials {
    inherit_from_delegate = true
  }

  depends_on = [helm_release.harness_delegate]
}

# ─────────────────────────────────────────
# Kubernetes Connector (Inherit from Delegate)
# Used for KubernetesDirect CI builds
# ─────────────────────────────────────────
resource "harness_platform_connector_kubernetes" "k8s" {
  identifier = "k8sdelegate"
  name       = "k8s-delegate"
  org_id     = var.harness_org_id
  project_id = var.harness_project_id

  inherit_from_delegate {
    delegate_selectors = [var.delegate_name]
  }

  depends_on = [helm_release.harness_delegate]
}


# ─────────────────────────────────────────
# Harness Monitored Service (for Continuous Verification)
# Maps: online-boutique service + production env → Prometheus health source
# Required for the Verify step in the pipeline
# ─────────────────────────────────────────
resource "harness_platform_monitored_service" "online_boutique" {
  identifier = "online_boutique_production"
  org_id     = var.harness_org_id
  project_id = var.harness_project_id

  request {
    name            = "online-boutique-production"
    type            = "Application"
    service_ref     = harness_platform_service.online_boutique.identifier
    environment_ref = harness_platform_environment.production.identifier

    health_sources {
      name       = "prometheus"
      identifier = "prometheus"
      type       = "Prometheus"
      spec = jsonencode({
        connectorRef = harness_platform_connector_prometheus.prometheus.identifier
        metricDefinitions = [
          {
            identifier              = "error_rate"
            metricName              = "error_rate"
            riskCategory            = "Errors"
            lowerBaselineDeviation  = false
            higherBaselineDeviation = true
            groupName               = "Errors"
            query                   = "sum(rate(http_requests_total{namespace=\"online-boutique\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{namespace=\"online-boutique\"}[5m])) * 100"
            serviceInstanceField    = "pod"
            isManualQuery           = true
          }
        ]
      })
    }
  }

  depends_on = [
    harness_platform_service.online_boutique,
    harness_platform_environment.production,
    harness_platform_connector_prometheus.prometheus,
  ]
}
