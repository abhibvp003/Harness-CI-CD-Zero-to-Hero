# AWS region for Secrets Manager access
variable "aws_region" {
  type = string
}

# EKS cluster name (required for Pod Identity Association)
variable "cluster_name" {
  description = "EKS cluster name for Pod Identity binding"
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
