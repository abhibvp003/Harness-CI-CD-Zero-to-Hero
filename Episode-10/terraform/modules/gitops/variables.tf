# Harness account ID for GitOps agent setup
variable "harness_account_id" {
  type = string
}

# Harness organization ID for project scoping
variable "harness_org_id" {
  type = string
}

# Harness project ID for resource ownership
variable "harness_project_id" {
  type = string
}

# GitHub username for repo access
variable "github_username" {
  type = string
}

# GitHub repository name for GitOps source
variable "github_repo" {
  description = "GitHub repository name (for GitOps source)"
  type        = string
}

# Identifier for the GitOps agent resource
variable "agent_identifier" {
  type    = string
  default = "ep10gitopsagent"
}

# Display name for the GitOps agent
variable "agent_name" {
  type    = string
  default = "ep10-gitops-agent"
}

# Identifier for the ArgoCD application resource
variable "app_identifier" {
  type    = string
  default = "onlineboutique"
}

# Display name for the ArgoCD application
variable "app_name" {
  type    = string
  default = "online-boutique"
}

# Path to Kubernetes manifests in the repo
variable "app_path" {
  type    = string
  default = "Episode-10/k8s"
}

# Kubernetes namespace for app deployment
variable "app_namespace" {
  type    = string
  default = "online-boutique"
}

# Harness service identifier for deployment
variable "service_identifier" {
  type    = string
  default = "online_boutique"
}

# Domain injected into Helm chart at sync time
variable "domain_name" {
  description = "Domain name injected into Helm chart at ArgoCD sync time (overrides values.yaml placeholder)"
  type        = string
  # Comes from GitHub Actions variable: vars.DOMAIN_NAME
  # ArgoCD uses this to render Ingress host: app.yourdomain.com
}

# GitHub PAT for GitOps repo write access
variable "github_pat" {
  description = "GitHub Personal Access Token (for GitOps PR write access)"
  type        = string
  sensitive   = true
}

# Git branch to sync manifests from
variable "github_branch" {
  description = "Git branch to sync from"
  type        = string
}

# Harness API key for agent health check polling
variable "harness_api_key" {
  type      = string
  sensitive = true
}

# EKS cluster name (for kubectl auth in agent install)
variable "cluster_name" {
  type = string
}

# AWS region (for kubectl auth in agent install)
variable "aws_region" {
  type = string
}

# ArgoCD cluster identifier (auto-registered by deploy YAML as "incluster")
variable "cluster_identifier" {
  type    = string
  default = "incluster"
}
