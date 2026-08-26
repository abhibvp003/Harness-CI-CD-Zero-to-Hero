# Episode 10: Complete Enterprise Project (End-to-End)

## Architecture

![Enterprise GitOps Platform Architecture](architecture/architecture.png)

---

## 🎯 Goal

Build the COMPLETE enterprise CI/CD platform — everything from Episodes 1-9 automated with **one `terraform apply`**. Zero manual clicks. MNC production standard.

---

## 🏗️ What This Creates

| Category | Resources |
|----------|-----------|
| **Infrastructure** | VPC → EKS (Auto Mode) → Bastion (SSM + SonarQube) → RDS PostgreSQL |
| **Networking** | Kong Gateway 3.9 (API Gateway + Ingress + NLB + ACM TLS) → ExternalDNS |
| **Security** | External Secrets Operator → AWS Secrets Manager (1 min refresh — bank-grade) |
| **CI/CD** | K8s Delegate (HA) → GitOps Agent (HA) → Harness Platform Resources |
| **Observability** | Prometheus + Grafana → EFK Stack → Jaeger All-in-One + OTel Collector |
| **Governance** | OPA Policies → Continuous Verification (Prometheus) → Auto-Rollback |
| **AI** | 5 Agents — Security, Code Review, Release Notes, Deployment Risk, Log Analysis |
| **DAST** | OWASP ZAP — Post-deploy scan with S3 HTML report |

---

## Pipeline Flow

![Pipeline Execution View](architecture/pipeline%20-1.png)

![Pipeline Designer View](architecture/pipeline.png)

```
Code Push → Security Scans → Build 11 Images → AI Agents → GitOps Deploy → Verify → DAST → Slack

Stage 1: security-scans (5 parallel)
  Gitleaks | Trivy | OSV Scanner | SonarQube | Checkov

Stage 2: build-and-push (4 batches × 3 parallel)
  S3 Cache Restore → 11 BuildAndPushECR → S3 Cache Save

Stage 3: ai-agents (5 agents)
  Security | Code Review | Release Notes | Risk Assessment | Log Analysis

Stage 4: gitops-deploy
  UpdateReleaseRepo → Approve → MergePR → GitOpsSync → GetAppStatus → Verify (CV)
  Rollback: RevertPR → MergePR → GitOpsSync (auto on failure)

Stage 5: dast-owasp-zap
  ZAP Baseline Scan → S3 presigned URL (7-day browser access)

Notifications: Slack (success/failure)
```

---

## 📁 Project Structure

