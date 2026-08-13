variable "harness_account_id" {
  type = string
}

variable "harness_org_id" {
  type = string
}

variable "harness_project_id" {
  type = string
}

variable "github_username" {
  type = string
}

variable "github_repo" {
  description = "GitHub repository name (for GitOps source)"
  type        = string
}

variable "agent_identifier" {
  type    = string
  default = "ep10gitopsagent"
}

variable "agent_name" {
  type    = string
  default = "ep10-gitops-agent"
}

variable "app_identifier" {
  type    = string
  default = "onlineboutique"
}

variable "app_name" {
  type    = string
  default = "online-boutique"
}

variable "app_path" {
  type    = string
  default = "Episode-10/k8s"
}

variable "app_namespace" {
  type    = string
  default = "online-boutique"
}

variable "service_identifier" {
  type    = string
  default = "online_boutique"
}

variable "domain_name" {
  description = "Domain name injected into Helm chart at ArgoCD sync time (overrides values.yaml placeholder)"
  type        = string
  # Comes from GitHub Actions variable: vars.DOMAIN_NAME
  # ArgoCD uses this to render Ingress host: app.yourdomain.com
}

variable "github_pat" {
  description = "GitHub Personal Access Token (for GitOps PR write access)"
  type        = string
  sensitive   = true
}

variable "github_branch" {
  description = "Git branch to sync from"
  type        = string
}
