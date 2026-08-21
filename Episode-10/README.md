# Episode 10: Complete Enterprise Project (End-to-End)

## 🎯 Goal

Build the COMPLETE enterprise CI/CD platform — everything from Episodes 1-9 automated with **one `terraform apply`**. Zero manual clicks. MNC production standard.

---

## 🏗️ What This Creates

```
One terraform apply = Entire Enterprise Platform

Infrastructure:       VPC → EKS (Auto Mode) → Bastion → RDS PostgreSQL
Networking:           Kong Gateway (API Gateway + Ingress) → ExternalDNS (auto Route53)
Security:             External Secrets Operator → AWS Secrets Manager
CI/CD:                K8s Delegate (HA) → GitOps Agent (HA) → Harness Platform Resources
Observability:        Prometheus + Grafana → EFK → Jaeger + OTel Collector
Governance:           OPA Policies → Continuous Verification (3 Health Sources) → Auto-Rollback
AI:                   Security Agent → Code Review → Deployment Risk Assessment
```

---

## 📁 Project Structure

```
Episode-10/
├── terraform/                          ← Infrastructure as Code (14 modules)
│   ├── main.tf                         ← Root module — calls all child modules
│   ├── variables.tf                    ← All inputs (from GitHub Secrets/Variables)
│   ├── outputs.tf                      ← Platform outputs
│   ├── provider.tf                     ← AWS, Helm, Kubernetes, Harness providers
│   └── modules/
│       ├── vpc/                        ← VPC, Subnets, NAT, Route Tables
│       ├── eks/                        ← EKS Auto Mode, IAM, KMS, CloudWatch
│       ├── bastion/                    ← EC2, SSM, kubectl, Helm, SonarQube
│       ├── ecr/                        ← 11 repos + lifecycle policies
│       ├── rds/                        ← PostgreSQL 16.3 + auto-creds in AWS SM
│       ├── delegate/                   ← K8s Delegate (HA + autoscale + RBAC)
│       ├── kong-gateway/               ← Kong 3.9 OSS (Manager UI, 20 plugins, NLB + ACM TLS)
│       ├── external-dns/               ← Auto Route53 records from Ingress (Pod Identity)
│       ├── external-secrets/           ← ESO + ClusterSecretStore (Pod Identity)
│       ├── gitops/                     ← GitOps Agent + Repo + Cluster + App
│       ├── harness-platform/           ← Service, Envs, Connectors, OPA, CV (3 health sources)
│       ├── monitoring/                 ← Prometheus + Grafana (Helm via ArgoCD)
│       ├── logging/                    ← EFK Stack — ES 7.17 (xpack trial auth) + Kibana + Fluentd
│       └── tracing/                    ← Jaeger 3.1.1 + OTel Collector (ArgoCD)
│
├── k8s/                                ← Helm Chart (ArgoCD syncs to cluster)
│   ├── Chart.yaml
│   ├── values.yaml                     ← Image URLs + config (GitOps updates via PR)
│   └── templates/                      ← 11 microservices + Redis + Ingress + ExternalSecrets
│
├── .harness/
│   └── enterprise-gitops-pipeline.yaml ← CI + Security + AI + GitOps + Verify + Rollback
│
├── ai-agents/                          ← 4 AI agents (Python, zero dependencies)
│   ├── security_agent.py              ← Trivy/Gitleaks/OWASP → AI report
│   ├── deployment_risk_agent.py       ← SAFE/RISKY/BLOCK decision
│   ├── code_review_agent.py           ← Git diff → bugs/security/performance
│   └── log_analysis_agent.py          ← Logs → root cause + fix suggestions
│
├── policies/
│   └── production-governance.rego      ← OPA: no Friday deploys, require approval
│
├── src/                                ← 11 microservices (Google Online Boutique)
├── sonar-project.properties            ← SonarQube multi-service scan config
├── DEPLOY-STEPS.md                     ← Step-by-step deployment guide
└── README.md                           ← This file
```

---

## 🚀 Pipeline Flow

```
Code Push → OPA Gate → Security Scans → Build 11 Images → AI Analysis → GitOps Deploy → Verify → Slack

Stage 1: CI (KubernetesDirect — code stays in VPC)
  ├── [Parallel] Gitleaks + Trivy + OWASP + SonarQube
  └── [Parallel] BuildAndPushECR × 11 (OIDC, tag: v#)

Stage 2: AI Security Agent → reads scan results → prioritized report

Stage 3: AI Deployment Risk → SAFE/RISKY/BLOCK

Stage 4: GitOps Deploy
  ├── UpdateReleaseRepo (PR with 11 image tags)
  ├── HarnessApproval (human review)
  ├── MergePR → main
  ├── GitOpsSync → ArgoCD syncs cluster
  ├── GetAppDetails → Healthy ✅
  └── Verify → 3 Health Sources CV (auto-rollback if ANY degraded)
        ├── Prometheus: pod restarts (infrastructure)
        ├── Prometheus: HTTP 5xx via Kong (end-to-end)
        └── Elasticsearch: error logs (application)

Rollback: RevertPR → MergePR → GitOpsSync (old version back)
Notifications: Slack on success/failure
```