```
Episode-10/
├── terraform/                          ← Infrastructure as Code (15 modules)
│   ├── main.tf                         ← Root module — orchestrates all modules + pre-destroy cleanup
│   ├── variables.tf                    ← All inputs (injected from GitHub Secrets/Variables via Actions)
│   ├── outputs.tf                      ← Platform outputs (cluster name, bastion IP, VPC ID, RDS endpoint)
│   ├── provider.tf                     ← AWS, Helm, Kubernetes, Kubectl, Harness providers configured
│   └── modules/
│       ├── vpc/                        ← VPC (10.0.0.0/16) + 2 public subnets (NLB, Bastion)
│       │                                  + 2 private subnets (EKS pods, RDS) + NAT GW + IGW + Route Tables
│       ├── eks/                        ← EKS Cluster (v1.31) + 2 Managed Node Groups:
│       │                                  Workloads (6×t3a.large, 3-10 autoscale) + CI (1×t3a.xlarge, tainted)
│       │                                  + OIDC (IRSA) + KMS encryption + LB Controller + Cluster Autoscaler
│       │                                  + EBS CSI + VPC CNI + CoreDNS + kube-proxy addons
│       ├── bastion/                    ← EC2 (t2.medium, Amazon Linux 2023) + SSM (no SSH key needed)
│       │                                  + pre-installs: kubectl, Helm, Docker, aws-cli, SonarQube
│       │                                  + EKS Admin access via aws_eks_access_entry
│       ├── ecr/                        ← 11 Docker repos (frontend, cart, checkout, product, currency,
│       │                                  email, payment, recommendation, shipping, ad, loadgenerator, cache)
│       │                                  + lifecycle: delete untagged after 7 days + scan-on-push
│       ├── rds/                        ← PostgreSQL 16.3 (db.t3.micro) + gp3 encrypted (20-100GB auto)
│       │                                  + private subnet only + 7-day backups + credentials → AWS SM
│       ├── delegate/                   ← Harness Delegate (Helm) + HA (2 replicas, autoscale to 6)
│       │                                  + 2-4Gi memory + ClusterRole (pods, deploys, jobs, ingress, secrets)
│       ├── kong-gateway/               ← Kong 3.9 OSS (DB-less, Helm) + NLB (ACM TLS on 443)
│       │                                  + HA (2→6 replicas) + Manager UI (basic-auth, password in AWS SM)
│       │                                  + 20 plugins: rate-limit (10000/min), CORS, security headers,
│       │                                    bot-detect, zipkin, proxy-cache (60s), IP restrict, request-size,
│       │                                    correlation-id, file-log, tcp-log, http-log, JWT, ACL, gRPC, etc.
│       ├── external-dns/               ← ExternalDNS (Helm + IRSA) → watches Kong Ingress resources
│       │                                  → auto-creates Route53 CNAME records (30s poll, TXT ownership)
│       ├── external-secrets/           ← ESO (Helm + IRSA) + ClusterSecretStore (aws-secrets-manager)
│       │                                  + pre-creates app-secrets in AWS SM with placeholder keys
│       ├── gitops/                     ← Harness GitOps Agent (ArgoCD HA: controller×2, repo-server×2-5,
│       │                                  server×2-4, redis×2) + downloads YAML from Harness API
│       │                                  + creates Repo (GitHub PAT) + Cluster + App (Helm chart sync)
│       ├── harness-platform/           ← Service (online_boutique, ReleaseRepo type)
│       │                                  + 2 Environments (production + development)
│       │                                  + Connectors: Prometheus, Elasticsearch (API), K8s delegate
│       │                                  + OPA Policy + PolicySet (via API, free tier compatible)
│       │                                  + Monitored Service (CV: pod restarts, CPU, memory)
│       │                                  + Variables: ci_cache_bucket, domain_name, sonar_host_url
│       ├── monitoring/                 ← kube-prometheus-stack 62.3.0 (ArgoCD auto-sync + self-heal)
│       │                                  + Grafana (password in AWS SM) + 50Gi persistent storage
│       │                                  + 2 dashboards: Online Boutique pods + Kong Gateway health
│       ├── logging/                    ← Elasticsearch 7.17 (xpack trial, single-node, yellow health check)
│       │                                  + Kibana (Kong Ingress) + Fluentd DaemonSet (logstash format)
│       │                                  + auto Kibana index pattern job (waits for fluentd* index)
│       ├── tracing/                    ← Jaeger All-in-One (allInOne.enabled=true, collector+query+storage)
│       │                                  + OTLP enabled (4317/4318) + badger persistent storage
│       │                                  + OTel Collector (receives OTLP from apps → exports to Jaeger)
│       └── falco/                      ← Falco 4.16.1 (DaemonSet, modern_ebpf driver)
│                                          + Sidekick UI (basic-auth, password in AWS SM)
│                                          + Detects: shell exec, privilege escalation, file tampering
│
├── k8s/                                ← Helm Chart — ArgoCD syncs from GitHub to cluster
│   ├── Chart.yaml                      ← Chart metadata
│   ├── values.yaml                     ← Image tags + config (pipeline PR updates these values)
│   └── templates/
│       ├── frontend.yaml               ← Frontend (Go) + OTEL_SERVICE_NAME
│       ├── cartservice.yaml            ← CartService (.NET) — reads REDIS_ADDR from app-secrets
│       ├── checkoutservice.yaml        ← CheckoutService (Go)
│       ├── productcatalogservice.yaml  ← ProductCatalog (Go)
│       ├── currencyservice.yaml        ← CurrencyService (Node.js)
│       ├── emailservice.yaml           ← EmailService (Python)
│       ├── paymentservice.yaml         ← PaymentService (Node.js)
│       ├── recommendationservice.yaml  ← RecommendationService (Python)
│       ├── shippingservice.yaml        ← ShippingService (Go)
│       ├── adservice.yaml              ← AdService (Java/Gradle)
│       ├── loadgenerator.yaml          ← LoadGenerator (Locust) — drives traffic for metrics
│       ├── redis.yaml                  ← Redis (cart storage)
│       ├── ingress.yaml                ← Kong Ingress: app.domain → frontend
│       ├── external-secret.yaml        ← ESO: AWS SM → K8s Secret (1 min refresh, bank-grade)
│       ├── external-secret-db.yaml     ← ESO: DB credentials (1 min refresh)
│       ├── namespace.yaml              ← online-boutique namespace
│       └── storageclass.yaml           ← auto-ebs-sc (gp3, encrypted, default)
│
├── .harness/
│   └── enterprise-gitops-pipeline.yaml ← 5-stage enterprise pipeline:
│                                          Stage 1: Security (Gitleaks, Trivy, OSV, SonarQube, Checkov)
│                                          Stage 2: Build (11 images → ECR, S3 cache, remote layer cache)
│                                          Stage 3: AI (5 agents: security, code review, risk, notes, logs)
│                                          Stage 4: GitOps (PR → Approve → Merge → Sync → CV → Rollback)
│                                          Stage 5: DAST (OWASP ZAP → S3 presigned HTML report)
│
├── ai-agents/                          ← 5 AI agents (Python + Google Gemini 3.5 Flash)
│   ├── ai_provider.py                 ← Provider abstraction (Gemini/OpenAI via AI_API_KEY env)
│   ├── security_agent.py             ← Reads pipeline context → threat assessment report
│   ├── code_review_agent.py          ← Reviews last 5 commits → score 1-10, APPROVE/BLOCK
│   ├── release_notes_agent.py        ← Last 20 commits → changelog with contributors table
│   ├── deployment_risk_agent.py      ← Environment + tests + time + changes → SAFE/RISKY/BLOCK
│   └── log_analysis_agent.py         ← Git log patterns → risky changes + recommendations
│
├── policies/
│   └── production-governance.rego     ← OPA: no Friday deploys, require approval, require rollback
│
├── architecture/                       ← Architecture diagrams (for README + LinkedIn)
│   ├── architecture.png               ← Full platform architecture with tech logos
│   ├── pipeline -1.png                ← Pipeline execution view (Harness UI)
│   └── pipeline.png                   ← Pipeline designer view (Harness Studio)
│
├── src/                               ← 11 microservices source (Google Online Boutique fork)
├── .checkov.yaml                      ← Checkov suppressions (known acceptable risks)
├── .gitleaks.toml                     ← Gitleaks allowlist (test data, not real secrets)
├── sonar-project.properties           ← SonarQube config (scans all 11 service directories)
├── DEPLOY-STEPS.md                    ← Complete 12-step deployment guide
└── README.md                          ← This file
```

