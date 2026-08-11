output "agent_identifier" {
  value = harness_platform_gitops_agent.agent.identifier
}

output "cluster_identifier" {
  value = harness_platform_gitops_cluster.incluster.identifier
}

output "repo_identifier" {
  value = harness_platform_gitops_repository.repo.identifier
}
