# AWS region for Secrets Manager access (from GitHub Variable: AWS_REGION)
variable "aws_region" {
  type = string
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

# Name of the secret in AWS Secrets Manager
variable "secret_name" {
  type    = string
  default = "online-boutique/app-secrets"
}

# Common tags applied to secret resources
variable "tags" {
  type    = map(string)
  default = {}
}