---

## 🛡️ Security Stack (8 Layers)

| Layer | Tool | Stage |
|-------|------|-------|
| 1 | Gitleaks | CI (secrets in code) |
| 2 | SonarQube | CI (code quality) |
| 3 | OWASP | CI (dependency CVEs) |
| 4 | Trivy | CI (filesystem vulns) |
| 5 | OPA Policies | On Pipeline Run |
| 6 | Approval Gates | GitOps CD |
| 7 | Kong Gateway | Runtime (rate limit, WAF, bot detection) |
| 8 | Continuous Verification | Post-deploy (3 health sources — metrics + HTTP + logs) |

---

## 🔍 Continuous Verification (3 Health Sources)

| # | Health Source | Type | What It Monitors | Rollback When |
|---|---|---|---|---|
| 1 | `prometheus` | Prometheus Metrics | Pod restart count | Pods crash-looping after deploy |
| 2 | `app-http-errors` | Prometheus Metrics | HTTP 5xx errors via Kong Gateway | App returning 502/503/500 to users |
| 3 | `elasticsearch` | Elasticsearch Logs | Error logs, exceptions, stack traces | New error patterns or error spike |

**How it works:**
- After GitOps deploys the new version, the **Verify step** runs for 5 minutes
- Harness ML compares pre-deploy baseline vs post-deploy metrics/logs
- If **ANY** of the 3 health sources detects anomaly → **automatic rollback**
- Rollback = RevertPR → MergePR → GitOpsSync (old version restored in seconds)

---

## 🌐 Access URLs

| Service | URL | Login |
|---------|-----|-------|
| Online Boutique | `https://app.yourdomain.com` | No login |
| Kong Manager | `https://kong.yourdomain.com` | admin / (from AWS SM: `online-boutique/kong-admin-password`) |
| Grafana | `https://grafana.yourdomain.com` | admin / (from AWS SM: `online-boutique/grafana-password`) |
| Kibana | `https://kibana.yourdomain.com` | elastic / (from AWS SM: `online-boutique/efk-password`) |
| Jaeger | `https://jaeger.yourdomain.com` | No login |
| SonarQube | `http://BASTION-IP:9000` | admin / admin |

All via **1 NLB + Kong Gateway** (cost optimized). ExternalDNS auto-manages Route53.

---

## 💰 Cost

| Running | ~$6/day (~$183/month) |
|---------|----------------------|
| **After destroy** | **$0.00** |

---

## 📋 How to Use

See **[DEPLOY-STEPS.md](./DEPLOY-STEPS.md)** for complete step-by-step instructions.

Quick start:
1. Set GitHub Variables + Secrets (Step 1-3 in DEPLOY-STEPS)
2. Run `ep10-setup.yml → apply` (creates everything)
3. Import pipeline from Git in Harness
4. Run pipeline → 11 microservices deployed via GitOps
5. When done: `ep10-setup.yml → destroy` (bill = $0)

---

## 🎓 Technologies Covered

| Category | Technologies |
|----------|-------------|
| **Platform** | Harness CI, CD, GitOps, STO, OPA |
| **Containers** | Docker, Multi-stage Builds, ECR |
| **Orchestration** | Kubernetes (EKS Auto Mode), Helm |
| **API Gateway** | Kong Gateway 3.9 OSS (20 plugins, Manager UI, HA) |
| **Infrastructure** | Terraform (14 modules), GitHub Actions |
| **GitOps** | ArgoCD (via Harness GitOps Agent) |
| **Database** | RDS PostgreSQL (encrypted, auto-creds) |
| **Security** | Trivy, SonarQube, Gitleaks, OWASP, OPA |
| **Secrets** | AWS Secrets Manager + External Secrets Operator |
| **Monitoring** | Prometheus, Grafana (auto-dashboards) |
| **Logging** | Elasticsearch, Fluentd, Kibana (EFK) |
| **Continuous Verification** | Harness CV (Prometheus metrics + Elasticsearch logs + HTTP 5xx) |
| **Tracing** | OpenTelemetry, Jaeger |
| **DNS** | Route53 + ExternalDNS (automatic) |
| **TLS** | ACM Certificate (auto-discovery) |
| **AI** | GPT-4o-mini / Gemini (security, code review, risk) |
| **Notifications** | Slack |

---

> 🎬 Previous Episode: [Episode 9 - GitOps & Observability](../Episode-09/README.md)
