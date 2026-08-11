# ═══════════════════════════════════════════════════════════════════
# GitOps — Harness GitOps Agent + Repository + Cluster + Application
# MNC Pattern: Agent installed via Helm (only exception to ArgoCD rule)
# Everything else ArgoCD manages from Git
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# GitOps Agent Namespace
# ─────────────────────────────────────────
resource "kubernetes_namespace" "gitops" {
  metadata {
    name = "gitops"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "purpose"                      = "harness-gitops-agent"
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# ─────────────────────────────────────────
# Harness GitOps Agent (registered in Harness Platform)
# ─────────────────────────────────────────
resource "harness_platform_gitops_agent" "agent" {
  identifier = "ep10gitopsagent"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id

  name = "ep10-gitops-agent"
  type = "MANAGED_ARGO_PROVIDER"

  metadata {
    namespace         = "gitops"
    high_availability = true
  }

  depends_on = [kubernetes_namespace.gitops, helm_release.harness_delegate]
}

# ─────────────────────────────────────────
# GitOps Agent Install (Helm — ArgoCD components in cluster)
# HA: 2 replicas for agent + redis
# ─────────────────────────────────────────
resource "helm_release" "gitops_agent" {
  name             = "harness-gitops-agent"
  repository       = "https://harness.github.io/gitops-helm/"
  chart            = "gitops-helm"
  namespace        = "gitops"
  create_namespace = false

  values = [
    yamlencode({
      global = {
        accountId = var.harness_account_id
      }
      agent = {
        name      = "ep10-gitops-agent"
        accountId = var.harness_account_id
        orgId     = var.harness_org_id
        projectId = var.harness_project_id
      }

      # High Availability — multiple replicas
      replicaCount = 2

      # ArgoCD Application Controller — HA
      controller = {
        replicas = 2
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
      }

      # ArgoCD Repo Server — HA
      repoServer = {
        replicas = 2
        autoscaling = {
          enabled                        = true
          minReplicas                    = 2
          maxReplicas                    = 5
          targetCPUUtilizationPercentage = 70
        }
        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      # ArgoCD Server — HA
      server = {
        replicas = 2
        autoscaling = {
          enabled                        = true
          minReplicas                    = 2
          maxReplicas                    = 4
          targetCPUUtilizationPercentage = 70
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      # Redis — HA
      redis = {
        enabled  = true
        replicas = 2
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
    })
  ]

  wait    = true
  timeout = 600

  depends_on = [kubernetes_namespace.gitops, harness_platform_gitops_agent.agent]
}

# ─────────────────────────────────────────
# GitOps Repository (your GitHub repo)
# ─────────────────────────────────────────
resource "harness_platform_gitops_repository" "repo" {
  identifier = "ep10repo"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  agent_id   = harness_platform_gitops_agent.agent.identifier

  repo {
    repo            = "https://github.com/${var.github_username}/Harness-CI-CD-Zero-to-Hero"
    name            = "Harness-CI-CD-Zero-to-Hero"
    type_           = "git"
    connection_type = "HTTPS"
  }

  depends_on = [harness_platform_gitops_agent.agent]
}

# ─────────────────────────────────────────
# GitOps Cluster (in-cluster — same EKS)
# ─────────────────────────────────────────
resource "harness_platform_gitops_cluster" "incluster" {
  identifier = "incluster"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  agent_id   = harness_platform_gitops_agent.agent.identifier

  request {
    upsert = true
    cluster {
      server = "https://kubernetes.default.svc"
      name   = "in-cluster"
      config {
        tls_client_config {
          insecure = true
        }
        cluster_connection_type = "IN_CLUSTER"
      }
    }
  }

  depends_on = [harness_platform_gitops_agent.agent]
}

# ─────────────────────────────────────────
# GitOps Application (Online Boutique — auto-syncs from Git)
# Points to Episode-10/k8s/ Helm chart folder
# ArgoCD renders templates + syncs to cluster
# ─────────────────────────────────────────
resource "harness_platform_gitops_applications" "online_boutique" {
  identifier = "onlineboutique"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = harness_platform_gitops_cluster.incluster.identifier
  repo_id    = harness_platform_gitops_repository.repo.identifier
  agent_id   = harness_platform_gitops_agent.agent.identifier

  name = "online-boutique"

  application {
    metadata {
      labels = {
        "harness.io/envRef"     = "production"
        "harness.io/serviceRef" = "online_boutique"
      }
    }
    spec {
      sync_policy {
        sync_options = ["CreateNamespace=true"]
      }
      source {
        repo_url        = "https://github.com/${var.github_username}/Harness-CI-CD-Zero-to-Hero"
        path            = "Episode-10/k8s"
        target_revision = "main"
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = "online-boutique"
      }
    }
  }

  depends_on = [
    harness_platform_gitops_cluster.incluster,
    harness_platform_gitops_repository.repo,
  ]
}
