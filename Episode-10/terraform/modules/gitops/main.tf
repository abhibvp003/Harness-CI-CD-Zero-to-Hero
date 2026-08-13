# Creates the gitops namespace where ArgoCD agent will live
resource "kubernetes_namespace" "gitops" {
  metadata {
    name   = "gitops"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

# Registers a Harness GitOps agent for ArgoCD-based deployments
resource "harness_platform_gitops_agent" "agent" {
  identifier = var.agent_identifier
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  name       = var.agent_name
  type       = "MANAGED_ARGO_PROVIDER"

  metadata {
    namespace         = "gitops"
    high_availability = true
  }

  depends_on = [kubernetes_namespace.gitops]
}

# Deploys the Harness GitOps agent into the cluster via Helm
resource "helm_release" "gitops_agent" {
  name             = "harness-gitops-agent"
  repository       = "https://harness.github.io/gitops-helm/"
  chart            = "gitops-helm"
  namespace        = "gitops"
  create_namespace = false
  atomic           = false # Chart bug: agent needs ConfigMap patch — atomic would uninstall before patch runs
  cleanup_on_fail  = true  # Clean up failed resources
  values = [
    yamlencode({
      global = {
        accountId = var.harness_account_id
      }
      harness = {
        identity = {
          accountIdentifier = var.harness_account_id
          orgIdentifier     = var.harness_org_id
          projectIdentifier = var.harness_project_id
          agentIdentifier   = var.agent_identifier
        }
        secrets = {
          agentSecret = harness_platform_gitops_agent.agent.agent_token
        }
        gitopsServerHost = "https://app.harness.io/prod1/gitops"
      }
      http = {
        agentHttpTarget = "https://app.harness.io/gitops"
      }
      configMap = {
        AGENT_HTTP_TARGET = "https://app.harness.io/gitops"
      }
      agent = {
        harnessName = var.agent_name
        httpTarget  = "https://app.harness.io/gitops"
        image = {
          repository = "docker.io/harness/gitops-agent"
          tag        = "v0.124.0"
        }
        replicas = 2
        autoscaling = {
          enabled          = true
          highAvailability = true
        }
      }
      upgrader = {
        enabled = true
        image   = "docker.io/harness/upgrader:latest"
      }
      argocdHarnessPlugin = { enabled = true }
      "argo-cd" = {
        enabled = true
        crds = {
          install = true
          keep    = true
        }
        "redis-ha" = { enabled = false }
        configs = {
          cm = { "cluster.inClusterEnabled" = true }
        }
        controller = {
          resources = {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { cpu = "1", memory = "2Gi" }
          }
        }
        repoServer = {
          replicas = 2
          resources = {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { cpu = "1", memory = "2Gi" }
          }
        }
        server = {
          replicas = 2
        }
      }
      "redis-ha" = { enabled = false }
      redis = {
        enabled = true
        image = {
          repository = "docker.io/harness/redis"
          tag        = "7.4.8"
        }
      }
    })
  ]

  set {
    name  = "agent.httpTarget"
    value = "https://app.harness.io/gitops"
  }

  wait       = false # Agent starts after ConfigMap patch below
  timeout    = 900
  depends_on = [harness_platform_gitops_agent.agent]
}

# Chart v1.2.8 bug workaround: set AGENT_HTTP_TARGET directly in ConfigMap (native Terraform, no shell)
resource "kubernetes_config_map_v1_data" "agent_http_target" {
  metadata {
    name      = "gitops-agent"
    namespace = "gitops"
  }
  data = {
    AGENT_HTTP_TARGET = "https://app.harness.io/gitops"
  }
  force      = true
  depends_on = [helm_release.gitops_agent]
}

# Restart agent deployment to pick up patched ConfigMap (triggers rolling restart — no downtime)
resource "kubectl_manifest" "restart_gitops_agent" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "gitops-agent"
      namespace = "gitops"
      annotations = {
        "kubectl.kubernetes.io/restartedAt" = timestamp()
      }
    }
    spec = {
      template = {
        metadata = {
          annotations = {
            "kubectl.kubernetes.io/restartedAt" = timestamp()
          }
        }
      }
    }
  })
  force_new  = true
  depends_on = [kubernetes_config_map_v1_data.agent_http_target]
}

# Connects the GitHub repository as a source for GitOps syncs (needs PAT for PR write access)
resource "harness_platform_gitops_repository" "repo" {
  identifier = "repo"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  agent_id   = harness_platform_gitops_agent.agent.identifier

  repo {
    repo            = "https://github.com/${var.github_username}/${var.github_repo}"
    name            = var.github_repo
    type_           = "git"
    connection_type = "HTTPS"
    username        = var.github_username # automatic {reads the repo name directly from GitHub} {github action : ${{ github.event.repository.name }}}
    password        = var.github_pat      # github Secrets 
  }

  depends_on = [helm_release.gitops_agent]
}

# Registers the in-cluster Kubernetes as a GitOps deploy target
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
        tls_client_config { insecure = true }
        cluster_connection_type = "IN_CLUSTER"
      }
    }
  }

  depends_on = [helm_release.gitops_agent]
}

# Creates the ArgoCD application that deploys our app from Git
resource "harness_platform_gitops_applications" "app" {
  identifier = var.app_identifier
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = harness_platform_gitops_cluster.incluster.identifier
  repo_id    = harness_platform_gitops_repository.repo.identifier
  agent_id   = harness_platform_gitops_agent.agent.identifier
  name       = var.app_name

  application {
    metadata {
      labels = {
        "harness.io/envRef"     = "production"
        "harness.io/serviceRef" = var.service_identifier
      }
    }
    spec {
      sync_policy { sync_options = ["CreateNamespace=true"] }
      source {
        repo_url        = "https://github.com/${var.github_username}/${var.github_repo}"
        path            = var.app_path
        target_revision = var.github_branch
        helm {
          # Overrides "domain" in values.yaml at sync time (GitHub Var → Terraform → ArgoCD → Ingress host)
          parameters {
            name  = "domain"
            value = var.domain_name
          }
        }
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = var.app_namespace
      }
    }
  }

  depends_on = [harness_platform_gitops_cluster.incluster, harness_platform_gitops_repository.repo]
}