---

## 🛡️ Security Stack (9 Layers)

| Layer | Tool | Stage | What It Detects |
|-------|------|-------|-----------------|
| 1 | Gitleaks | CI | Hardcoded secrets, API keys, passwords |
| 2 | Trivy | CI | Filesystem vulnerabilities (HIGH/CRITICAL) |
| 3 | OSV Scanner | CI | Dependency CVEs (Google OSV database) |
| 4 | SonarQube | CI | Code quality, security hotspots |
| 5 | Checkov | CI | Terraform + K8s misconfigurations |
| 6 | OPA Policies | Pipeline Run | Governance (no Friday deploys, require approval) |
| 7 | Approval Gates | GitOps CD | Human review before production |
| 8 | Kong Gateway | Runtime | Rate limiting (10000/min/IP), bot detection, CORS |
| 9 | OWASP ZAP | Post-deploy | XSS, SQL injection, CSRF on live app |

---

## 🔍 Continuous Verification (Auto-Rollback)

| Health Source | Type | Metrics | Rollback When |
|---|---|---|---|
| Prometheus | Metrics | Pod Restarts, CPU Usage, Memory Usage | Pods crash-looping or resource spike after deploy |

**How it works:**
- After GitOps deploys the new version, the **Verify step** runs for 5 minutes (`type: Auto`)
- Harness ML compares pre-deploy baseline vs post-deploy metrics
- If anomaly detected → **automatic rollback** (RevertPR → MergePR → GitOpsSync)
- Build 1: establishes baseline (no comparison, always passes)
- Build 2+: real before vs after comparison

