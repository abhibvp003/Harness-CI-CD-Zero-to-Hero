# ═══════════════════════════════════════════════════════════════════
# Falco Module — Runtime Security Monitoring via ArgoCD (Helm)
# Detects suspicious behavior in running containers (shell exec, privilege escalation, etc.)
# UI: falcosidekick-ui with login (password stored in AWS Secrets Manager)
# ═══════════════════════════════════════════════════════════════════

terraform {
  required_providers {
    harness = {
      source = "harness/harness"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# Auto-generate Falco UI password and store in AWS SM
resource "random_password" "falco" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "falco" {
  name                    = "online-boutique/falco-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "falco" {
  secret_id = aws_secretsmanager_secret.falco.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.falco.result
  })
}

# Register Falco Helm repo in Harness GitOps
resource "harness_platform_gitops_repository" "falco" {
  identifier = "helm_falco"
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  agent_id   = var.gitops_agent_id
  upsert     = true
  repo {
    repo            = "https://falcosecurity.github.io/charts"
    name            = "falcosecurity"
    type_           = "helm"
    insecure        = true
    connection_type = "HTTPS_ANONYMOUS"
  }
}

# Falco — Harness GitOps Application (DaemonSet — runs on every node)
resource "harness_platform_gitops_applications" "falco" {
  identifier = "falco"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.gitops_cluster_id
  repo_id    = harness_platform_gitops_repository.falco.identifier
  agent_id   = var.gitops_agent_id
  name       = "falco"

  application {
    metadata {
      name   = "falco"
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
        repo_url        = "https://falcosecurity.github.io/charts"
        chart           = "falco"
        target_revision = "4.16.1"
        helm {
          parameters {
            name  = "falcosidekick.enabled"
            value = "true"
          }
          parameters {
            name  = "falcosidekick.webui.enabled"
            value = "true"
          }
          parameters {
            name  = "falcosidekick.webui.user"
            value = "admin:${random_password.falco.result}"
          }
          parameters {
            name  = "falcosidekick.webui.ingress.enabled"
            value = "true"
          }
          parameters {
            name  = "falcosidekick.webui.ingress.ingressClassName"
            value = "kong"
          }
          parameters {
            name  = "falcosidekick.webui.ingress.hosts[0].host"
            value = "falco.${var.domain_name}"
          }
          parameters {
            name  = "falcosidekick.webui.ingress.hosts[0].paths[0].path"
            value = "/"
          }
          parameters {
            name  = "driver.kind"
            value = "modern_ebpf"
          }
          parameters {
            name  = "collectors.kubernetes.enabled"
            value = "true"
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "falco"
      }
    }
  }

  depends_on = [harness_platform_gitops_repository.falco]
}

# Namespace for Falco
resource "kubernetes_namespace" "falco" {
  metadata { name = "falco" }
  lifecycle { ignore_changes = all }
}
