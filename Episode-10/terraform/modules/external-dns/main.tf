# ═══════════════════════════════════════════════════════════════════
# ExternalDNS — Auto-creates Route53 records from Ingress resources
# MNC Pattern: Zero manual DNS management
# Watches Ingress → creates CNAME in Route53 → deletes on Ingress removal
# Only manages records it creates (ownership via TXT records)
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# IAM Role for External DNS (EKS Pod Identity)
# EKS Auto Mode blocks IMDS access — pods need Pod Identity for AWS creds
# ─────────────────────────────────────────
resource "aws_iam_role" "external_dns" {
  name = "external-dns-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Route53 permissions — External DNS needs to list zones and upsert records
resource "aws_iam_role_policy" "external_dns_route53" {
  name = "external-dns-route53"
  role = aws_iam_role.external_dns.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
        ]
        Resource = ["*"]
      }
    ]
  })
}

# EKS Pod Identity Association — binds IAM role to the external-dns service account
resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = var.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}

# ─────────────────────────────────────────
# External DNS Helm Release
# ─────────────────────────────────────────
resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  version          = "1.14.5"

  values = [
    yamlencode({
      # AWS Route53 provider
      provider = "aws"

      # Only manage records for your domain (don't touch other hosted zones)
      domainFilters = [var.domain_name]

      # txtOwnerId — unique ID to identify records created by THIS instance
      txtOwnerId = "ep10-external-dns"

      # Policy: sync = create + delete records when Ingress changes
      policy = "sync"

      # Source: watch both Ingress and Service (LoadBalancer) resources
      sources = ["ingress", "service"]

      # AWS region
      env = [
        { name = "AWS_DEFAULT_REGION", value = var.aws_region }
      ]

      # Service account — must match Pod Identity association name
      serviceAccount = {
        create = true
        name   = "external-dns"
      }

      # Log level (debug helps troubleshoot — change to info once working)
      logLevel = "debug"

      # Interval to check for changes (30 seconds)
      interval = "30s"

      # Registry type (TXT records for ownership tracking)
      registry  = "txt"
      txtPrefix = "_externaldns."

      # Extra args for Kong IngressClass compatibility
      extraArgs = [
        "--ingress-class=kong"
      ]
    })
  ]

  depends_on = [aws_eks_pod_identity_association.external_dns]
}

# Restart ExternalDNS to ensure Pod Identity credentials are injected
resource "null_resource" "restart_external_dns" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --kubeconfig /tmp/kubeconfig
      for i in $(seq 1 12); do
        READY=$(KUBECONFIG=/tmp/kubeconfig kubectl get deployment external-dns -n external-dns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        if [ "$READY" -ge 1 ] 2>/dev/null; then break; fi
        echo "Waiting for ExternalDNS deployment... (attempt $i/12)"
        sleep 10
      done
      KUBECONFIG=/tmp/kubeconfig kubectl rollout restart deployment/external-dns -n external-dns
      KUBECONFIG=/tmp/kubeconfig kubectl rollout status deployment/external-dns -n external-dns --timeout=120s
    EOT
  }

  depends_on = [helm_release.external_dns]
}
