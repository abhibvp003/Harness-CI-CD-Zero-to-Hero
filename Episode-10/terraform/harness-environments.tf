# ═══════════════════════════════════════════════════════════════════
# Harness Environments
# GitOps uses gitOpsClusters (not infrastructureDefinitions)
# Infrastructure is defined by the ArgoCD Application destination
# ═══════════════════════════════════════════════════════════════════

resource "harness_platform_environment" "production" {
  identifier = "production"
  name       = "production"
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  type       = "Production"

  yaml = <<-YAML
    environment:
      name: production
      identifier: production
      type: Production
      orgIdentifier: ${var.harness_org_id}
      projectIdentifier: ${var.harness_project_id}
  YAML
}

resource "harness_platform_environment" "development" {
  identifier = "development"
  name       = "development"
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  type       = "PreProduction"

  yaml = <<-YAML
    environment:
      name: development
      identifier: development
      type: PreProduction
      orgIdentifier: ${var.harness_org_id}
      projectIdentifier: ${var.harness_project_id}
  YAML
}
