variable "domain_name" {
  type = string
}

variable "github_username" {
  type = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_branch" {
  description = "Git branch to sync from"
  type        = string
}
