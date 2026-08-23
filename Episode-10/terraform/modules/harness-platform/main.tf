# ── Connectors ──

# Connector to query Prometheus metrics for continuous verification
resource "harness_platform_connector_prometheus" "prometheus" {
  identifier         = "prometheus"
  name               = "prometheus"
  org_id             = var.org_id
  project_id         = var.project_id
  url                = "http://monitoring-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
  delegate_selectors = [var.delegate_name]
}

# Elasticsearch connector for CV (created via Harness API — provider doesn't support this resource)
# Password: same auto-generated EFK password stored in AWS SM (online-boutique/efk-password)
# Kibana login: elastic / (password from AWS SM)
# This connector enables log-based verification in the Verify Deployment step
resource "null_resource" "elk_connector" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Step 1: Create Harness secret for ES password (delete first if exists)
      curl -s -X DELETE \
        "https://app.harness.io/gateway/ng/api/v2/secrets/elk_password?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}" 2>/dev/null || true
      sleep 2
      curl -s -X POST \
        "https://app.harness.io/gateway/ng/api/v2/secrets?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" \
        -d '{
          "secret": {
            "type": "SecretText",
            "name": "elk_password",
            "identifier": "elk_password",
            "orgIdentifier": "${var.org_id}",
            "projectIdentifier": "${var.project_id}",
            "spec": {
              "secretManagerIdentifier": "harnessSecretManager",
              "valueType": "Inline",
              "value": "${var.efk_password}"
            }
          }
        }' 2>/dev/null

      sleep 2

      # Step 2: Create ELK connector (delete first if exists)
      curl -s -X DELETE \
        "https://app.harness.io/gateway/ng/api/connectors/elasticsearch?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}" 2>/dev/null || true
      sleep 2
      curl -s -X POST \
        "https://app.harness.io/gateway/ng/api/connectors?accountIdentifier=${var.harness_account_id}" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" \
        -d '{
          "connector": {
            "name": "elasticsearch",
            "identifier": "elasticsearch",
            "orgIdentifier": "${var.org_id}",
            "projectIdentifier": "${var.project_id}",
            "type": "ElasticSearch",
            "spec": {
              "url": "http://elasticsearch-master.logging.svc.cluster.local:9200",
              "delegateSelectors": ["${var.delegate_name}"],
              "authType": "UsernamePassword",
              "username": "elastic",
              "passwordRef": "elk_password"
            }
          }
        }' 2>/dev/null || true
    EOT
  }
  depends_on = [harness_platform_connector_prometheus.prometheus]
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
# Uses Harness API directly (terraform resource returns 400 on some accounts)
resource "null_resource" "opa_policy" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create OPA Policy via API
      curl -s -X POST \
        "https://app.harness.io/gateway/pm/api/v1/policies?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" \
        -d '{
          "identifier": "production_governance",
          "name": "Production Governance",
          "rego": ${jsonencode(var.opa_policy_rego)}
        }' 2>/dev/null || true

      # Create Policy Set via API
      curl -s -X POST \
        "https://app.harness.io/gateway/pm/api/v1/policysets?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}" \
        -H "Content-Type: application/json" \
        -d '{
          "identifier": "production_policy_set",
          "name": "Production Policy Set",
          "action": "onrun",
          "type": "pipeline",
          "enabled": true,
          "policies": [{"identifier": "production_governance", "severity": "error"}]
        }' 2>/dev/null || true
    EOT
  }
}

# ── Harness Variable: CI Cache Bucket (used by RestoreCacheS3/SaveCacheS3 in pipeline) ──
resource "harness_platform_variables" "ci_cache_bucket" {
  identifier = "ci_cache_bucket"
  name       = "ci_cache_bucket"
  org_id     = var.org_id
  project_id = var.project_id
  type       = "String"
  spec {
    value_type  = "FIXED"
    fixed_value = var.ci_cache_bucket
  }
}

# ── Harness Variable: Domain Name (used by OWASP ZAP to scan live app URL) ──
resource "harness_platform_variables" "domain_name" {
  identifier = "domain_name"
  name       = "domain_name"
  org_id     = var.org_id
  project_id = var.project_id
  type       = "String"
  spec {
    value_type  = "FIXED"
    fixed_value = var.domain_name
  }
}

# ── Harness Variable: SonarQube Host URL (bastion IP auto-detected — no manual entry) ──
# Pre-delete if manually created (prevents "already exists" error on first apply)
resource "null_resource" "delete_existing_sonar_var" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      curl -s -X DELETE \
        "https://app.harness.io/gateway/ng/api/variables/sonar_host_url?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.org_id}&projectIdentifier=${var.project_id}" \
        -H "x-api-key: ${var.harness_api_key}" 2>/dev/null || true
    EOT
  }
}

resource "harness_platform_variables" "sonar_host_url" {
  identifier = "sonar_host_url"
  name       = "sonar_host_url"
  org_id     = var.org_id
  project_id = var.project_id
  type       = "String"
  spec {
    value_type  = "FIXED"
    fixed_value = "http://${var.bastion_public_ip}:9000"
  }
  depends_on = [null_resource.delete_existing_sonar_var]
}

# ── GitOps Cluster → Environment Mapping (links cluster to production environment) ──
resource "harness_platform_environment_clusters_mapping" "production" {
  identifier = "production"
  org_id     = var.org_id
  project_id = var.project_id
  env_id     = harness_platform_environment.production.identifier
  clusters {
    identifier       = "incluster"
    name             = "incluster"
    agent_identifier = var.gitops_agent_id
    scope            = "PROJECT"
  }
  depends_on = [harness_platform_environment.production]

  # Ensure cluster mapping is destroyed before the environment
  # (Harness won't delete env if cluster mapping still references it)
  lifecycle {
    create_before_destroy = false
  }
}

