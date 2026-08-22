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

# ═══════════════════════════════════════════════════════════════════
# PRE-DESTROY CLEANUP — Runs BEFORE Terraform destroys EKS/VPC
# 
# HOW IT WORKS (Terraform destroy order):
#   1. Terraform destroys Kong, Monitoring, Logging, Tracing, Falco, etc.
#      (they depend on this null_resource → destroyed FIRST)
#   2. Terraform destroys THIS null_resource → destroy provisioner runs
#      (cleans NLBs, ENIs, NAT GWs — everything blocking subnet deletion)
#   3. Terraform destroys EKS cluster (node groups, addons, cluster)
#   4. Terraform destroys VPC (subnets now have zero dependencies → instant)
#
# This is the standard pattern used by AWS EKS Blueprints and enterprise
# Terraform modules. The cleanup lives in Terraform, not in the pipeline.
# ═══════════════════════════════════════════════════════════════════
resource "null_resource" "pre_destroy_cleanup" {
  triggers = {
    cluster_name = var.cluster_name
    region       = var.aws_region
    vpc_id       = module.vpc.vpc_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      #!/bin/bash
      set -x
      CLUSTER="${self.triggers.cluster_name}"
      REGION="${self.triggers.region}"
      VPC_ID="${self.triggers.vpc_id}"

      echo "═══════════════════════════════════════════════════════════════"
      echo "  PRE-DESTROY: Cleaning K8s-created AWS resources"
      echo "  Cluster: $CLUSTER | Region: $REGION | VPC: $VPC_ID"
      echo "═══════════════════════════════════════════════════════════════"

      # ─── Step 1: K8s cleanup (if cluster is still accessible) ───
      if aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
        aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" 2>/dev/null

        echo "[1/8] Removing webhooks..."
        kubectl delete validatingwebhookconfiguration --all --ignore-not-found=true 2>/dev/null || true
        kubectl delete mutatingwebhookconfiguration --all --ignore-not-found=true 2>/dev/null || true

        echo "[2/8] Removing ArgoCD finalizers..."
        for app in $(kubectl get applications -n gitops -o name 2>/dev/null); do
          kubectl patch "$app" -n gitops --type json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
        done

        echo "[3/8] Deleting LoadBalancer services (releases NLBs/ALBs)..."
        kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | while read -r NS SVC; do
          [ -z "$NS" ] && continue
          echo "  Deleting: $NS/$SVC"
          kubectl delete svc "$SVC" -n "$NS" --ignore-not-found=true --timeout=60s 2>/dev/null || true
        done

        echo "[4/8] Deleting PVCs (releases EBS volumes)..."
        kubectl get pvc -A --no-headers 2>/dev/null | while read -r NS PVC _; do
          [ -z "$NS" ] && continue
          kubectl delete pvc "$PVC" -n "$NS" --ignore-not-found=true --timeout=30s 2>/dev/null || true
        done

        echo "[5/8] Cleaning namespaces..."
        for ns in $(kubectl get ns --no-headers 2>/dev/null | awk '{print $1}'); do
          case "$ns" in kube-system|kube-public|kube-node-lease|default) continue;; esac
          kubectl patch ns "$ns" --type json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
          kubectl patch ns "$ns" --type json -p='[{"op":"replace","path":"/spec/finalizers","value":[]}]' 2>/dev/null || true
          kubectl delete namespace "$ns" --ignore-not-found=true --wait=false --timeout=30s 2>/dev/null || true
        done

        echo "[6/8] Waiting 60s for AWS to release ENIs..."
        sleep 60
      else
        echo "EKS cluster not accessible. Skipping K8s cleanup."
      fi

      # ─── Step 2: AWS-level cleanup (works even if cluster is gone) ───
      if [ -n "$VPC_ID" ]; then
        echo "[7/8] Deleting Load Balancers in VPC..."
        for arn in $(aws elbv2 describe-load-balancers --region "$REGION" \
          --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null); do
          [ -z "$arn" ] || [ "$arn" = "None" ] && continue
          echo "  Deleting LB: $arn"
          # First delete target groups associated with this LB
          for tg in $(aws elbv2 describe-target-groups --region "$REGION" --load-balancer-arn "$arn" \
            --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null); do
            [ -z "$tg" ] || [ "$tg" = "None" ] && continue
            aws elbv2 delete-target-group --region "$REGION" --target-group-arn "$tg" 2>/dev/null || true
          done
          aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn" 2>/dev/null || true
        done
        # Classic ELBs
        for elb in $(aws elb describe-load-balancers --region "$REGION" \
          --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" --output text 2>/dev/null); do
          [ -z "$elb" ] || [ "$elb" = "None" ] && continue
          aws elb delete-load-balancer --region "$REGION" --load-balancer-name "$elb" 2>/dev/null || true
        done

        # Wait for LB ENIs to release
        sleep 30

        # Delete NAT Gateways
        for nat in $(aws ec2 describe-nat-gateways --region "$REGION" \
          --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending,deleting" \
          --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text 2>/dev/null); do
          [ -z "$nat" ] || [ "$nat" = "None" ] && continue
          echo "  Deleting NAT GW: $nat"
          aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$nat" 2>/dev/null || true
        done

        # Wait for NAT GW ENIs to release (NAT GWs take ~60s to fully delete)
        echo "Waiting 60s for NAT Gateway ENI release..."
        sleep 60

        echo "[8/8] Force-cleaning ENIs..."
        # Detach all ENIs
        ENI_LIST=$(aws ec2 describe-network-interfaces --region "$REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query 'NetworkInterfaces[].[NetworkInterfaceId,Attachment.AttachmentId,Status]' --output text 2>/dev/null || true)
        
        echo "$ENI_LIST" | while read -r eni attach status; do
          [ -z "$eni" ] || [ "$eni" = "None" ] && continue
          if [ "$status" = "in-use" ] && [ -n "$attach" ] && [ "$attach" != "None" ]; then
            echo "  Detaching: $eni"
            aws ec2 detach-network-interface --region "$REGION" --attachment-id "$attach" --force 2>/dev/null || true
          fi
        done

        echo "Waiting 20s for detach to complete..."
        sleep 20

        # Delete all ENIs (re-query to get current state after detach)
        ENI_IDS=$(aws ec2 describe-network-interfaces --region "$REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || true)
        
        for eni in $ENI_IDS; do
          [ -z "$eni" ] || [ "$eni" = "None" ] && continue
          echo "  Deleting ENI: $eni"
          aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" 2>/dev/null || true
        done

        # Final check — if any ENIs still exist, wait and retry once more
        sleep 10
        REMAINING_ENIS=$(aws ec2 describe-network-interfaces --region "$REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || true)
        
        for eni in $REMAINING_ENIS; do
          [ -z "$eni" ] || [ "$eni" = "None" ] && continue
          echo "  RETRY deleting ENI: $eni"
          aws ec2 detach-network-interface --region "$REGION" --attachment-id \
            $(aws ec2 describe-network-interfaces --region "$REGION" --network-interface-ids "$eni" \
              --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text 2>/dev/null) --force 2>/dev/null || true
          sleep 5
          aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" 2>/dev/null || true
        done

        # Release unassociated Elastic IPs
        for alloc in $(aws ec2 describe-addresses --region "$REGION" \
          --query 'Addresses[?AssociationId==null].AllocationId' --output text 2>/dev/null); do
          [ -z "$alloc" ] || [ "$alloc" = "None" ] && continue
          echo "  Releasing EIP: $alloc"
          aws ec2 release-address --region "$REGION" --allocation-id "$alloc" 2>/dev/null || true
        done

        # Delete orphaned target groups (leftover from deleted LBs)
        for tg in $(aws elbv2 describe-target-groups --region "$REGION" \
          --query "TargetGroups[?VpcId=='$VPC_ID' && length(LoadBalancerArns)==\`0\`].TargetGroupArn" --output text 2>/dev/null); do
          [ -z "$tg" ] || [ "$tg" = "None" ] && continue
          echo "  Deleting orphaned TG: $tg"
          aws elbv2 delete-target-group --region "$REGION" --target-group-arn "$tg" 2>/dev/null || true
        done
      fi

      echo "═══════════════════════════════════════════════════════════════"
      echo "  PRE-DESTROY CLEANUP COMPLETE — Terraform can now delete VPC"
      echo "═══════════════════════════════════════════════════════════════"
    EOT
  }

  depends_on = [module.eks, module.vpc]
}

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
  depends_on             = [module.eks, null_resource.pre_destroy_cleanup]
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
  depends_on       = [kubernetes_storage_class.ebs, null_resource.pre_destroy_cleanup]
}

# ── Kong Gateway (API Gateway + Ingress Controller) ──
module "kong_gateway" {
  source      = "./modules/kong-gateway"
  domain_name = var.domain_name
  depends_on  = [module.eks, module.external_secrets, null_resource.pre_destroy_cleanup]
}

# ── ExternalDNS (Auto-creates Route53 records from Ingress) ──
module "external_dns" {
  source            = "./modules/external-dns"
  domain_name       = var.domain_name
  aws_region        = var.aws_region
  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  depends_on        = [module.kong_gateway, null_resource.pre_destroy_cleanup]
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
  depends_on        = [module.eks, null_resource.pre_destroy_cleanup]
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
  depends_on         = [module.delegate, null_resource.pre_destroy_cleanup]
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
  efk_password       = module.logging.efk_password
  depends_on         = [module.delegate, module.gitops, module.logging, module.monitoring]
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
  depends_on         = [module.gitops, module.external_secrets, null_resource.pre_destroy_cleanup]
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
  depends_on         = [module.gitops, module.external_secrets, null_resource.pre_destroy_cleanup]
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
  depends_on         = [module.gitops, null_resource.pre_destroy_cleanup]
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
  depends_on         = [module.gitops, null_resource.pre_destroy_cleanup]
}
