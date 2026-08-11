resource "kubernetes_namespace" "gitops" {
  metadata {
    name   = "gitops"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

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

resource "helm_release" "gitops_agent" {
  name             = "harness-gitops-agent"
  repository       = "https://harness.github.io/gitops-helm/"
  chart            = "gitops-helm"
  namespace        = "gitops"
  create_namespace = false

  values = [
    yamlencode({
      global = { accountId = var.harness_account_id }
      agent = {
        name      = var.agent_name
        accountId = var.harness_account_id
        orgId     = var.harness_org_id
        projectId = var.harness_project_id
      }
      replicaCount = 2
      controller   = { replicas = 2 }
      repoServer = {
        replicas    = 2
        autoscaling = { enabled = true, minReplicas = 2, maxReplicas = 5, targetCPUUtilizationPercentage = 70 }
      }
      server = {
        replicas    = 2
        autoscaling = { enabled = true, minReplicas = 2, maxReplicas = 4, targetCPUUtilizationPercentage = 70 }
      }
      redis = { enabled = true, replicas = 2 }
    })
  ]

  wait       = true
  timeout    = 600
  depends_on = [harness_platform_gitops_agent.agent]
}

resource "harness_platform_gitops_repository" "repo" {
  identifier = "repo"
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
}

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
}

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
        repo_url        = "https://github.com/${var.github_username}/Harness-CI-CD-Zero-to-Hero"
        path            = var.app_path
        target_revision = "main"
      }
      destination {
        server    = "https://kubernetes.default.svc"
        namespace = var.app_namespace
      }
    }
  }

  depends_on = [harness_platform_gitops_cluster.incluster, harness_platform_gitops_repository.repo]
}
