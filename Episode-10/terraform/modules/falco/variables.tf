# Domain name for Falco UI ingress
variable "domain_name" {
  type = string
}

# Harness GitOps (for ArgoCD app registration)
variable "harness_account_id" { type = string }
variable "harness_org_id" { type = string }
variable "harness_project_id" { type = string }
variable "gitops_agent_id" { type = string }
variable "gitops_cluster_id" { type = string }
