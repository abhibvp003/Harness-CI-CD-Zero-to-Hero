variable "domain_name" {
  type = string
}

variable "github_username" {
  type = string
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}
