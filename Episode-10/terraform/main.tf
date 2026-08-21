# ═══════════════════════════════════════════════════════════════════
# ROOT MODULE — Orchestrates all infrastructure modules
# One `terraform apply` creates the entire enterprise platform
# ═══════════════════════════════════════════════════════════════════

locals {
  common_tags = {
    Project   = "online-boutique"
    Episode   = "10"
    ManagedBy = "terraform"
  }

  microservices = [
    "frontend", "cartservice", "checkoutservice", "productcatalogservice",
    "currencyservice", "emailservice", "paymentservice",
    "recommendationservice", "shippingservice", "adservice", "loadgenerator",
    "cache"
  ]
}

data "aws_availability_zones" "available" {}

# ── VPC ──
module "vpc" {
  source             = "./modules/vpc"
  vpc_cidr           = var.vpc_cidr
  cluster_name       = var.cluster_name
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  tags               = local.common_tags
}

# ── EKS ──
module "eks" {
  source             = "./modules/eks"
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  subnet_ids         = module.vpc.all_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  region             = var.aws_region
  tags               = local.common_tags
}

# ── StorageClass ──
resource "kubernetes_storage_class" "ebs" {
  metadata {
    name        = "auto-ebs-sc"
    annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters             = { type = "gp3", encrypted = "true" }
  depends_on             = [module.eks]
}

# ── Bastion ──
module "bastion" {
  source           = "./modules/bastion"
  cluster_name     = var.cluster_name
  instance_type    = var.bastion_instance_type
  subnet_id        = module.vpc.public_subnet_ids[1]
  vpc_id           = module.vpc.vpc_id
  eks_cluster_name = module.eks.cluster_name
  aws_region       = var.aws_region
  tags             = local.common_tags
}

# ── ECR ──
module "ecr" {
  source           = "./modules/ecr"
  repository_names = local.microservices
  tags             = local.common_tags
}

# ── S3 Cache Bucket (CI build cache — Go modules, npm packages, Gradle deps) ── {ep10-enterprise-cluster-ci-cache-713939171080}
resource "aws_s3_bucket" "ci_cache" {
  bucket        = "${var.cluster_name}-ci-cache-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = merge(local.common_tags, { Name = "${var.cluster_name}-ci-cache" })
}

resource "aws_s3_bucket_lifecycle_configuration" "ci_cache" {
  bucket = aws_s3_bucket.ci_cache.id
  rule {
    id     = "expire-old-cache"
    status = "Enabled"
    filter {}
    expiration { days = 14 }
  }
}

# ── RDS ──
module "rds" {
  source         = "./modules/rds"
  cluster_name   = var.cluster_name
  vpc_id         = module.vpc.vpc_id
  vpc_cidr       = var.vpc_cidr
  subnet_ids     = module.vpc.private_subnet_ids
  instance_class = var.rds_instance_class
  db_name        = var.rds_db_name
  db_username    = var.rds_username
  secret_prefix  = "online-boutique"
  tags           = local.common_tags
}

# ── Delegate ──
module "delegate" {
  source           = "./modules/delegate"
  account_id       = var.harness_account_id
  delegate_token   = var.harness_delegate_token
  delegate_name    = var.delegate_name
  replicas         = var.delegate_replicas
  image_tag        = var.delegate_image_tag
  eks_cluster_name = module.eks.cluster_name
  depends_on       = [kubernetes_storage_class.ebs]
}

# ── Kong Gateway (API Gateway + Ingress Controller) ──
module "kong_gateway" {
  source      = "./modules/kong-gateway"
  domain_name = var.domain_name
  depends_on  = [module.eks, module.external_secrets]
}

# ── ExternalDNS (Auto-creates Route53 records from Ingress) ──
module "external_dns" {
  source            = "./modules/external-dns"
  domain_name       = var.domain_name
  aws_region        = var.aws_region
  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  depends_on        = [module.kong_gateway]
}

# ── External Secrets Operator ──
module "external_secrets" {
  source            = "./modules/external-secrets"
  aws_region        = var.aws_region
  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  secret_name       = "online-boutique/app-secrets"
  tags              = local.common_tags
  depends_on        = [module.eks]
}

# ── GitOps Agent ──
module "gitops" {
  source             = "./modules/gitops"
  harness_account_id = var.harness_account_id
  harness_org_id     = var.harness_org_id
  harness_project_id = var.harness_project_id
  github_username    = var.github_username
  github_repo        = var.github_repo
  github_pat         = var.github_pat
  github_branch      = var.github_branch
  harness_api_key    = var.harness_api_key
  cluster_name       = var.cluster_name
  aws_region         = var.aws_region
  domain_name        = var.domain_name # Injected into ArgoCD Application helm.parameters (overrides values.yaml placeholder)
  agent_identifier   = "ep10gitopsagent"
  agent_name         = "ep10-gitops-agent"
  app_identifier     = "onlineboutique"
  app_name           = "online-boutique"
  app_path           = "Episode-10/k8s"
  app_namespace      = "online-boutique"
  service_identifier = "online_boutique"
  depends_on         = [module.delegate]
}

# ── Harness Platform Resources ──
module "harness_platform" {
  source             = "./modules/harness-platform"
  org_id             = var.harness_org_id
  project_id         = var.harness_project_id
  delegate_name      = var.delegate_name
  aws_region         = var.aws_region
  domain_name        = var.domain_name
  github_username    = var.github_username
  github_repo        = var.github_repo
  github_branch      = var.github_branch
  ci_cache_bucket    = aws_s3_bucket.ci_cache.bucket
  bastion_public_ip  = module.bastion.public_ip
  harness_account_id = var.harness_account_id
  harness_api_key    = var.harness_api_key
  opa_policy_rego    = file("${path.module}/../policies/production-governance.rego")
  gitops_agent_id    = module.gitops.agent_identifier
  depends_on         = [module.delegate, module.gitops]
}

# ── Monitoring (Prometheus + Grafana) ──
module "monitoring" {
  source             = "./modules/monitoring"
  domain_name        = var.domain_name
  github_username    = var.github_username
  github_repo        = var.github_repo
  github_branch      = var.github_branch
  harness_account_id = var.harness_account_id
  harness_org_id     = var.harness_org_id
  harness_project_id = var.harness_project_id
  gitops_agent_id    = module.gitops.agent_identifier
  gitops_cluster_id  = module.gitops.cluster_identifier
  depends_on         = [module.gitops, module.external_secrets]
}

# ── Logging (EFK — Elasticsearch + Fluentd + Kibana) ──
module "logging" {
  source             = "./modules/logging"
  domain_name        = var.domain_name
  github_username    = var.github_username
  github_repo        = var.github_repo
  github_branch      = var.github_branch
  harness_account_id = var.harness_account_id
  harness_org_id     = var.harness_org_id
  harness_project_id = var.harness_project_id
  gitops_agent_id    = module.gitops.agent_identifier
  gitops_cluster_id  = module.gitops.cluster_identifier
  depends_on         = [module.gitops, module.external_secrets]
}

# ── Tracing (Jaeger + OTel Collector) ──
module "tracing" {
  source             = "./modules/tracing"
  domain_name        = var.domain_name
  github_username    = var.github_username
  github_repo        = var.github_repo
  github_branch      = var.github_branch
  harness_account_id = var.harness_account_id
  harness_org_id     = var.harness_org_id
  harness_project_id = var.harness_project_id
  gitops_agent_id    = module.gitops.agent_identifier
  gitops_cluster_id  = module.gitops.cluster_identifier
  depends_on         = [module.gitops]
}

# ── Falco (Runtime Security — detects suspicious container behavior) ──
module "falco" {
  source             = "./modules/falco"
  domain_name        = var.domain_name
  harness_account_id = var.harness_account_id
  harness_org_id     = var.harness_org_id
  harness_project_id = var.harness_project_id
  gitops_agent_id    = module.gitops.agent_identifier
  gitops_cluster_id  = module.gitops.cluster_identifier
  depends_on         = [module.gitops]
}
