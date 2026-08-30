# Harness organization ID for resource scoping (from GitHub Variable: HARNESS_ORG_ID)
variable "org_id" {
  type = string
}

# Harness project ID for resource ownership (from GitHub Variable: HARNESS_PROJECT_ID)
variable "project_id" {
  type = string
}

# Name of the delegate connector reference
variable "delegate_name" {
  type = string
}

# AWS region for connector configuration (from GitHub Variable: AWS_REGION)
variable "aws_region" {
  type = string
}

# Domain name for service endpoint configuration (from GitHub Variable: DOMAIN_NAME)
variable "domain_name" {
  type = string
}

# GitHub username for source repo access (auto from github.repository_owner)
variable "github_username" {
  type = string
}

# OPA policy rego content for governance
variable "opa_policy_rego" {
  description = "OPA policy rego content"
  type        = string
}

# GitHub repository name for pipeline source (auto from github.event.repository.name)
variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

# Git branch to fetch manifests from (from GitHub Variable: GIT_BRANCH)
variable "github_branch" {
  description = "Git branch to fetch manifests from"
  type        = string
}

# S3 bucket name for CI build cache
variable "ci_cache_bucket" {
  type = string
}

# Bastion public IP (for SonarQube URL variable)
variable "bastion_public_ip" {
  type = string
}

# Harness account ID (for API calls) (from GitHub Variable: HARNESS_ACCOUNT_ID)
variable "harness_account_id" {
  type = string
}

# Harness API key (for API calls to delete existing variables) (from GitHub Secret: HARNESS_API_KEY)
variable "harness_api_key" {
  type      = string
  sensitive = true
}

# GitOps agent identifier for cluster-environment mapping
variable "gitops_agent_id" {
  type = string
}

# EFK password for Elasticsearch connector (auto-generated, passed from logging module)
variable "efk_password" {
  type      = string
  sensitive = true
}
