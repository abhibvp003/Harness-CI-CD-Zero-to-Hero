# Domain name for tracing dashboard ingress
variable "domain_name" {
  type = string
}

# GitHub username for tracing config access
variable "github_username" {
  type = string
}

# GitHub repository name for tracing source
variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

# Git branch to sync tracing config from
variable "github_branch" {
  description = "Git branch to sync from"
  type        = string
}
