variable "org_id" {
  type = string
}

variable "project_id" {
  type = string
}

variable "delegate_name" {
  type = string
}

variable "aws_region" {
  type = string
}

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