---

## 🌐 Access URLs

| Service | URL | Login |
|---------|-----|-------|
| Online Boutique | `https://app.yourdomain.com` | No login |
| Kong Manager | `https://kong.yourdomain.com` | admin / (AWS SM: `online-boutique/kong-admin-password`) |
| Grafana | `https://grafana.yourdomain.com` | admin / (AWS SM: `online-boutique/grafana-password`) |
| Kibana | `https://kibana.yourdomain.com` | elastic / (AWS SM: `online-boutique/efk-password`) |
| Jaeger | `https://jaeger.yourdomain.com` | No login |
| Falco | `https://falco.yourdomain.com` | admin / (AWS SM: `online-boutique/falco-password`) |
| SonarQube | `http://BASTION-IP:9000` | admin / admin |

All via **1 NLB + Kong Gateway** (cost optimized). ExternalDNS auto-manages Route53.

---

## � Secrets Management (Bank-Grade)

```
AWS Secrets Manager → External Secrets Operator (1 min refresh) → K8s Secret → Pods

No secrets in Git. No hardcoded values. Auto-rotation within 60 seconds.
```

| Secret | Source | Used By |
|--------|--------|---------|
| `COLLECTOR_SERVICE_ADDR` | AWS SM (`app-secrets`) | All services (Jaeger tracing) |
| `REDIS_ADDR` | AWS SM (`app-secrets`) | cartservice |
| DB credentials | AWS SM (`db-credentials`) | All services |
| Grafana password | AWS SM (auto-generated) | Grafana login |
| EFK password | AWS SM (auto-generated) | Elasticsearch + Kibana |
| Kong admin password | AWS SM (auto-generated) | Kong Manager |

---

## 💰 Cost

| Period | Cost |
|--------|------|
| Running | ~$6/day (~$183/month) |
| **After destroy** | **$0.00** |

---

## 📋 How to Use

See **[DEPLOY-STEPS.md](./DEPLOY-STEPS.md)** for complete step-by-step instructions.

**Quick start:**
1. Set GitHub Variables + Secrets (Step 1-3 in DEPLOY-STEPS)
2. Run `ep10-setup.yml → apply` (creates everything ~20 min)
3. Add secrets in AWS SM (Step 6)
4. Import pipeline from Git in Harness
5. Run pipeline → 11 microservices deployed via GitOps
6. When done: `ep10-setup.yml → destroy` (bill = $0)

---

## 🎓 Technologies (25+)

| Category | Technologies |
|----------|-------------|
| **CI/CD Platform** | Harness CI, CD, GitOps, CV, OPA |
| **Containers** | Docker, Multi-stage Builds, ECR (Remote Cache) |
| **Orchestration** | Kubernetes (EKS Auto Mode), Helm, Karpenter |
| **API Gateway** | Kong Gateway 3.9 OSS (HA, 20 plugins, proxy cache) |
| **Infrastructure** | Terraform (14 modules), GitHub Actions (OIDC) |
| **GitOps** | ArgoCD (via Harness GitOps Agent, auto-sync + self-heal) |
| **Database** | RDS PostgreSQL 16.3 (encrypted, auto-creds) |
| **Security** | Trivy, SonarQube, Gitleaks, OSV, Checkov, OWASP ZAP, Falco |
| **Secrets** | AWS Secrets Manager + External Secrets Operator (1 min refresh) |
| **Monitoring** | Prometheus + Grafana (pod health dashboards) |
| **Logging** | Elasticsearch + Fluentd + Kibana (EFK) |
| **Tracing** | Jaeger All-in-One + OpenTelemetry Collector |
| **DNS/TLS** | Route53 + ExternalDNS + ACM Certificate |
| **AI** | Google Gemini 3.5 Flash (5 agents) |
| **Notifications** | Slack |
| **IAM** | Pod Identity (IRSA replacement) |

---

> 🎬 Previous Episode: [Episode 9 - GitOps & Observability](../Episode-09/README.md)
