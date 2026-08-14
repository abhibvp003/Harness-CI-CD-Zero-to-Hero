# Domain name for logging dashboard ingress
variable "domain_name" {
  type = string
}

# GitHub username for Git source reference
variable "github_username" {
  type = string
}

# GitHub repository name for values files source
variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

# Git branch to sync values from
variable "github_branch" {
  description = "Git branch for ArgoCD multi-source values"
  type        = string
}

# Harness GitOps identifiers (for app registration in Harness UI)
variable "harness_account_id" { type = string }
variable "harness_org_id" { type = string }
variable "harness_project_id" { type = string }
variable "gitops_agent_id" { type = string }
variable "gitops_repo_id" { type = string }
variable "gitops_cluster_id" { type = string }
