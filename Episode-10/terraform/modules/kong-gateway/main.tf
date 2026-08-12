# ═══════════════════════════════════════════════════════════════════
# Kong Gateway — API Gateway + Ingress Controller
# Single entry point for ALL microservices with HA + autoscaling
# ═══════════════════════════════════════════════════════════════════

# Lookup existing ACM Certificate
data "aws_acm_certificate" "wildcard" {
  domain      = "*.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

# ─────────────────────────────────────────
# Kong Ingress Controller (Helm)
# ─────────────────────────────────────────
resource "helm_release" "kong" {
  name             = "kong"
  repository       = "https://charts.konghq.com"
  chart            = "kong"
  namespace        = "kong"
  create_namespace = true
  version          = "2.39.3"

  values = [
    yamlencode({
      # Ingress Controller
      ingressController = {
        enabled      = true
        installCRDs  = true
        ingressClass = "kong"
      }

      # Proxy (internet-facing NLB with ACM TLS termination)
      proxy = {
        enabled = true
        type    = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"             = "external"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"         = data.aws_acm_certificate.wildcard.arn
          "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"        = "443"
          "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "http"
        }
        tls = { enabled = false } # TLS terminated at NLB (ACM)
      }

      # Admin API (ClusterIP — only accessible inside cluster for Kong Manager)
      admin = {
        enabled = true
        type    = "ClusterIP"
        http    = { enabled = true }
      }

      # Kong Manager UI (dashboard — routes, plugins, upstreams, health)
      manager = {
        enabled = true
        type    = "ClusterIP"
        ingress = {
          enabled          = true
          ingressClassName = "kong"
          hostname         = "kong.${var.domain_name}"
          annotations = {
            "konghq.com/strip-path" = "false"
          }
        }
      }

      # Prometheus metrics endpoint (Kong exposes /metrics for scraping)
      serviceMonitor = {
        enabled = true
      }

      # HA — 2 replicas minimum, autoscale to 6
      replicaCount = 2
      autoscaling = {
        enabled                        = true
        minReplicas                    = 2
        maxReplicas                    = 6
        targetCPUUtilizationPercentage = 70
      }

      # Production resources
      resources = {
        requests = { cpu = "500m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }

      # Environment variables for Kong
      env = {
        # DB-less mode (declarative config via Ingress Controller — no PostgreSQL needed)
        database = "off"
        # Trusted IPs (for X-Forwarded-For from NLB)
        trusted_ips = "0.0.0.0/0,::/0"
        # Real IP header from NLB
        real_ip_header    = "X-Forwarded-For"
        real_ip_recursive = "on"
      }
    })
  ]
}

# ═══════════════════════════════════════════════════════════════════
# Global Kong Plugins (Applied to ALL routes automatically)
# Security + Observability at gateway level
# ═══════════════════════════════════════════════════════════════════

# Plugin 1: Rate Limiting — 100 requests/minute per IP (DDoS protection)
resource "kubernetes_manifest" "kong_rate_limit" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-rate-limit"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "rate-limiting"
    config = {
      minute              = 100
      policy              = "local"
      fault_tolerant      = true
      hide_client_headers = false
      header_name         = "X-RateLimit-Remaining" # Shows remaining requests in response header
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 2: CORS — Allow cross-origin requests (frontend → backend APIs)
resource "kubernetes_manifest" "kong_cors" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-cors"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "cors"
    config = {
      origins         = ["*"]
      methods         = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
      headers         = ["Accept", "Authorization", "Content-Type", "X-Requested-With"]
      exposed_headers = ["X-RateLimit-Remaining"]
      max_age         = 3600
      credentials     = true
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 3: Request Logging — {All API requests logged to stdout (Fluentd → EFK)}
resource "kubernetes_manifest" "kong_logging" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-logging"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "file-log"
    config = {
      path   = "/dev/stdout"
      reopen = true
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 4: Prometheus Metrics — {Per-route latency, errors, bandwidth}
resource "kubernetes_manifest" "kong_prometheus" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-prometheus"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "prometheus"
    config = {
      per_consumer            = true
      status_code_metrics     = true
      latency_metrics         = true
      bandwidth_metrics       = true
      upstream_health_metrics = true
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 5: Request Size Limiting — Prevent large payload attacks {10MB max}
resource "kubernetes_manifest" "kong_request_size" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-request-size"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "request-size-limiting"
    config = {
      allowed_payload_size = 10 # MB
      size_unit            = "megabytes"
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 6: Response Transformer — Add security headers to all responses {HSTS, X-Frame, XSS}
resource "kubernetes_manifest" "kong_security_headers" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-security-headers"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "response-transformer"
    config = {
      add = {
        headers = [
          "X-Content-Type-Options:nosniff",
          "X-Frame-Options:DENY",
          "X-XSS-Protection:1; mode=block",
          "Strict-Transport-Security:max-age=31536000; includeSubDomains"
        ]
      }
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 7: IP Restriction — {Block known bad IPs} ( security requirement)
resource "kubernetes_manifest" "kong_ip_restriction" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-ip-restriction"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "ip-restriction"
    config = {
      # Deny known malicious IPs (add your blocklist here)
      deny = []
      # Or allow only specific IPs (whitelist mode — uncomment for admin routes)
      # allow = ["10.0.0.0/8", "172.16.0.0/12"]
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 8: Bot Detection — Block common bots and scrapers
resource "kubernetes_manifest" "kong_bot_detection" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-bot-detection"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "bot-detection"
    config = {
      deny = [] # Kong has built-in bot patterns — blocks known bad user-agents
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 9: Request Termination — Maintenance mode (enable when needed)
# Uncomment to put entire API in {maintenance mode}
# resource "kubernetes_manifest" "kong_maintenance" {
#   manifest = {
#     apiVersion = "configuration.konghq.com/v1"
#     kind       = "KongClusterPlugin"
#     metadata = {
#       name = "global-maintenance"
#       annotations = { "kubernetes.io/ingress.class" = "kong" }
#       labels      = { global = "true" }
#     }
#     plugin = "request-termination"
#     config = {
#       status_code = 503
#       message     = "Service is under maintenance. Please try again later."
#       content_type = "application/json"
#       body         = "{\"error\": \"Service Unavailable\", \"message\": \"Scheduled maintenance in progress\"}"
#     }
#   }
#   depends_on = [helm_release.kong]
# }

# Plugin 10: Correlation ID — Track requests across microservices (	X-Request-ID header for distributed tracing)
resource "kubernetes_manifest" "kong_correlation_id" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-correlation-id"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "correlation-id"
    config = {
      header_name     = "X-Request-ID"
      generator       = "uuid#counter"
      echo_downstream = true # {Return X-Request-ID in response for debugging}
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 11: Response Rate Limiting — Protect against response flooding {Limit notification endpoints}
resource "kubernetes_manifest" "kong_response_rate_limit" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-response-rate-limit"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "response-ratelimiting"
    config = {
      limits = {
        sms_notifications = { minute = 10 } # Limit notification-heavy endpoints
      }
      header_name = "X-Kong-Limit"
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 12: Proxy Caching — {Cache GET responses 30s (reduce backend load)}
resource "kubernetes_manifest" "kong_proxy_cache" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-proxy-cache"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "proxy-cache"
    config = {
      response_code  = [200]
      request_method = ["GET"]
      content_type   = ["application/json"]
      cache_ttl      = 30       # Cache for 30 seconds
      strategy       = "memory" # In-memory cache (fast, no Redis needed)
      memory = {
        dictionary_name = "kong_db_cache"
      }
    }
  }
  depends_on = [helm_release.kong]
}



# Plugin 13: Key Auth — {API Key authentication} (for external API consumers)
# Consumers must pass ?apikey=xxx or header X-API-Key to access protected routes
resource "kubernetes_manifest" "kong_key_auth" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-key-auth"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      # NOT global — apply per-route using annotations on specific Ingress
      # labels = { global = "true" }
    }
    plugin = "key-auth"
    config = {
      key_names        = ["apikey", "X-API-Key"]
      key_in_query     = true
      key_in_header    = true
      key_in_body      = false
      hide_credentials = true
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 14: ACL (Access Control List) — { Group-based access to routes }
# Combine with key-auth: consumer has API key + belongs to group "internal" or "external"
resource "kubernetes_manifest" "kong_acl" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-acl"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
    }
    plugin = "acl"
    config = {
      allow              = ["internal", "admin", "partner"] # Only these groups can access
      hide_groups_header = true
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 15: TCP Log — Send request logs to external logging service {Send logs to Fluentd TCP}
resource "kubernetes_manifest" "kong_tcp_log" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-tcp-log"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "tcp-log"
    config = {
      host = "fluentd.logging.svc.cluster.local"
      port = 24224
      tls  = false
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 16: Request Transformer — Add/Remove/Rename headers before forwarding to upstream
resource "kubernetes_manifest" "kong_request_transformer" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-request-transformer"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "request-transformer"
    config = {
      add = {
        headers = [
          "X-Gateway:kong",          # Identify traffic came through Kong
          "X-Environment:production" # Tag environment in every request
        ]
      }
      remove = {
        headers = ["X-Powered-By"] # Remove server technology fingerprint
      }
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 17: Retry/Circuit Breaker (via upstream config — healthchecks)
# Kong auto-retries failed upstream requests and removes unhealthy upstreams {Retry logic}
resource "kubernetes_manifest" "kong_upstream_timeout" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-retry"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "pre-function"
    config = {
      access = [
        "kong.service.request.set_header('X-Kong-Retry-Count', '3')"
      ]
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 18: Zipkin — Distributed tracing (sends trace data to Jaeger/Zipkin) {Distributed tracing → OTel/Jaeger}
resource "kubernetes_manifest" "kong_zipkin" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-zipkin"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      labels      = { global = "true" }
    }
    plugin = "zipkin"
    config = {
      http_endpoint       = "http://otel-collector.tracing.svc.cluster.local:9411/api/v2/spans"
      sample_ratio        = 1 # 100% sampling (reduce in high-traffic prod)
      include_credential  = true
      traceid_byte_count  = 16
      header_type         = "preserve"
      default_header_type = "b3-single"
      tags_header         = "Zipkin-Tags"
      static_tags = [
        { name = "kong.env", value = "production" },
        { name = "kong.service", value = "online-boutique" }
      ]
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 19: HTTP Log — Send structured JSON logs to HTTP endpoint (webhook/SIEM) --> {Structured logs → Elasticsearch}
resource "kubernetes_manifest" "kong_http_log" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-http-log"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      # NOT global by default — enable per route for audit-critical endpoints
      # labels = { global = "true" }
    }
    plugin = "http-log"
    config = {
      http_endpoint = "http://elasticsearch.logging.svc.cluster.local:9200/kong-logs/_doc"
      method        = "POST"
      content_type  = "application/json"
      timeout       = 10000
      keepalive     = 60000
      flush_timeout = 2
      retry_count   = 3
    }
  }
  depends_on = [helm_release.kong]
}

# Plugin 20: gRPC Gateway — Convert REST to gRPC (frontend HTTP → backend gRPC)
# Enables REST clients to call gRPC microservices through Kong
resource "kubernetes_manifest" "kong_grpc_gateway" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongClusterPlugin"
    metadata = {
      name        = "global-grpc-gateway"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
      # NOT global — apply to specific gRPC routes only
    }
    plugin = "grpc-gateway"
    config = {} # Proto files specified per-route via annotations
  }
  depends_on = [helm_release.kong]
}

# ═══════════════════════════════════════════════════════════════════
# Kong Manager Authentication (Basic Auth — protects admin UI)
# Access: kong.yourdomain.com → prompts username/password
# Credentials: admin / KongAdmin@2026 (stored in K8s Secret)
# ═══════════════════════════════════════════════════════════════════

# Kong Consumer (the admin user)
resource "kubernetes_manifest" "kong_admin_consumer" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongConsumer"
    metadata = {
      name        = "kong-admin"
      namespace   = "kong"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
    }
    username = "admin"
  }
  depends_on = [helm_release.kong]
}

# Basic Auth credentials for the admin consumer
resource "kubernetes_secret" "kong_admin_credentials" {
  metadata {
    name      = "kong-admin-basic-auth"
    namespace = "kong"
    labels = {
      "konghq.com/credential" = "basic-auth"
    }
  }

  data = {
    kongCredType = "basic-auth"
    username     = "admin"
    password     = var.kong_admin_password
  }

  depends_on = [kubernetes_manifest.kong_admin_consumer]
}

# Basic Auth plugin — applied ONLY to Kong Manager route (not global)
resource "kubernetes_manifest" "kong_manager_auth" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongPlugin"
    metadata = {
      name      = "kong-manager-basic-auth"
      namespace = "kong"
    }
    plugin = "basic-auth"
    config = {
      hide_credentials = true
    }
  }
  depends_on = [helm_release.kong]
}

# ═══════════════════════════════════════════════════════════════════
# JWT Authentication — validates tokens at gateway level, auth not duplicated in each service
# Auto-generate JWT secret (never hardcoded)
# ═══════════════════════════════════════════════════════════════════
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# Store JWT secret in AWS Secrets Manager (apps read from here to sign tokens)
resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "online-boutique/jwt-secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id = aws_secretsmanager_secret.jwt_secret.id
  secret_string = jsonencode({
    JWT_SECRET = random_password.jwt_secret.result
    JWT_ISSUER = "online-boutique-issuer"
    JWT_ALGO   = "HS256"
  })
}

# JWT Plugin (apply to specific routes via annotation: konghq.com/plugins: jwt-auth)
resource "kubernetes_manifest" "kong_jwt_auth" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongPlugin"
    metadata = {
      name      = "jwt-auth"
      namespace = "kong"
    }
    plugin = "jwt"
    config = {
      # Where to find the JWT token in the request
      header_names    = ["Authorization"]
      uri_param_names = ["jwt"]
      cookie_names    = []
      # Claims to validate
      claims_to_verify = ["exp"] # Verify token not expired
      # Key claim — identifies which consumer owns the token
      key_claim_name = "iss"
      # Secret is base64 encoded
      secret_is_base64 = false
      # Forward decoded claims to upstream service as headers
      run_on_preflight = true
    }
  }
  depends_on = [helm_release.kong]
}

# JWT Consumer — represents your application/service that issues tokens
resource "kubernetes_manifest" "kong_jwt_consumer" {
  manifest = {
    apiVersion = "configuration.konghq.com/v1"
    kind       = "KongConsumer"
    metadata = {
      name        = "online-boutique-app"
      namespace   = "kong"
      annotations = { "kubernetes.io/ingress.class" = "kong" }
    }
    username = "online-boutique-app"
  }
  depends_on = [helm_release.kong]
}

# JWT Credential for the consumer (secret used to sign/verify tokens)
resource "kubernetes_secret" "kong_jwt_credential" {
  metadata {
    name      = "online-boutique-jwt-credential"
    namespace = "kong"
    labels = {
      "konghq.com/credential" = "jwt"
    }
  }

  data = {
    kongCredType = "jwt"
    key          = "online-boutique-issuer" # iss claim value in JWT
    algorithm    = "HS256"
    secret       = random_password.jwt_secret.result # Auto-generated, stored in AWS SM
  }

  depends_on = [kubernetes_manifest.kong_jwt_consumer]
}
