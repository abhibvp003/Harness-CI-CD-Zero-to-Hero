# Harness organization ID for resource scoping
variable "org_id" {
  type = string
}

# Harness project ID for resource ownership
variable "project_id" {
  type = string
}

# Name of the delegate connector reference
variable "delegate_name" {
  type = string
}

# AWS region for connector configuration
variable "aws_region" {
  type = string
}

# Domain name for service endpoint configuration
variable "domain_name" {
  type = string
}

# GitHub username for source repo access
variable "github_username" {
  type = string
}

# OPA policy rego content for governance
variable "opa_policy_rego" {
  description = "OPA policy rego content"
  type        = string
}

# GitHub repository name for pipeline source
variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

# Git branch to fetch manifests from
variable "github_branch" {
  description = "Git branch to fetch manifests from"
  type        = string
}

# S3 bucket name for CI build cache
variable "ci_cache_bucket" {
  type = string
}
