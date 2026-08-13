# ═══════════════════════════════════════════════════════════════════
# Episode 10 — Terraform Providers
# SELF-CONTAINED: Creates EKS + Delegate + Monitoring + Harness resources
# One terraform apply = EVERYTHING (no dependency on infra.yml)
# ═══════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    harness = {
      source  = "harness/harness"
      version = "~> 0.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {}
}

# ═══════════════════════════════════════════════════════════════════
# AWS Provider
# ═══════════════════════════════════════════════════════════════════
provider "aws" {
  region = var.aws_region
}

# ═══════════════════════════════════════════════════════════════════
# Kubernetes Provider (connects AFTER EKS is created)
# ═══════════════════════════════════════════════════════════════════
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

# ═══════════════════════════════════════════════════════════════════
# Helm Provider (installs charts on EKS)
# ═══════════════════════════════════════════════════════════════════
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}

# ═══════════════════════════════════════════════════════════════════
# Kubectl Provider (applies manifests WITHOUT plan-time API connection)
# ═══════════════════════════════════════════════════════════════════
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

# ═══════════════════════════════════════════════════════════════════
# Harness Provider (creates Services, Environments, Pipelines)
# ═══════════════════════════════════════════════════════════════════
provider "harness" {
  endpoint         = "https://app.harness.io/gateway"
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}
