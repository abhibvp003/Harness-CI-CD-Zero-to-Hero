# Deploys the Harness Delegate into EKS using a Helm chart
resource "helm_release" "delegate" {
  name             = "harness-delegate-ng"
  repository       = "https://app.harness.io/storage/harness-download/delegate-helm-chart/"
  chart            = "harness-delegate-ng"
  namespace        = "harness-delegate-ng"
  create_namespace = true

  values = [
    yamlencode({
      accountId           = var.account_id
      delegateToken       = var.delegate_token
      managerEndpoint     = "https://app.harness.io"
      delegateName        = var.delegate_name
      replicas            = var.replicas
      delegateDockerImage = "us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:${var.image_tag}"
      tags                = var.delegate_name
      autoscaling = {
        enabled                        = true
        minReplicas                    = var.replicas
        maxReplicas                    = var.replicas * 3
        targetCPUUtilizationPercentage = 70
      }
      resources = {
        requests = { cpu = "500m", memory = "2Gi" }
        limits   = { cpu = "1", memory = "4Gi" }
      }
    })
  ]

  wait    = true
  timeout = 900
}

# ClusterRole granting the delegate broad access to K8s resources
resource "kubernetes_cluster_role" "delegate" {
  metadata { name = "harness-delegate-cluster-role" }

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
}

# Binds the ClusterRole to the delegate's service account
resource "kubernetes_cluster_role_binding" "delegate" {
  metadata { name = "harness-delegate-cluster-rolebinding" }
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
}

