output "agent_identifier" {
  value = harness_platform_gitops_agent.agent.identifier
}

output "cluster_identifier" {
  value = "incluster"
}

output "repo_identifier" {
  value = harness_platform_gitops_repository.repo.identifier
}
