# ═══════════════════════════════════════════════════════════════════
# ExternalDNS — Auto-creates Route53 records from Ingress resources
# MNC Pattern: Zero manual DNS management
# Watches Ingress → creates CNAME in Route53 → deletes on Ingress removal
# Only manages records it creates (ownership via TXT records)
# IRSA: projected SA token provides credentials instantly at pod start
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# IAM Role for External DNS (IRSA)
# Uses OIDC trust policy — no webhook, credentials available at pod start
# ─────────────────────────────────────────
resource "aws_iam_role" "external_dns" {
  name = "external-dns-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:external-dns:external-dns"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
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

      # Service account with IRSA annotation — credentials available instantly
      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
        }
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

  depends_on = [aws_iam_role_policy.external_dns_route53]
}
