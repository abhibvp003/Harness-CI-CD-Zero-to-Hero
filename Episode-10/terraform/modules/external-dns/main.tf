# ═══════════════════════════════════════════════════════════════════
# ExternalDNS — Auto-creates Route53 records from Ingress resources
# MNC Pattern: Zero manual DNS management
# Watches Ingress → creates CNAME in Route53 → deletes on Ingress removal
# Only manages records it creates (ownership via TXT records)
# ═══════════════════════════════════════════════════════════════════

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

      # Hosted Zone ID (optional — speeds up lookup if you have multiple zones)
      # txtOwnerId — unique ID to identify records created by THIS instance
      txtOwnerId = "ep10-external-dns"

      # Policy: sync = create + delete records when Ingress changes
      # upsert-only = only create/update, never delete (safer but leaves orphans)
      policy = "sync"

      # Source: watch Ingress resources for hostnames
      sources = ["ingress"]

      # AWS region
      env = [
        { name = "AWS_DEFAULT_REGION", value = var.aws_region }
      ]

      # Service account (uses EKS node IAM role — no access keys)
      serviceAccount = {
        create = true
        name   = "external-dns"
      }

      # Log level
      logLevel = "info"

      # Interval to check for changes (30 seconds)
      interval = "30s"

      # Registry type (TXT records for ownership tracking)
      registry  = "txt"
      txtPrefix = "_externaldns."
    })
  ]
}
