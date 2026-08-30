# Domain name for tracing dashboard ingress (from GitHub Variable: DOMAIN_NAME)
variable "domain_name" {
  type = string
}

# GitHub username for tracing config access (auto from github.repository_owner)
variable "github_username" {
  type = string
}

# GitHub repository name for tracing source (auto from github.event.repository.name)
variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

# Git branch to sync tracing config from (from GitHub Variable: GIT_BRANCH)
variable "github_branch" {
  description = "Git branch to sync from"
  type        = string
}

# Harness GitOps (for self-contained app registration)
variable "harness_account_id" { type = string } # from GitHub Variable: HARNESS_ACCOUNT_ID
variable "harness_org_id" { type = string }     # from GitHub Variable: HARNESS_ORG_ID
variable "harness_project_id" { type = string } # from GitHub Variable: HARNESS_PROJECT_ID
variable "gitops_agent_id" { type = string }
variable "gitops_cluster_id" { type = string }
