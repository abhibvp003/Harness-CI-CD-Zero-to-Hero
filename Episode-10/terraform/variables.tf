# ═══════════════════════════════════════════════════════════════════
# Episode 10 — Variables
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# AWS
# ─────────────────────────────────────────
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name (created by this Terraform)"
  type        = string
  default     = "ep10-enterprise-cluster"
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
  description = "Harness Organization Identifier"
  type        = string
  default     = "default"
}

variable "harness_project_id" {
  description = "Harness Project Identifier"
  type        = string
  default     = "HarnessCICDZerotoHero"
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
  default     = "24.04.83502"
}

# ─────────────────────────────────────────
# Monitoring
# ─────────────────────────────────────────
variable "grafana_admin_password" {
  description = "Grafana admin password (used in ArgoCD monitoring app)"
  type        = string
  default     = "admin123"
  sensitive   = true
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
