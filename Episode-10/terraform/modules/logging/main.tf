# ═══════════════════════════════════════════════════════════════════
# Logging Module — EFK Stack (Elasticsearch + Fluentd + Kibana) via Helm
# All via ArgoCD for GitOps self-healing and drift detection
# ═══════════════════════════════════════════════════════════════════

# Auto-generate EFK password and store in AWS SM
resource "random_password" "efk" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "efk" {
  name                    = "online-boutique/efk-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "efk" {
  secret_id = aws_secretsmanager_secret.efk.id
  secret_string = jsonencode({
    username = "elastic"
    password = random_password.efk.result
  })
}

# Elasticsearch — Helm chart via ArgoCD
resource "kubectl_manifest" "argocd_elasticsearch" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "elasticsearch", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      source = {
        repoURL        = "https://helm.elastic.co"
        chart          = "elasticsearch"
        targetRevision = "8.5.1"
        helm = {
          valuesObject = {
            replicas           = 1
            minimumMasterNodes = 1
            resources = {
              requests = { cpu = "500m", memory = "1Gi" }
              limits   = { cpu = "1", memory = "2Gi" }
            }
            volumeClaimTemplate = {
              resources        = { requests = { storage = "10Gi" } }
              storageClassName = "auto-ebs-sc"
            }
            esConfig = {
              "elasticsearch.yml" = "xpack.security.enabled: true"
            }
            secret = {
              enabled  = true
              password = random_password.efk.result
            }
          }
        }
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "logging" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  })
}

# Kibana — Helm chart via ArgoCD (with Kong Ingress)
resource "kubectl_manifest" "argocd_kibana" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "kibana", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      source = {
        repoURL        = "https://helm.elastic.co"
        chart          = "kibana"
        targetRevision = "8.5.1"
        helm = {
          valuesObject = {
            elasticsearchHosts = "http://elasticsearch-master:9200"
            resources = {
              requests = { cpu = "200m", memory = "512Mi" }
              limits   = { cpu = "500m", memory = "1Gi" }
            }
            ingress = {
              enabled   = true
              className = "kong"
              hosts     = [{ host = "kibana.${var.domain_name}", paths = [{ path = "/" }] }]
            }
          }
        }
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "logging" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  })
}

# Fluentd — Helm chart via ArgoCD (DaemonSet, collects all pod logs)
resource "kubectl_manifest" "argocd_fluentd" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "fluentd", namespace = "gitops" }
    spec = {
      project = "online-boutique"
      source = {
        repoURL        = "https://fluent.github.io/helm-charts"
        chart          = "fluentd"
        targetRevision = "0.5.2"
        helm = {
          valuesObject = {
            kind = "DaemonSet"
            fileConfigs = {
              "output.conf" = <<-EOF
                <match **>
                  @type elasticsearch
                  host elasticsearch-master.logging.svc.cluster.local
                  port 9200
                  user elastic
                  password ${random_password.efk.result}
                  logstash_format true
                  logstash_prefix k8s-logs
                </match>
              EOF
            }
          }
        }
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "logging" }
      syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
    }
  })
}
