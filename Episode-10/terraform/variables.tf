# ═══════════════════════════════════════════════════════════════════
# Episode 10 — Variables
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# AWS
# ─────────────────────────────────────────
variable "aws_region" {
  description = "AWS region (set via GitHub Variable: AWS_REGION)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (set via GitHub Variable: CLUSTER_NAME)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "bastion_instance_type" {
  description = "Bastion EC2 instance type"
  type        = string
  default     = "t2.medium"
}

# ─────────────────────────────────────────
# Harness Platform
# ─────────────────────────────────────────
variable "harness_account_id" {
  description = "Harness Account ID (Account Settings → Overview)"
  type        = string
}

variable "harness_api_key" {
  description = "Harness Platform API Key (PAT or SAT token)"
  type        = string
  sensitive   = true
}

variable "harness_delegate_token" {
  description = "Harness Delegate Token (Project Settings → Delegates → Tokens)"
  type        = string
  sensitive   = true
}

variable "harness_org_id" {
  description = "Harness Organization Identifier (set via GitHub Variable: HARNESS_ORG_ID)"
  type        = string
}

variable "harness_project_id" {
  description = "Harness Project Identifier (set via GitHub Variable: HARNESS_PROJECT_ID)"
  type        = string
}

# ─────────────────────────────────────────
# Delegate
# ─────────────────────────────────────────
variable "delegate_name" {
  description = "Name of the Kubernetes delegate"
  type        = string
  default     = "eks-k8s-delegate"
}

variable "delegate_replicas" {
  description = "Number of delegate replicas (2 for HA — production requirement)"
  type        = number
  default     = 2
}

variable "delegate_image_tag" {
  description = "Harness delegate image tag"
  type        = string
  default     = "26.07.89707"
}

# ─────────────────────────────────────────
# Networking (Optional — for custom domain)
# ─────────────────────────────────────────
variable "domain_name" {
  description = "Custom domain for ALB Ingress (optional, leave empty to skip DNS/TLS)"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 Hosted Zone ID (required only if domain_name is set)"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────
# GitOps
# ─────────────────────────────────────────
variable "github_username" {
  description = "Your GitHub username (for GitOps repo URL)"
  type        = string
}

# ─────────────────────────────────────────
# RDS (PostgreSQL)
# ─────────────────────────────────────────
variable "rds_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_db_name" {
  description = "Database name"
  type        = string
  default     = "onlineboutique"
}

variable "rds_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
}

# ─────────────────────────────────────────
# GitHub Repository
# ─────────────────────────────────────────
variable "github_repo" {
  description = "GitHub repository name (set via GitHub Variable: GITHUB_REPO)"
  type        = string
}

variable "github_pat" {
  description = "GitHub Personal Access Token (for GitOps repo write — set via GitHub Secret: GITHUB_PAT)"
  type        = string
  sensitive   = true
}

variable "github_branch" {
  description = "Git branch name (set via GitHub Variable: GITHUB_BRANCH)"
  type        = string
}
