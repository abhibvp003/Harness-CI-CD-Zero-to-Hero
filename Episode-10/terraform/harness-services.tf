# ═══════════════════════════════════════════════════════════════════
# Harness GitOps Service — Release Repo Manifest Type
# GitOps Service ≠ CD Service
# Points ONLY to values.yaml (the file GitOpsUpdateReleaseRepo modifies)
# ArgoCD Application handles the actual manifest rendering + deploy
# ═══════════════════════════════════════════════════════════════════

resource "harness_platform_service" "online_boutique" {
  identifier = "online_boutique"
  name       = "online-boutique"
  org_id     = var.harness_org_id
  project_id = var.harness_project_id

  yaml = <<-YAML
    service:
      name: online-boutique
      identifier: online_boutique
      orgIdentifier: ${var.harness_org_id}
      projectIdentifier: ${var.harness_project_id}
      serviceDefinition:
        type: Kubernetes
        spec:
          manifests:
            - manifest:
                identifier: release_repo
                type: ReleaseRepo
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: account.Github
                      repoName: Harness-CI-CD-Zero-to-Hero
                      branch: main
                      paths:
                        - Episode-10/k8s/values.yaml
          artifacts:
            primary:
              primaryArtifactRef: ecr_frontend
              sources:
                - identifier: ecr_frontend
                  type: Ecr
                  spec:
                    connectorRef: account.aws_account
                    region: ${var.aws_region}
                    imagePath: frontend
                    tag: <+input>
  YAML

  depends_on = [helm_release.harness_delegate]
}
