# ═══════════════════════════════════════════════════════════════════
# GitOps Module — Official Harness Pattern (from harness-community/gitops-terraform-onboarding)
# Flow: Register Agent → Get Deploy YAML → kubectl apply → Wait → Create Repo → Cluster → App
# ═══════════════════════════════════════════════════════════════════

# Step 1: Create namespace
resource "kubernetes_namespace" "gitops" {
  metadata {
    name   = "gitops"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

# Step 2: Register agent in Harness API (returns agent_token used in deploy YAML)
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

# Step 3: Get the official deploy YAML from Harness (same as "Download YAML" button in UI)
# This YAML has ALL correct values: AGENT_HTTP_TARGET, agentSecret, accountId, etc.
data "harness_platform_gitops_agent_deploy_yaml" "agent_yaml" {
  identifier = harness_platform_gitops_agent.agent.identifier
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  namespace  = "gitops"
}

# Step 4: Save YAML to file and apply with kubectl (official Harness pattern)
resource "null_resource" "install_gitops_agent" {
  triggers = {
    agent_id = harness_platform_gitops_agent.agent.identifier
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Write the Harness-generated YAML to a temp file
      cat <<'YAML' > /tmp/gitops_agent.yaml
      ${data.harness_platform_gitops_agent_deploy_yaml.agent_yaml.yaml}
      YAML

      # Configure kubectl
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --kubeconfig /tmp/kubeconfig

      # Apply the agent YAML (installs ArgoCD + agent with correct config)
      KUBECONFIG=/tmp/kubeconfig kubectl apply -f /tmp/gitops_agent.yaml

      # Wait for agent to connect to Harness (polls every 10s, max 5 min)
      echo "Waiting for GitOps agent to connect..."
      for i in $(seq 1 30); do
        RESP=$(curl -s -H "x-api-key: ${var.harness_api_key}" \
          "https://app.harness.io/gateway/gitops/api/v1/agents/${var.agent_identifier}?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.harness_org_id}&projectIdentifier=${var.harness_project_id}" 2>/dev/null)
        if echo "$RESP" | grep -q '"health"'; then
          echo "Agent connected! (attempt $i)"
          break
        fi
        echo "Attempt $i/30 — waiting 10s..."
        sleep 10
      done
    EOT
  }

  depends_on = [data.harness_platform_gitops_agent_deploy_yaml.agent_yaml]
}

# Step 5: Create GitOps repository (public repo — no credentials needed for read)
resource "harness_platform_gitops_repository" "repo" {
  identifier = "repo"
  account_id = var.harness_account_id
  project_id = var.harness_project_id
  org_id     = var.harness_org_id
  agent_id   = var.agent_identifier
  upsert     = true

  repo {
    repo            = "https://github.com/${var.github_username}/${var.github_repo}"
    name            = var.github_repo
    insecure        = true
    connection_type = "HTTPS"
    username        = var.github_username
    password        = var.github_pat
  }

  depends_on = [null_resource.install_gitops_agent]
}

# Step 6: Register in-cluster as GitOps deploy target
resource "harness_platform_gitops_cluster" "incluster" {
  identifier = "incluster"
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  agent_id   = var.agent_identifier

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

  depends_on = [harness_platform_gitops_repository.repo]
}

# Step 7: Create ArgoCD Application (syncs Helm chart from Git to cluster)
resource "harness_platform_gitops_applications" "app" {
  identifier = var.app_identifier
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = harness_platform_gitops_cluster.incluster.identifier
  repo_id    = harness_platform_gitops_repository.repo.identifier
  agent_id   = var.agent_identifier
  name       = var.app_name

  application {
    metadata {
      name = var.app_name
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

  depends_on = [harness_platform_gitops_cluster.incluster]
}
