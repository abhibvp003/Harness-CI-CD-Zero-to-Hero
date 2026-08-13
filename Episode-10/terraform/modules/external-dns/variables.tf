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

# EKS cluster name (required for Pod Identity Association)
variable "cluster_name" {
  description = "EKS cluster name for Pod Identity binding"
  type        = string
}
