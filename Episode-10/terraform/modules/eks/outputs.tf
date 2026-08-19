output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_role_name" {
  value = aws_iam_role.eks_nodes.name
}

output "node_role_arn" {
  value = aws_iam_role.eks_nodes.arn
}

# OIDC provider ARN for IRSA trust policies in other modules
output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

# OIDC provider URL (without https://) for IAM condition keys
output "oidc_provider_url" {
  value = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
