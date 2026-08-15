# ═══════════════════════════════════════════════════════════════════
# Logging Module — EFK Stack via ArgoCD (Helm)
# Self-contained: registers its own Helm repos + creates Harness apps
# ═══════════════════════════════════════════════════════════════════

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

# Register Helm repos in Harness GitOps
resource "harness_platform_gitops_repository" "elastic" {
  identifier = "helm_elastic"
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  agent_id   = var.gitops_agent_id
  upsert     = true
  repo {
    repo            = "https://helm.elastic.co"
    name            = "elastic"
    type_           = "helm"
    insecure        = true
    connection_type = "HTTPS_ANONYMOUS"
  }
}

resource "harness_platform_gitops_repository" "fluent" {
  identifier = "helm_fluent"
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  agent_id   = var.gitops_agent_id
  upsert     = true
  repo {
    repo            = "https://fluent.github.io/helm-charts"
    name            = "fluent"
    type_           = "helm"
    insecure        = true
    connection_type = "HTTPS_ANONYMOUS"
  }
}

# Elasticsearch — Harness GitOps Application
resource "harness_platform_gitops_applications" "elasticsearch" {
  identifier = "elasticsearch"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = harness_platform_gitops_repository.elastic.identifier
  agent_id   = var.gitops_agent_id
  name       = "elasticsearch"

  application {
    metadata {
      name   = "elasticsearch"
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
            name  = "resources.requests.cpu"
            value = "250m"
          }
          parameters {
            name  = "resources.requests.memory"
            value = "512Mi"
          }
          parameters {
            name  = "resources.limits.cpu"
            value = "500m"
          }
          parameters {
            name  = "resources.limits.memory"
            value = "1Gi"
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
            value = "xpack.security.enabled: true\nxpack.license.self_generated.type: trial\nxpack.security.transport.ssl.enabled: false\n"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "logging"
      }
    }
  }

  depends_on = [harness_platform_gitops_repository.elastic]
}

# Kibana — Harness GitOps Application
resource "harness_platform_gitops_applications" "kibana" {
  identifier = "kibana"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = harness_platform_gitops_repository.elastic.identifier
  agent_id   = var.gitops_agent_id
  name       = "kibana"

  application {
    metadata {
      name   = "kibana"
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
  repo_id    = harness_platform_gitops_repository.fluent.identifier
  agent_id   = var.gitops_agent_id
  name       = "fluentd"

  application {
    metadata {
      name   = "fluentd"
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
        repo_url        = "https://fluent.github.io/helm-charts"
        chart           = "fluentd"
        target_revision = "0.5.2"
        helm {
          parameters {
            name  = "kind"
            value = "DaemonSet"
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
