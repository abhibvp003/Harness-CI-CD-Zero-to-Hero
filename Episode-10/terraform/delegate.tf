# ═══════════════════════════════════════════════════════════════════
# Kubernetes Delegate — Installed via Helm (Production Way)
# This replaces manual "kubectl apply" from Episodes 6-9
# MNC Pattern: Delegate installed as code, reproducible, version-controlled
# ═══════════════════════════════════════════════════════════════════

resource "helm_release" "harness_delegate" {
  name             = "harness-delegate-ng"
  repository       = "https://app.harness.io/storage/harness-download/delegate-helm-chart/"
  chart            = "harness-delegate-ng"
  namespace        = "harness-delegate-ng"
  create_namespace = true

  values = [
    yamlencode({
      accountId           = var.harness_account_id
      delegateToken       = var.harness_delegate_token
      managerEndpoint     = "https://app.harness.io"
      delegateName        = var.delegate_name
      replicas            = var.delegate_replicas
      delegateDockerImage = "harness/delegate:${var.delegate_image_tag}"
      tags                = var.delegate_name

      # High Availability
      autoscaling = {
        enabled                        = true
        minReplicas                    = var.delegate_replicas
        maxReplicas                    = var.delegate_replicas * 3
        targetCPUUtilizationPercentage = 70
      }

      # Resource requests/limits for production
      resources = {
        requests = {
          cpu    = "500m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "1"
          memory = "4Gi"
        }
      }
    })
  ]

  wait    = true
  timeout = 600

  depends_on = [aws_eks_cluster.main, kubernetes_storage_class.ebs]
}

# ─────────────────────────────────────────
# Delegate RBAC — Required for KubernetesDirect CI builds
# Must exist BEFORE pipeline runs (delegate needs pod create permission)
# ─────────────────────────────────────────
resource "kubernetes_namespace" "harness_builds" {
  metadata {
    name = "harness-builds"
    labels = {
      purpose    = "ci-builds"
      managed-by = "harness-delegate"
    }
  }

  depends_on = [aws_eks_cluster.main]
}

resource "kubernetes_cluster_role" "delegate" {
  metadata {
    name = "harness-delegate-cluster-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "pods/exec", "services", "endpoints", "persistentvolumeclaims", "events", "configmaps", "secrets", "serviceaccounts", "namespaces", "nodes"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [aws_eks_cluster.main]
}

resource "kubernetes_cluster_role_binding" "delegate" {
  metadata {
    name = "harness-delegate-cluster-rolebinding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.delegate.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "harness-delegate-ng"
  }

  depends_on = [helm_release.harness_delegate]
}
