# ═══════════════════════════════════════════════════════════════════
# Outputs — Summary of everything created
# ═══════════════════════════════════════════════════════════════════

output "eks_cluster_name" {
  description = "EKS Cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "bastion_public_ip" {
  description = "Bastion server public IP"
  value       = aws_instance.bastion.public_ip
}

output "bastion_ssm_command" {
  description = "Connect to bastion via SSM (no key needed)"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}

output "delegate_name" {
  description = "Harness delegate name"
  value       = var.delegate_name
}

output "service_created" {
  description = "Harness service created"
  value       = harness_platform_service.online_boutique.name
}

output "environments_created" {
  description = "Harness environments created"
  value       = [harness_platform_environment.production.name, harness_platform_environment.development.name]
}

output "prometheus_connector_id" {
  description = "Harness Prometheus connector ID"
  value       = harness_platform_connector_prometheus.prometheus.identifier
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}
