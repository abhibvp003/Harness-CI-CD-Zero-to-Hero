# AWS region for Secrets Manager access
variable "aws_region" {
  type = string
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
