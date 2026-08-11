# ═══════════════════════════════════════════════════════════════════
# OPA Policies — Automated Governance (Episode 8 Pattern)
# MNC Pattern: Policies created via Terraform, evaluated On Run
# Blocks pipeline if rules are violated (no human intervention needed)
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
# Policy: Production Governance
# Rules: No Friday deploys, require approval, require rollback, no hardcoded IDs
# ─────────────────────────────────────────
resource "harness_platform_policy" "production_governance" {
  identifier = "production_governance"
  name       = "Production Governance"
  org_id     = var.harness_org_id
  project_id = var.harness_project_id

  rego = file("${path.module}/../policies/production-governance.rego")
}

# ─────────────────────────────────────────
# Policy Set: Enforces policy On Run for all pipelines
# ─────────────────────────────────────────
resource "harness_platform_policyset" "production" {
  identifier = "production_policy_set"
  name       = "Production Policy Set"
  org_id     = var.harness_org_id
  project_id = var.harness_project_id
  action     = "onrun"
  type       = "pipeline"
  enabled    = true

  policies {
    identifier = harness_platform_policy.production_governance.identifier
    severity   = "error"
  }
}