resource "harness_platform_environment_clusters_mapping" "development" {
  identifier = "development"
  org_id     = var.org_id
  project_id = var.project_id
  env_id     = harness_platform_environment.development.identifier
  clusters {
    identifier       = "incluster"
    name             = "incluster"
    agent_identifier = var.gitops_agent_id
    scope            = "PROJECT"
  }
  depends_on = [harness_platform_environment.development]

  lifecycle {
    create_before_destroy = false
  }
}

# ── Monitored Service (CV) ──

# Delay between monitored service deletion and service/environment deletion (Harness API eventual consistency)
# On destroy: monitored service + cluster mappings delete first → wait 15s → then service/environment delete
resource "time_sleep" "wait_for_monitored_service_delete" {
  depends_on       = [harness_platform_service.online_boutique, harness_platform_environment.production]
  destroy_duration = "15s"
}

# Monitored service that tracks BOTH metrics AND logs for continuous verification
# ═══════════════════════════════════════════════════════════════════
# WHY BOTH Prometheus + Elasticsearch?
# ─────────────────────────────────────
# Prometheus (Metrics): Detects infrastructure issues
#   → Pod Restarts, CPU spikes, memory leaks, pods not ready
#   → Problem: If pods are Running but the APPLICATION is broken
#     (returning 500s, null responses, logic errors), metrics look healthy!
#
# Elasticsearch (Logs): Detects application-level issues
#   → Error logs, exceptions, stack traces, timeout messages
#   → Catches: App returning errors, DB connection failures,
#     null pointer exceptions, third-party API failures
#   → Even when pods are Running/Ready, logs reveal the real health
#
# Together: Infrastructure health (Prometheus) + Application health (EFK)
#           = Complete verification. Rollback on ANY degradation.
# ═══════════════════════════════════════════════════════════════════
resource "harness_platform_monitored_service" "online_boutique" {
  identifier = "online_boutique_production"
  org_id     = var.org_id
  project_id = var.project_id
  depends_on = [time_sleep.wait_for_monitored_service_delete]


  request {
    name            = "online-boutique-production"
    type            = "Application"
    service_ref     = harness_platform_service.online_boutique.identifier
    environment_ref = harness_platform_environment.production.identifier

    # ── Health Source 1: Prometheus (Metrics — infrastructure health) ──
    health_sources {
      name       = "prometheus"
      identifier = "prometheus"
      type       = "Prometheus"
      spec = jsonencode({
        connectorRef = "prometheus"
        metricDefinitions = [{
          identifier = "pod_restarts"
          metricName = "Pod Restarts"
          riskProfile = {
            riskCategory   = "Errors"
            thresholdTypes = ["ACT_WHEN_HIGHER"]
          }
          analysis = {
            liveMonitoring = {
              enabled = true
            }
            deploymentVerification = {
              enabled                  = true
              serviceInstanceFieldName = "pod"
            }
          }
          query         = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"online-boutique\"}[5m]))"
          groupName     = "Pod Health"
          isManualQuery = true
        }]
        metricPacks = [{
          identifier = "Custom"
        }]
      })
    }

    # ── Health Source 2: Elasticsearch (Logs — application health) ──
    # Queries container logs from the online-boutique namespace
    # Harness ML analyzes log patterns: if new error patterns or error spike
    # detected after deployment - triggers automatic rollback
    health_sources {
      name       = "elasticsearch"
      identifier = "elasticsearch"
      type       = "ElasticSearch"
      version    = "v2"
      spec = jsonencode({
        connectorRef = "elasticsearch"
        queryDefinitions = [
          {
            name       = "Error Logs"
            identifier = "error_logs"
            query      = "kubernetes.namespace_name:online-boutique AND (level:error OR level:ERROR OR severity:ERROR OR log:*error* OR log:*Error* OR log:*exception* OR log:*Exception*)"
            index      = "fluentd-*"
            groupName  = "Logs_Group"
            queryParams = {
              index                = "fluentd-*"
              serviceInstanceField = "kubernetes.pod_name"
              timeStampIdentifier  = "@timestamp"
              timeStampFormat      = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
              messageIdentifier    = "log"
            }
          }
        ]
      })
    }

    # ── Health Source 3: Prometheus (Pod CPU — detects resource spikes after deploy) ──
    # Monitors CPU usage per pod in online-boutique namespace
    # If CPU spikes abnormally after deploy → indicates resource leak → rollback
    health_sources {
      name       = "app-resource-health"
      identifier = "app_resource_health"
      type       = "Prometheus"
      spec = jsonencode({
        connectorRef = "prometheus"
        metricDefinitions = [{
          identifier = "pod_cpu_usage"
          metricName = "Pod CPU Usage"
          riskProfile = {
            riskCategory   = "Performance"
            thresholdTypes = ["ACT_WHEN_HIGHER"]
          }
          analysis = {
            liveMonitoring = {
              enabled = true
            }
            deploymentVerification = {
              enabled                  = true
              serviceInstanceFieldName = "pod"
            }
          }
          query         = "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"online-boutique\",container!=\"\"}[5m]))"
          groupName     = "Resource Health"
          isManualQuery = true
        }]
        metricPacks = [{
          identifier = "Custom"
        }]
      })
    }
  }
}
