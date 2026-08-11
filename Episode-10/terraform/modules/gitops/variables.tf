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
