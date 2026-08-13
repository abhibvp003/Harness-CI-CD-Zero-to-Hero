# ═══════════════════════════════════════════════════════════════════
# Episode 10 — Variables (All from GitHub Variables/Secrets)
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# AWS
# ─────────────────────────────────────────

# Used in: provider.tf, EKS module, RDS module, Bastion, ExternalDNS — sets the AWS region for all resources
variable "aws_region" {
  description = "AWS region (set via GitHub Variable: AWS_REGION)"
  type        = string
}

# Used in: EKS module, Bastion, VPC tagging — names the EKS cluster and all related resources
variable "cluster_name" {
  description = "EKS cluster name (set via GitHub Variable: CLUSTER_NAME)"
  type        = string
}

# Used in: EKS module — which Kubernetes version to run (1.31 = latest stable)
variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

# Used in: VPC module — the IP range for the entire network (10.0.0.0/16 = 65k IPs)
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

# Used in: Bastion module — EC2 instance size for the management server
variable "bastion_instance_type" {
  description = "Bastion EC2 instance type"
  type        = string
  default     = "t2.medium"
}

# ─────────────────────────────────────────
# Harness Platform
# ─────────────────────────────────────────

# Used in: Harness provider, GitOps agent, all Harness resources — your Harness account identifier
variable "harness_account_id" {
  description = "Harness Account ID (Account Settings → Overview)"
  type        = string
}

# Used in: Harness provider — authenticates Terraform to create Harness resources (services, envs, connectors)
variable "harness_api_key" {
  description = "Harness Platform API Key (PAT or SAT token)"
  type        = string
  sensitive   = true
}

# Used in: Delegate Helm chart — the token that authenticates the delegate to Harness control plane
variable "harness_delegate_token" {
  description = "Harness Delegate Token (Project Settings → Delegates → Tokens)"
  type        = string
  sensitive   = true
}

# Used in: All Harness resources (service, env, connector, policy) — which org they belong to
variable "harness_org_id" {
  description = "Harness Organization Identifier (set via GitHub Variable: HARNESS_ORG_ID)"
  type        = string
}

# Used in: All Harness resources — which project they belong to (everything scoped inside this project)
variable "harness_project_id" {
  description = "Harness Project Identifier (set via GitHub Variable: HARNESS_PROJECT_ID)"
  type        = string
}

# ─────────────────────────────────────────
# Delegate
# ─────────────────────────────────────────

# Used in: Delegate Helm chart, all connector delegate_selectors — the tag that identifies this delegate
variable "delegate_name" {
  description = "Name of the Kubernetes delegate"
  type        = string
  default     = "eks-k8s-delegate"
}

# Used in: Delegate Helm chart — how many delegate pods to run (2 = HA, one can restart without downtime)
variable "delegate_replicas" {
  description = "Number of delegate replicas (2 for HA — production requirement)"
  type        = number
  default     = 2
}

# Used in: Delegate Helm chart — which delegate Docker image version to pull
variable "delegate_image_tag" {
  description = "Harness delegate image tag"
  type        = string
  default     = "26.07.89707"
}

# ─────────────────────────────────────────
# Networking
# ─────────────────────────────────────────

# Used in: Kong ACM cert lookup, ExternalDNS, Ingress hosts, Grafana/Kibana/Jaeger URLs
variable "domain_name" {
  description = "Custom domain for Ingress (set via GitHub Variable: DOMAIN_NAME)"
  type        = string
  default     = ""
}

# Used in: (reserved for future DNS validation if needed)
variable "hosted_zone_id" {
  description = "Route53 Hosted Zone ID (required only if domain_name is set)"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────
# GitHub / GitOps
# ─────────────────────────────────────────

# Used in: GitOps repo URL, ArgoCD app source — constructs https://github.com/{username}/{repo}
variable "github_username" {
  description = "Your GitHub username (auto-detected from github.repository_owner in workflow)"
  type        = string
}

# Used in: GitOps repo URL, Harness service repoName, ArgoCD app — the repository name
variable "github_repo" {
  description = "GitHub repository name (auto-detected from github.event.repository.name in workflow)"
  type        = string
}

# Used in: GitOps repo credentials — ArgoCD needs write access to create PRs (UpdateReleaseRepo)
variable "github_pat" {
  description = "GitHub Personal Access Token with repo scope (set via GitHub Secret: GH_PAT)"
  type        = string
  sensitive   = true
}

# Used in: GitOps target_revision, Harness service branch, ArgoCD sync — which branch to watch
variable "github_branch" {
  description = "Git branch name (set via GitHub Variable: GIT_BRANCH)"
  type        = string
}

# ─────────────────────────────────────────
# RDS (PostgreSQL)
# ─────────────────────────────────────────

# Used in: RDS module — the database instance size (db.t3.micro = free tier eligible)
variable "rds_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

# Used in: RDS module — the database name created inside PostgreSQL
variable "rds_db_name" {
  description = "Database name"
  type        = string
  default     = "onlineboutique"
}

# Used in: RDS module — the master username for database login
variable "rds_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
}
