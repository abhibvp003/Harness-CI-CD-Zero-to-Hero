# ═══════════════════════════════════════════════════════════════════
# Logging Module — EFK Stack via ArgoCD (Helm)
# ═══════════════════════════════════════════════════════════════════

# Auto-generate EFK password and store in AWS SM
resource "random_password" "efk" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "efk" {
  name                    = "online-boutique/efk-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "efk" {
  secret_id = aws_secretsmanager_secret.efk.id
  secret_string = jsonencode({
    username = "elastic"
    password = random_password.efk.result
  })
}

# Elasticsearch — Harness GitOps Application
resource "harness_platform_gitops_applications" "elasticsearch" {
  identifier = "elasticsearch"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = var.gitops_repo_id
  agent_id   = var.gitops_agent_id
  name       = "elasticsearch"

  application {
    metadata {
      name   = "elasticsearch"
      labels = { "harness.io/envRef" = "production" }
    }
    spec {
      sync_policy { sync_options = ["CreateNamespace=true"] }
      source {
        repo_url        = "https://helm.elastic.co"
        chart           = "elasticsearch"
        target_revision = "7.17.3"
        helm {
          parameters {
            name  = "replicas"
            value = "1"
          }
          parameters {
            name  = "minimumMasterNodes"
            value = "1"
          }
          parameters {
            name  = "volumeClaimTemplate.resources.requests.storage"
            value = "10Gi"
          }
          parameters {
            name  = "volumeClaimTemplate.storageClassName"
            value = "auto-ebs-sc"
          }
          parameters {
            name  = "extraEnvs[0].name"
            value = "ELASTIC_PASSWORD"
          }
          parameters {
            name  = "extraEnvs[0].value"
            value = random_password.efk.result
          }
          parameters {
            name  = "esConfig.elasticsearch\\.yml"
            value = "xpack.security.enabled: true\nxpack.security.transport.ssl.enabled: false"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "logging"
      }
    }
  }
}

# Kibana — Harness GitOps Application
resource "harness_platform_gitops_applications" "kibana" {
  identifier = "kibana"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = var.gitops_repo_id
  agent_id   = var.gitops_agent_id
  name       = "kibana"

  application {
    metadata {
      name   = "kibana"
      labels = { "harness.io/envRef" = "production" }
    }
    spec {
      sync_policy { sync_options = ["CreateNamespace=true"] }
      source {
        repo_url        = "https://helm.elastic.co"
        chart           = "kibana"
        target_revision = "7.17.3"
        helm {
          parameters {
            name  = "elasticsearchHosts"
            value = "http://elasticsearch-master:9200"
          }
          parameters {
            name  = "extraEnvs[0].name"
            value = "ELASTICSEARCH_USERNAME"
          }
          parameters {
            name  = "extraEnvs[0].value"
            value = "elastic"
          }
          parameters {
            name  = "extraEnvs[1].name"
            value = "ELASTICSEARCH_PASSWORD"
          }
          parameters {
            name  = "extraEnvs[1].value"
            value = random_password.efk.result
          }
          parameters {
            name  = "ingress.enabled"
            value = "true"
          }
          parameters {
            name  = "ingress.className"
            value = "kong"
          }
          parameters {
            name  = "ingress.hosts[0].host"
            value = "kibana.${var.domain_name}"
          }
          parameters {
            name  = "ingress.hosts[0].paths[0].path"
            value = "/"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "logging"
      }
    }
  }

  depends_on = [harness_platform_gitops_applications.elasticsearch]
}

# Fluentd — Harness GitOps Application
resource "harness_platform_gitops_applications" "fluentd" {
  identifier = "fluentd"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = var.gitops_repo_id
  agent_id   = var.gitops_agent_id
  name       = "fluentd"

  application {
    metadata {
      name   = "fluentd"
      labels = { "harness.io/envRef" = "production" }
    }
    spec {
      sync_policy { sync_options = ["CreateNamespace=true"] }
      source {
        repo_url        = "https://fluent.github.io/helm-charts"
        chart           = "fluentd"
        target_revision = "0.5.2"
        helm {
          parameters {
            name  = "kind"
            value = "DaemonSet"
          }
          parameters {
            name  = "env[0].name"
            value = "FLUENT_ELASTICSEARCH_HOST"
          }
          parameters {
            name  = "env[0].value"
            value = "elasticsearch-master.logging.svc.cluster.local"
          }
          parameters {
            name  = "env[1].name"
            value = "FLUENT_ELASTICSEARCH_PORT"
          }
          parameters {
            name  = "env[1].value"
            value = "9200"
          }
          parameters {
            name  = "env[2].name"
            value = "FLUENT_ELASTICSEARCH_USER"
          }
          parameters {
            name  = "env[2].value"
            value = "elastic"
          }
          parameters {
            name  = "env[3].name"
            value = "FLUENT_ELASTICSEARCH_PASSWORD"
          }
          parameters {
            name  = "env[3].value"
            value = random_password.efk.result
          }
          parameters {
            name  = "env[4].name"
            value = "FLUENT_ELASTICSEARCH_SCHEME"
          }
          parameters {
            name  = "env[4].value"
            value = "http"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "logging"
      }
    }
  }

  depends_on = [harness_platform_gitops_applications.elasticsearch]
}
