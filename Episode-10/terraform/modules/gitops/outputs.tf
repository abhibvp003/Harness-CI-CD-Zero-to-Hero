output "agent_identifier" {
  value = harness_platform_gitops_agent.agent.identifier
}

output "cluster_identifier" {
  value = var.cluster_identifier
}

output "repo_identifier" {
  value = harness_platform_gitops_repository.repo.identifier
}

output "harness_account_id" {
  value = var.harness_account_id
}

output "harness_org_id" {
  value = var.harness_org_id
}

output "harness_project_id" {
  value = var.harness_project_id
}

output "service_identifier" {
  value = var.service_identifier
}
