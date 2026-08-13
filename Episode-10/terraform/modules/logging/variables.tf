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
