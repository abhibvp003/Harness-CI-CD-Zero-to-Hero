# ── Connectors ──

# Connector to query Prometheus metrics for continuous verification
resource "harness_platform_connector_prometheus" "prometheus" {
  identifier         = "prometheus"
  name               = "prometheus"
  org_id             = var.org_id
  project_id         = var.project_id
  url                = "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
  delegate_selectors = [var.delegate_name]
}

# Kubernetes connector that uses the delegate to talk to the cluster
resource "harness_platform_connector_kubernetes" "k8s" {
  identifier = "k8sdelegate"
  name       = "k8s-delegate"
  org_id     = var.org_id
  project_id = var.project_id
  inherit_from_delegate { delegate_selectors = [var.delegate_name] }
}

# ── Service ──

# Defines the online-boutique microservice in Harness CD
resource "harness_platform_service" "online_boutique" {
  identifier = "online_boutique"
  name       = "online-boutique"
  org_id     = var.org_id
  project_id = var.project_id

  yaml = <<-YAML
    service:
      name: online-boutique
      identifier: online_boutique
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
      serviceDefinition:
        type: Kubernetes
        spec:
          manifests:
            - manifest:
                identifier: release_repo
                type: ReleaseRepo
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: account.Github
                      gitFetchType: Branch
                      repoName: ${var.github_repo}
                      branch: ${var.github_branch}
                      paths:
                        - Episode-10/k8s/values.yaml
          artifacts:
            primary:
              primaryArtifactRef: ecr_frontend
              sources:
                - identifier: ecr_frontend
                  type: Ecr
                  spec:
                    connectorRef: account.aws_account
                    region: ${var.aws_region}
                    imagePath: frontend
                    tag: <+input>
  YAML
}

# ── Environments ──

# Production environment where verified releases get deployed
resource "harness_platform_environment" "production" {
  identifier = "production"
  name       = "production"
  org_id     = var.org_id
  project_id = var.project_id
  type       = "Production"
  yaml       = <<-YAML
    environment:
      name: production
      identifier: production
      type: Production
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
  YAML
}

# Development environment for testing before production
resource "harness_platform_environment" "development" {
  identifier = "development"
  name       = "development"
  org_id     = var.org_id
  project_id = var.project_id
  type       = "PreProduction"
  yaml       = <<-YAML
    environment:
      name: development
      identifier: development
      type: PreProduction
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
  YAML
}

# ── OPA Policy ──

# OPA policy that enforces governance rules on production deploys
resource "harness_platform_policy" "production_governance" {
  identifier = "production_governance"
  name       = "Production Governance"
  org_id     = var.org_id
  project_id = var.project_id
  rego       = var.opa_policy_rego
}

# Policy set that runs the governance check on pipeline execution
resource "harness_platform_policyset" "production" {
  identifier = "production_policy_set"
  name       = "Production Policy Set"
  org_id     = var.org_id
  project_id = var.project_id
  action     = "onrun"
  type       = "pipeline"
  enabled    = true
  policies {
    identifier = harness_platform_policy.production_governance.identifier
    severity   = "error"
  }
}

# ── Monitored Service (CV) ──

# Monitored service that tracks error rate for continuous verification
resource "harness_platform_monitored_service" "online_boutique" {
  identifier = "online_boutique_production"
  org_id     = var.org_id
  project_id = var.project_id

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
        metricDefinitions = [{
          identifier              = "error_rate"
          metricName              = "error_rate"
          riskCategory            = "Errors"
          higherBaselineDeviation = true
          groupName               = "Errors"
          query                   = "sum(rate(http_requests_total{namespace=\"online-boutique\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{namespace=\"online-boutique\"}[5m])) * 100"
          serviceInstanceField    = "pod"
          isManualQuery           = true
          analysis = {
            deploymentVerification = {
              enabled                  = true
              serviceInstanceFieldName = "pod"
            }
            liveMonitoring = {
              enabled = true
            }
            riskProfile = {
              riskCategory   = "Errors"
              thresholdTypes = ["ACT_WHEN_HIGHER"]
            }
          }
        }]
      })
    }
  }
}
