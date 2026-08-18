# ═══════════════════════════════════════════════════════════════════
# Root Outputs
# ═══════════════════════════════════════════════════════════════════

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "bastion_ssm_command" {
  value = "aws ssm start-session --target ${module.bastion.instance_id} --region ${var.aws_region}"
}

output "delegate_name" {
  value = module.delegate.delegate_name
}

output "service_created" {
  value = module.harness_platform.service_identifier
}

output "environments_created" {
  value = [module.harness_platform.production_env_identifier, "development"]
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

output "ci_cache_bucket" {
  value = aws_s3_bucket.ci_cache.bucket
}
