# Domain name for DNS record management
variable "domain_name" {
  description = "Domain name to manage records for"
  type        = string
}

# AWS region for ExternalDNS deployment
variable "aws_region" {
  description = "AWS region"
  type        = string
}

# EKS cluster name (used for resource naming)
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
