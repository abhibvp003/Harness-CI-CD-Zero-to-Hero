# Domain name for DNS record management (from GitHub Variable: DOMAIN_NAME)
variable "domain_name" {
  description = "Domain name to manage records for"
  type        = string
}

# AWS region for ExternalDNS deployment (from GitHub Variable: AWS_REGION)
variable "aws_region" {
  description = "AWS region"
  type        = string
}

# EKS cluster name (used for resource naming) (from GitHub Variable: CLUSTER_NAME)
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

# OIDC provider ARN for IRSA trust policy
variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA"
  type        = string
}

# OIDC provider URL (without https://) for IAM condition keys
variable "oidc_provider_url" {
  description = "EKS OIDC provider URL without protocol prefix"
  type        = string
}
