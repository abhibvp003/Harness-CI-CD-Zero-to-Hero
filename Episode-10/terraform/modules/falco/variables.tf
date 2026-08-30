# Domain name for Falco UI ingress (from GitHub Variable: DOMAIN_NAME)
variable "domain_name" {
  type = string
}

# Harness GitOps (for ArgoCD app registration)
variable "harness_account_id" { type = string } # from GitHub Variable: HARNESS_ACCOUNT_ID
variable "harness_org_id" { type = string }     # from GitHub Variable: HARNESS_ORG_ID
variable "harness_project_id" { type = string } # from GitHub Variable: HARNESS_PROJECT_ID
variable "gitops_agent_id" { type = string }
variable "gitops_cluster_id" { type = string }
