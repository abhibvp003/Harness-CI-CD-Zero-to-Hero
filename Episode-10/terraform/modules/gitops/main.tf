# ═══════════════════════════════════════════════════════════════════
# GitOps Module — Official Harness Pattern (from harness-community/gitops-terraform-onboarding)
# Flow: Register Agent → Get Deploy YAML → kubectl apply → Wait → Create Repo → Cluster → App
#Harness API → Terraform data source → /tmp/gitops_agent.yaml → kubectl apply → deleted when runner exits
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

  # Prevent re-registration on re-runs (invalidates server-side token → agent disconnects)
  lifecycle {
    ignore_changes = all
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

# Step 4: Save the Harness-generated YAML to a file (too large for inline heredoc)
resource "local_file" "gitops_agent_yaml" {
  filename = "${path.module}/gitops_agent.yaml"
  content  = data.harness_platform_gitops_agent_deploy_yaml.agent_yaml.yaml
}

# Step 5: Apply the YAML to cluster + wait for agent to connect
resource "null_resource" "install_gitops_agent" {
  triggers = {
    agent_id  = harness_platform_gitops_agent.agent.identifier
    yaml_hash = md5(data.harness_platform_gitops_agent_deploy_yaml.agent_yaml.yaml)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Configure kubectl
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --kubeconfig /tmp/kubeconfig

      # Remove auto-upgrader CronJob from agent YAML (prevents version mismatch + permission denied errors)
      # Uses awk to split multi-doc YAML and skip any document containing "kind: CronJob"
      awk 'BEGIN{doc=""} /^---/{if(doc !~ /kind: CronJob/) print doc; doc="---\n"; next} {doc=doc $0 "\n"} END{if(doc !~ /kind: CronJob/) print doc}' ${local_file.gitops_agent_yaml.filename} > /tmp/gitops_agent_clean.yaml
      # Fallback: if awk produced empty file, use original
      [ -s /tmp/gitops_agent_clean.yaml ] || cp ${local_file.gitops_agent_yaml.filename} /tmp/gitops_agent_clean.yaml

      # Apply the agent YAML without auto-upgrader (installs ArgoCD + agent with correct config)
      KUBECONFIG=/tmp/kubeconfig kubectl apply -f /tmp/gitops_agent_clean.yaml

      # Delete any existing CronJob that may have been installed by a previous deploy
      KUBECONFIG=/tmp/kubeconfig kubectl delete cronjob -n gitops --all --ignore-not-found=true 2>/dev/null || true

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

      # Wait for ArgoCD app-controller to be ready (polls pod status, max 5 min)
      echo "Waiting for ArgoCD app-controller to be ready..."
      for i in $(seq 1 30); do
        READY=$(KUBECONFIG=/tmp/kubeconfig kubectl get pods -n gitops -l app.kubernetes.io/name=argocd-application-controller -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$READY" = "True" ]; then
          echo "ArgoCD app-controller ready! (attempt $i)"
          break
        fi
        echo "Attempt $i/30 — app-controller not ready yet, waiting 10s..."
        sleep 10
      done

      # Wait for Redis HA to be fully ready (all replicas synced — prevents NOREPLICAS error)
      echo "Waiting for Redis HA to be ready..."
      for i in $(seq 1 30); do
        REDIS_READY=$(KUBECONFIG=/tmp/kubeconfig kubectl get pods -n gitops -l app.kubernetes.io/name=argocd-redis-ha -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True")
        REDIS_TOTAL=$(KUBECONFIG=/tmp/kubeconfig kubectl get pods -n gitops -l app.kubernetes.io/name=argocd-redis-ha -o name 2>/dev/null | wc -l)
        if [ "$REDIS_READY" -ge 2 ] 2>/dev/null && [ "$REDIS_TOTAL" -ge 2 ] 2>/dev/null; then
          echo "Redis HA ready! ($REDIS_READY/$REDIS_TOTAL pods)"
          break
        fi
        echo "Attempt $i/30 — Redis HA not ready ($REDIS_READY/$REDIS_TOTAL), waiting 10s..."
        sleep 10
      done

      # Final check: verify agent is responding via Harness API (confirms full readiness)
      echo "Final verification — checking agent responds..."
      for i in $(seq 1 6); do
        RESP=$(curl -s -H "x-api-key: ${var.harness_api_key}" \
          "https://app.harness.io/gateway/gitops/api/v1/agents/${var.agent_identifier}?accountIdentifier=${var.harness_account_id}&orgIdentifier=${var.harness_org_id}&projectIdentifier=${var.harness_project_id}" 2>/dev/null)
        if echo "$RESP" | grep -q '"connected"'; then
          echo "Agent fully operational!"
          break
        fi
        sleep 10
      done
    EOT
  }

  depends_on = [local_file.gitops_agent_yaml]
}

# Step 5-auto: Enable AUTO CREATE project mapping (links GitOps cluster to Harness project)
resource "harness_platform_gitops_app_project_mapping" "project" {
  account_id              = var.harness_account_id
  org_id                  = var.harness_org_id
  project_id              = var.harness_project_id
  agent_id                = var.agent_identifier
  argo_project_name       = "*"
  auto_create_service_env = true
  depends_on              = [null_resource.install_gitops_agent]
}

# Step 5a: Create ArgoCD AppProject (defines what apps can deploy where)
resource "kubectl_manifest" "argocd_default_project" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "online-boutique"
      namespace = "gitops"
    }
    spec = {
      description = "Online Boutique enterprise project"
      sourceRepos = ["*"]
      destinations = [{
        namespace = "*"
        server    = "*"
      }]
      clusterResourceWhitelist = [{
        group = "*"
        kind  = "*"
      }]
    }
  })
  depends_on = [null_resource.install_gitops_agent]
}

# Step 5b: Create GitOps repository
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
    username        = var.github_username # automatic {reads the repo name directly from GitHub} {github action : ${{ github.event.repository.name }}}
    password        = var.github_pat      # github Secrets 
  }

  depends_on = [null_resource.install_gitops_agent]
}


# Step 6: ArgoCD auto-registers in-cluster when agent installs — no manual cluster resource needed
# The cluster "incluster" is created automatically by the deploy YAML (kubectl apply)

# Step 7: Create ArgoCD Application (syncs Helm chart from Git to cluster)
resource "harness_platform_gitops_applications" "app" {
  identifier = var.app_identifier
  account_id = var.harness_account_id
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  cluster_id = var.cluster_identifier
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
            # Overrides "domain" in values.yaml at sync time (GitHub Var → Terraform → ArgoCD → Ingress host)
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

  depends_on = [harness_platform_gitops_repository.repo]
}
