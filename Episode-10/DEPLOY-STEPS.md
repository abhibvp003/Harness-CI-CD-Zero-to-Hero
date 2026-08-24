# Episode 10: Complete Enterprise Project — Deployment Steps

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  TERRAFORM (One Apply = Entire Platform)                              │
│                                                                       │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌───────────┐  ┌────────┐  │
│  │  VPC    │→ │  EKS    │→ │Bastion  │→ │ Delegate  │→ │GitOps  │  │
│  │ Subnets │  │AutoMode │  │  SSM    │  │  HA (2)   │  │Agent   │  │
│  │ NAT, RT │  │ KMS,IAM │  │SonarQube│  │Autoscale  │  │HA (2)  │  │
│  └─────────┘  └─────────┘  └─────────┘  └───────────┘  └────────┘  │
│                                                                       │
│  ┌─────────┐  ┌─────────────┐  ┌────────────┐  ┌─────────────────┐  │
│  │  ECR    │  │ Harness     │  │ Harness    │  │  External       │  │
│  │11 repos │  │ Service     │  │ Environment│  │  Secrets        │  │
│  │lifecycle│  │(ReleaseRepo)│  │ (dev+prod) │  │  Operator       │  │
│  └─────────┘  └─────────────┘  └────────────┘  └─────────────────┘  │
│                                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  ┌────────────┐  │
│  │ Connectors  │  │ OPA Policy   │  │ Monitored  │  │Kong Gateway│  │
│  │Prometheus   │  │ + PolicySet  │  │ Service    │  │ 3.9 OSS    │  │
│  │K8s, ELK     │  │ (On Run)     │  │(CV — 3 HS) │  │NLB + ACM   │  │
│  └─────────────┘  └──────────────┘  └────────────┘  └────────────┘  │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  KONG GATEWAY 3.9 (API Gateway + Ingress Controller)                 │
│                                                                       │
│  NLB (internet-facing, ACM TLS termination on 443)                   │
│  ├── kong.domain    → Kong Manager OSS UI (basic-auth protected)     │
│  ├── grafana.domain → Prometheus + Grafana (login: admin/password)   │
│  ├── kibana.domain  → Kibana (login: elastic/password via xpack)     │
│  ├── jaeger.domain  → Jaeger Query UI (open access)                  │
│  └── app.domain     → Online Boutique Frontend                       │
│  20 Global Plugins: rate-limit, CORS, Zipkin, bot-detect, JWT, etc.  │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  HARNESS ENTERPRISE PIPELINE (Per Code Push)                          │
│                                                                       │
│  Stage 1: CI (KubernetesDirect — code stays in VPC)                  │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ [Parallel] Gitleaks │ Trivy │ OWASP │ SonarQube             │    │
│  │            ↓ scan results saved as JSON                       │    │
│  │ [Parallel] BuildAndPushECR × 11 services (OIDC, tag: v#)    │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  Stage 2: AI Security Agent                                          │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ python security_agent.py → reads scan JSONs → AI report      │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  Stage 3: AI Deployment Risk Agent                                   │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ python deployment_risk_agent.py → SAFE/RISKY/BLOCK           │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  Stage 4: GitOps Deploy (gitOpsEnabled: true)                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ UpdateReleaseRepo → Approval → MergePR → GitOpsSync → Verify│    │
│  │      (updates 11        (human       (merge to   (ArgoCD     │    │
│  │       image tags)        review)      main)      syncs)      │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  Rollback (auto on failure):                                         │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ RevertPR → MergePR (revert) → GitOpsSync (old version)      │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  OBSERVABILITY (ArgoCD Helm Apps — auto-sync + self-heal)            │
│                                                                       │
│  Prometheus + Grafana → kube-prometheus-stack 62.3.0 (auto-sync)     │
│  Elasticsearch 7.17   → elastic Helm chart (xpack trial, auth)       │
│  Kibana 7.17          → elastic Helm chart (native login screen)     │
│  Fluentd              → fluent Helm chart (DaemonSet, auto-sync)     │
│  Jaeger 3.1.1         → jaeger Helm chart (badger storage)           │
│  OTel Collector 0.97  → opentelemetry Helm chart (deployment mode)   │
│  All via Kong Ingress → 1 NLB → subdomains (grafana., kibana., etc.) │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  SECRETS (External Secrets Operator + Pod Identity)                   │
│                                                                       │
│  AWS Secrets Manager → ESO → K8s Secret → Pods (auto-refresh 1h)   │
│  Passwords auto-generated: Grafana, EFK, Kong Admin, JWT, RDS        │
│  No secrets in Git. No Harness runtime resolution needed.            │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  GOVERNANCE (OPA Policy — evaluated On Run)                          │
│                                                                       │
│  Rules: No Friday deploys │ Require approval │ Require rollback     │
│         No hardcoded IDs  │ Must use KubernetesDirect               │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  CONTINUOUS VERIFICATION (3 Health Sources — auto-rollback)           │
│                                                                       │
│  Monitored Service: online-boutique-production                       │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Health Source 1: Prometheus (Metrics — infrastructure)           │ │
│  │   Query: kube_pod_container_status_restarts_total                │ │
│  │   Detects: Pod crash-loops, restarts after deploy                │ │
│  ├─────────────────────────────────────────────────────────────────┤ │
│  │ Health Source 2: Prometheus (Metrics — HTTP 5xx via Kong)        │ │
│  │   Query: kong_http_requests_total{code=~"5.."}                   │ │
│  │   Detects: App returning 502/503/500 to real users               │ │
│  ├─────────────────────────────────────────────────────────────────┤ │
│  │ Health Source 3: Elasticsearch (Logs — application errors)       │ │
│  │   Index: fluentd-*  Query: namespace:online-boutique AND error   │ │
│  │   Detects: Exceptions, stack traces, error log spikes            │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  Verify Step (5 min, MEDIUM sensitivity):                            │
│    Compares pre-deploy vs post-deploy for ALL 3 health sources       │
│    ANY anomaly detected → automatic rollback (RevertPR → Sync)       │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  NOTIFICATIONS                                                        │
│                                                                       │
│  Slack: Pipeline success/failure                                     │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Pipeline Steps Explained

| # | Step | Type | What It Does |
|---|------|------|-------------|
| **Stage 1: security-scans** | | **CI (KubernetesDirect)** | **DevSecOps — 5 parallel security scans** |
| 1.1 | Gitleaks Scan | Run (parallel) | Detects hardcoded secrets/passwords in source code. Image: `zricethezav/gitleaks:latest`. Outputs JSON report. Fails if leaks found. |
| 1.2 | Trivy Scan | Run (parallel) | Filesystem vulnerability scan (HIGH+CRITICAL). Image: `aquasec/trivy:latest`. Scans `Episode-10/src/` directory. |
| 1.3 | OSV Dependency Scan | Run (parallel) | Google OSV scanner — checks all dependencies for known CVEs. Recursive scan of all package manifests. |
| 1.4 | SonarQube Analysis | Run (parallel) | Code quality + security analysis. Connects to SonarQube on Bastion (`<+variable.sonar_host_url>`). 3Gi memory. |
| 1.5 | Checkov IaC Scan | Run (parallel) | Infrastructure-as-Code security. Scans Terraform + K8s manifests for misconfigurations (uses `.checkov.yaml` for suppressions). |
| **Stage 2: build-and-push** | | **CI (KubernetesDirect)** | **Build 11 microservice Docker images → Push to ECR** |
| 2.1 | Restore Cache | RestoreCacheS3 | Restores Go modules, npm packages, Gradle deps from S3 (speeds up builds). |
| 2.2 | Push Frontend | BuildAndPushECR (batch 1) | Go multi-stage build. Tag: `v<sequenceId>`. Remote cache in ECR `cache` repo. 4Gi RAM. |
| 2.3 | Push CartService | BuildAndPushECR (batch 1) | .NET build. 4Gi RAM. |
| 2.4 | Push CheckoutService | BuildAndPushECR (batch 1) | Go build. 3Gi RAM. |
| 2.5 | Push ProductCatalog | BuildAndPushECR (batch 2) | Go build. 3Gi RAM. |
| 2.6 | Push CurrencyService | BuildAndPushECR (batch 2) | Node.js build. 2Gi RAM. |
| 2.7 | Push EmailService | BuildAndPushECR (batch 2) | Python build. 2Gi RAM. |
| 2.8 | Push PaymentService | BuildAndPushECR (batch 3) | Node.js build. 2Gi RAM. |
| 2.9 | Push RecommendationService | BuildAndPushECR (batch 3) | Python build. 2Gi RAM. |
| 2.10 | Push ShippingService | BuildAndPushECR (batch 3) | Go build. 3Gi RAM. |
| 2.11 | Push AdService | BuildAndPushECR (batch 4) | Java/Gradle build. 4Gi RAM (heaviest). |
| 2.12 | Push LoadGenerator | BuildAndPushECR (batch 4) | Python build. 2Gi RAM. |
| 2.13 | Prepare Cache Dirs | Run | Creates cache directories for S3 save step. |
| 2.14 | Save Cache | SaveCacheS3 | Saves Go/npm/Gradle caches to S3 for next run. |
| **Stage 3: ai-agents** | | **CI (KubernetesDirect)** | **5 AI Agents (Google Gemini) analyze the deployment** |
| 3.1 | AI Security Agent | Run (parallel) | Analyzes pipeline security scan context. Generates AI-powered security assessment report. |
| 3.2 | AI Code Review Agent | Run (parallel) | Reviews recently changed files (last 5 commits). Finds bugs, security issues, performance problems. Gives score 1-10. |
| 3.3 | AI Release Notes Agent | Run (parallel) | Analyzes last 20 git commits. Generates release notes with contributors, commit table, categorized changes. |
| 3.4 | AI Deployment Risk Agent | Run (parallel) | Evaluates risk: environment, test status, file count, time of day, vulnerabilities. Returns SAFE/RISKY/BLOCK. |
| 3.5 | AI Log Analysis Agent | Run (parallel) | Analyzes recent git log for patterns. Identifies risky changes and deployment concerns. |
| **Stage 4: gitops-deploy** | | **Deployment (GitOps)** | **Production deploy via ArgoCD (PR → Approve → Merge → Sync → Verify)** |
| 4.1 | Update Release Repo | GitOpsUpdateReleaseRepo | Creates PR updating all 11 image tags in `values.yaml`. PR title: "Deploy Online Boutique build #N". |
| 4.2 | Approve Deployment | HarnessApproval | Human approval gate. Any project user can approve. Timeout: 1 day. |
| 4.3 | Merge PR | MergePR | Merges the PR into main branch. Deletes source branch. ArgoCD watches main. |
| 4.4 | Sync Application | GitOpsSync | Triggers immediate ArgoCD sync (prune enabled). Doesn't wait for 3-min poll interval. |
| 4.5 | Get App Status | GitOpsGetAppDetails | Checks ArgoCD app health: Synced/Healthy/Degraded/Progressing. |
| 4.6 | Verify Deployment | Verify (CV) | Continuous Verification — 5 min, LOW sensitivity. Compares pre vs post deploy metrics (Prometheus: pod restarts, CPU, memory) + logs (Elasticsearch: error patterns). ANY anomaly → triggers rollback. |
| **Rollback (auto on Stage 4 failure)** | | **Auto** | **Reverts Git commit → ArgoCD syncs old version** |
| R1 | Revert PR | RevertPR | Creates revert of the deploy commit from step 4.1. |
| R2 | Merge Revert PR | MergePR | Merges revert into main. Old image tags restored in values.yaml. |
| R3 | Rollback Sync | GitOpsSync | ArgoCD syncs reverted state → previous working version deployed. |
| **Stage 5: dast-owasp-zap** | | **CI (KubernetesDirect)** | **DAST — Scans LIVE deployed app for web vulnerabilities** |
| 5.1 | OWASP ZAP Baseline Scan | Run | Spiders `https://app.<domain>` for 1 min. Passive scans all responses. Outputs HTML+JSON reports. Uploads HTML to S3 with presigned URL (7-day access). 4Gi RAM. |
| **Notifications** | | **Slack** | **Pipeline success/failure alerts to Slack channel** |

---

## Prerequisites (Already Done in Episodes 1-9)

| What | Used In Pipeline As | Created In | Link |
|------|---------------------|-----------|------|
| GitHub connector | `connectorRef: account.Github` | Episode 1 | [Episode 1 — Step 3](../Episode-01/hello-world-app/DEPLOY-STEPS.md#step-3-create-a-github-connector-first-time-only) |
| Docker Hub connector | `connectorRef: dockerhub` | Episode 2 | [Episode 2 — Step 5](../Episode-02/README.md#step-5-create-docker-hub-connector) |
| AWS OIDC connector | `connectorRef: account.aws_account` | Episode 3 | [Episode 3 — Connector 3](../Episode-03/README.md#connector-3-aws--create-now) |
| Variable: `aws_account_id` | `<+variable.aws_account_id>` | Episode 4 | [Episode 4 — Step 1](../Episode-04/README.md#step-1-add-variable-aws_account_id-in-harness) |
| Variable: `aws_region` | `<+variable.aws_region>` | Episode 3 | [Episode 3 — Step 4](../Episode-03/terraform-project/README.md#step-4-add-variables-in-harness) |
| S3 bucket (Terraform state) | GitHub Actions backend | Episode 3 | [kubernetes/README.md — Step 4](../kubernetes/README.md#step-4-create-s3-bucket-terraform-state) |
| GitHub OIDC → AWS IAM role | GitHub Actions auth | Episode 3 | [kubernetes/README.md — Step 2](../kubernetes/README.md#step-2-create-iam-role-for-github-actions) |
| GitHub variable: `AWS_ROLE_ARN` | GitHub Actions | Episode 3 | [kubernetes/README.md — Step 5](../kubernetes/README.md#step-5-add-github-variables) |
| GitHub variable: `S3_BUCKET_NAME` | GitHub Actions | Episode 3 | [kubernetes/README.md — Step 5](../kubernetes/README.md#step-5-add-github-variables) |
| GitHub environment: `production` | GitHub Actions | Episode 3 | [kubernetes/README.md — Step 6](../kubernetes/README.md#step-6-create-github-environment) |

> **All of the above must be done BEFORE running Episode 10.** If you followed Episodes 1-9, these already exist. Click links above if anything is missing.

---

## Prerequisites (New for Episode 10 — Already Configured)

### A. AWS vCPU Quota Increase (REQUIRED)

> **Without this, Terraform apply will fail** when creating the CI node group.

1. Go to **AWS Console** → **Service Quotas** → **EC2**: https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-1216C47A
4. Click **"Request increase at account level"**
5. Set value to **32** (default is 5 or 16, we need at least 20)
6. Click **Request**
7. Wait for approval (usually 5-30 minutes for small increases)

> **Why?** The EKS cluster uses ~14 vCPUs total:
> - Workloads: 4 × t3a.large = 8 vCPU
> - Bastion: 1 × t2.medium = 2 vCPU
> - CI Builds: 1 × t3a.xlarge = 4 vCPU
> - **Total: 14 vCPU** (needs quota of at least 32 for autoscaling headroom)
>
> The default AWS limit of 5-16 vCPUs is not enough. Every production AWS account needs this increase.

### B. Domain + Route53 + ACM Certificate

> These are already configured and will be reused for this project. No action needed.

| Resource | Status | Details |
|----------|--------|---------|
| **Domain** | ✅ Already registered | Your custom domain in Route53 |
| **Hosted Zone** | ✅ Already exists | Route53 hosted zone with NS records |
| **ACM Certificate** | ✅ Already issued | Wildcard `*.yourdomain.com` — DNS validated |

After `terraform apply`, **ExternalDNS automatically creates Route53 records** when Ingress resources are applied. No manual CNAME creation needed.

| Record | Type | Auto-Created By |
|--------|------|----------------|
| `app.yourdomain.com` | CNAME → NLB | ExternalDNS (from k8s/templates/ingress.yaml) |
| `grafana.yourdomain.com` | CNAME → NLB | ExternalDNS (from ArgoCD monitoring app) |
| `kibana.yourdomain.com` | CNAME → NLB | ExternalDNS (from Terraform Kibana ingress) |
| `jaeger.yourdomain.com` | CNAME → NLB | ExternalDNS (from ArgoCD Jaeger app) |
| `kong.yourdomain.com` | CNAME → NLB | ExternalDNS (from Kong Manager ingress) |

> On `terraform destroy`, ExternalDNS deletes ONLY these records. Your other Route53 records (NS, SOA, MX) are untouched.

---

## Step 1: Create Harness API Key

1. Login to Harness → https://app.harness.io
2. Bottom-left → Click your **avatar** → **My Profile**
3. Scroll down to **API Key** section
4. Click **+ API Key**
   - Name: `terraform-key`
   - Type: keep default
   - Click **Save**
5. Inside the API Key, click **+ Token**
   - Name: `ep10-token`
   - Expiry: 30 days
   - Click **Generate Token**
6. **COPY THE TOKEN NOW** (starts with `pat.xxxx...`)
   - You will NOT see this again after closing the dialog
   - Save it somewhere safe temporarily (you'll paste it in Step 3)

---

## Step 2: Get Delegate Token

1. Go to **Project Settings** (left sidebar → gear icon at bottom)
2. Click **Delegates** → Click **Tokens** tab (top)
3. You'll see a default token listed
4. Click the **copy icon** next to the token value
5. Save it — you'll paste it in Step 3

> If no token exists: Click **+ New Token** → Name: `ep10-delegate-token` → Click **Generate** → Copy

---

## Step 3: Add GitHub Secrets & Variables

1. Go to your GitHub repo → **Settings** tab (top)
2. Left sidebar → **Secrets and variables** → **Actions**

**Add Variables (click Variables tab → + New repository variable):**

| Name | Value | How to Get |
|------|-------|-----------|
| `HARNESS_ACCOUNT_ID` | Your 22-character Account ID | Harness → Account Settings → Overview → Account ID |
| `DOMAIN_NAME` | `yourdomain.com` | Your Route53 registered domain |
| `CLUSTER_NAME` | `ep10-enterprise-cluster` | (or any name you prefer) |
| `HARNESS_PROJECT_ID` | `HarnessCICDZerotoHero` | Harness → Project name → URL shows identifier |
| `HARNESS_ORG_ID` | `default` | Harness → Organization identifier (most users: `default`) |
| `AWS_REGION` | `us-east-1` | AWS region where you want to deploy |
| `GIT_BRANCH` | `master` | Your default Git branch (`master` or `main`) |

> All 7 variables are **required**.
**Add Secrets (click Secrets tab → + New repository secret):**

| Name | Value | How to Get |
|------|-------|-----------|
| `HARNESS_API_KEY` | `pat.xxxx...` | From Step 1 (the token you copied) |
| `HARNESS_DELEGATE_TOKEN` | Token string | From Step 2 (the delegate token) |
| `GH_PAT` | `ghp_xxxxx...` | GitHub → Settings → Developer Settings → Personal Access Tokens → Generate new (classic) → Select `repo` scope → Copy token |

> **Why GH_PAT?** ArgoCD needs write access to create PRs (UpdateReleaseRepo step updates image tags in values.yaml). This is the same PAT you used in Episode 9 for GitOps repository credentials.

> **Grafana, EFK, Kong passwords** are auto-generated by Terraform and stored in AWS Secrets Manager. No GitHub Secret needed for them.

> **Already should exist** (from Episode 3): `AWS_ROLE_ARN`, `S3_BUCKET_NAME`. If missing, see [kubernetes/README.md — Step 5](../kubernetes/README.md#step-5-add-github-variables).


---

## Step 4: Run Terraform (Create EVERYTHING — One Command)

1. Go to GitHub repo → **Actions** tab
2. Left sidebar → Click **"Episode 10 — Harness Automation Setup"**
3. Click **Run workflow** (top-right dropdown)
4. Select:
   - Branch: `main`
   - action: **apply**
5. Click green **Run workflow** button
6. Wait ~20 minutes (EKS cluster creation takes time)
7. After completion → Click the run → See **Summary** tab for all details

**What gets created automatically (zero manual clicks):**

| Category | Resources |
|----------|-----------|
| **AWS Infrastructure** | VPC, 4 subnets, NAT Gateway, Internet Gateway, Route Tables |
| **EKS** | Cluster (Auto Mode), IAM roles, KMS encryption, Security Group |
| **Bastion** | EC2 (t2.medium), SSM access, kubectl, Helm, Docker, SonarQube |
| **RDS** | PostgreSQL 16.3 (private subnet, encrypted, credentials auto-stored in AWS SM) |
| **Delegate** | K8s Delegate (HA — 2 replicas, autoscale to 6, 2Gi-4Gi memory) |
| **CI NodePool** | Karpenter NodePool `ci-builds` (xlarge/2xlarge instances, auto-scales to 64 CPU, auto-terminates when idle) |
| **GitOps Agent** | ArgoCD (HA — controller×2, repo-server×2→5, server×2→4, redis×2) |
| **ECR** | 11 repositories + lifecycle policy (delete untagged after 7 days) |
| **ALB Controller** | AWS Load Balancer Controller (1 shared ALB for all services) |
| **ESO** | External Secrets Operator (pulls secrets from AWS SM → K8s) |
| **Harness Service** | `online-boutique` (ReleaseRepo type → points to values.yaml) |
| **Harness Environments** | `development` (PreProduction) + `production` (Production) |
| **Harness Connectors** | Prometheus, AWS Secrets Manager, Kubernetes |
| **Harness OPA** | Policy (`production-governance.rego`) + PolicySet (On Run, severity: error) |
| **Harness Monitored Service** | `online_boutique_production` (Prometheus health source for CV) |
| **ArgoCD Apps** | monitoring (Helm), logging (Git), jaeger (Helm), otel-collector (Git) |
| **Ingress** | Kibana ingress via shared ALB |
| **Secrets** | AWS SM: `online-boutique/app-secrets` (you fill) + `online-boutique/db-credentials` (auto-filled by Terraform) |
| **RBAC** | ClusterRole + ClusterRoleBinding for delegate (pod create permissions) |

---

## Step 5: Verify in Harness UI + Cluster

After Terraform completes, verify everything appeared:

**5.0 — EKS Cluster Verification (run on Bastion via SSM):**
```bash
# Connect to EKS
aws eks update-kubeconfig --name ep10-enterprise-cluster --region us-east-1

# Verify nodes are ready (should see 4 nodes: 3 workload + 1 CI)
kubectl get nodes -o wide

# Verify node groups with labels
kubectl get nodes -L role,purpose

# Expected:
# NAME          STATUS   ROLES    AGE   VERSION   ROLE        PURPOSE
# ip-10-0-...   Ready    <none>   5m    v1.31     workloads
# ip-10-0-...   Ready    <none>   5m    v1.31     workloads
# ip-10-0-...   Ready    <none>   5m    v1.31     workloads
# ip-10-0-...   Ready    <none>   5m    v1.31                 ci-builds

# Verify AWS Load Balancer Controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify Cluster Autoscaler is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler

# Verify EBS CSI Driver is running
kubectl get pods -n kube-system -l app=ebs-csi-controller

# Verify Pod Identity Agent is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent

# Verify all EKS addons are ACTIVE
aws eks list-addons --cluster-name ep10-enterprise-cluster --region us-east-1
```

> All pods should be Running. If any are Pending/CrashLoop, check `kubectl describe pod <pod-name> -n kube-system` for the reason.

**5.1 — Delegate:**
1. Go to **Project Settings → Delegates**
2. Should see: `eks-k8s-delegate` — Status: ● **Connected** (2 replicas)
3. If not connected: wait 2-3 min, refresh

**5.2 — GitOps Agent:**
1. Go to **GitOps → Settings → GitOps Agents**
2. Should see: `ep10-gitops-agent` — Status: ● **Healthy**

**5.3 — Service:**
1. Go to **Deployments → Services**
2. Should see: `online-boutique`
3. Click it → verify Manifest type = Release Repo, Artifact = ECR

**5.4 — Environments:**
1. Go to **Deployments → Environments**
2. Should see: `development` (Pre-Production) + `production` (Production)

**5.5 — Connectors:**
1. Go to **Project Settings → Connectors**
2. Click each → **Test Connection**:
   - `prometheus` → ✅
   - `aws_secrets_manager` → ✅
   - `k8sdelegate` → ✅

**5.6 — OPA Policy:**
1. Go to **Project Settings → Governance → Policies**
2. Should see: `Production Governance` (active)
3. Click **Policy Sets** tab → `Production Policy Set` (enabled, On Run)

---

## Step 6: Add Secrets in AWS Secrets Manager

1. Go to **AWS Console** → **Secrets Manager** (https://console.aws.amazon.com/secretsmanager)

**6.1 — App Secrets (you fill manually):**
1. Find secret: `online-boutique/app-secrets`
2. Click on it → Click **"Retrieve secret value"** → **Edit**
3. Switch to **Key/value** tab
4. Add your key-value pairs:

| Key | Value | Used By |
|-----|-------|---------|
| `REDIS_ADDR` | `redis-cart:6379` | cartservice |
| `OTEL_ENDPOINT` | `otel-collector.tracing.svc.cluster.local:4317` | all services (tracing) |

5. Click **Save**

**6.2 — DB Credentials (auto-filled by Terraform — no action needed):**
- Secret: `online-boutique/db-credentials`
- Contains: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_URL`
- Terraform generated a random 24-char password and stored everything automatically
- ESO pulls this into K8s Secret `db-credentials` → all pods get these env vars

> ESO polls AWS SM every 1 hour. To force immediate refresh: `kubectl delete externalsecret app-secrets -n online-boutique` → ESO recreates it within 30 seconds.

**6.3 — Elasticsearch Connector (refresh after first apply):**
1. Go to **AWS Console → Secrets Manager** → find `online-boutique/efk-password`
2. Click **"Retrieve secret value"** → copy the `password` value
3. Go to **Harness → Project Settings → Secrets** → find `elk_password`
4. Click **Edit** → paste the password from step 2 → **Save**
5. Go to **Harness → Project Settings → Connectors** → find `elasticsearch`
6. Click **Edit** → click **Next** → **Next** → **Save** (just re-save without changes)
7. Click **Test Connection** → should show **Success**

> This step is needed only on first deployment. Harness CV caches connector credentials internally. Re-saving the connector refreshes the cache so the Verify step can authenticate to Elasticsearch.

---

## Step 7: Create Secrets in Harness (Manual — NOT automated by Terraform)

> These secrets are used by the pipeline at runtime. They can't be in Terraform because they're personal tokens (different per user).

**7.1 — Create Secrets:**
1. Go to **Project Settings → Secrets → + New Secret → Text**
2. Secret Manager: **Harness Built-in Secret Manager** (default)
3. Create each:

| # | Secret Name (ID) | Value | Where to Get |
|---|-----------------|-------|-------------|
| 1 | `ai_api_key` | `sk-proj-...` OR `AIzaSy...` | OpenAI: https://platform.openai.com/api-keys OR Gemini: https://aistudio.google.com/apikey (either one works) |
| 2 | `slack_webhook_url` | `https://hooks.slack.com/services/T.../B.../xxx` | Slack App → Incoming Webhooks → Add to channel → Copy URL |
| 3 | `sonar_token` | `squ_xxx...` | http://BASTION-IP:9000 → Login (admin/admin) → My Account → Security → Generate Token |

**7.2 — Create Variable:**

> **`sonar_host_url` is auto-created by Terraform** — it reads the bastion IP and sets `http://BASTION-IP:9000` automatically. No manual step needed.

---

## Step 8: Import Pipeline from Git

1. Go to **Pipelines** (left sidebar)
2. Click **+ Create a Pipeline**
3. Select **Import from Git**
4. Fill in:
   - **Git Connector:** `account.Github`
   - **Repository:** `Harness-CI-CD-Zero-to-Hero`
   - **Git Branch:** `main`
   - **YAML Path:** `Episode-10/.harness/enterprise-gitops-pipeline.yaml`
5. Click **Import Pipeline**
6. Pipeline appears: `ep10-enterprise-gitops`

---

## Step 9: Run Enterprise Pipeline (First Run)

1. Click **Run Pipeline**
2. Select branch: `main`
3. Click **Run Pipeline**

**First run flow:**
```
🔍 Security Scans (Gitleaks + Trivy + OWASP + SonarQube)... ✅ (2-3 min)
🐳 Build 11 images → Push to ECR (OIDC)................... ✅ (5-8 min)
🛡️ AI Security Agent → report generated.................... ✅ (30s)
🎯 AI Risk Agent → SAFE................................... ✅ (30s)
📝 Update Release Repo (creates PR with 11 image tags)..... ✅
⏸️ Approve Deployment...................................... ⏳ Click "Approve"
🔀 Merge PR → merged to main.............................. ✅
🔄 GitOps Sync → ArgoCD syncs cluster..................... ✅
📊 Get App Status → Healthy............................... ✅
✅ Verify Deployment (Prometheus CV)....................... ✅
📱 Slack: "Pipeline #1 succeeded".......................... ✅
```

> **Note:** First run may take longer (images building from scratch, no cache yet). Subsequent runs are faster (cache hits).

---

## Step 10: Verify Application is Running

**10.1 — Check in Harness GitOps:**
1. Go to **GitOps → Applications**
2. `online-boutique` should show: **Synced** ✅ + **Healthy** ✅

**10.2 — Check from Bastion (optional):**
```bash
# Connect to bastion
aws ssm start-session --target INSTANCE-ID --region us-east-1

# Check pods
kubectl get pods -n online-boutique

# All should be Running (11 services + redis + loadgenerator)
```

**10.3 — Access URLs:**

| Service | URL | Login |
|---------|-----|-------|
| Online Boutique | `https://app.yourdomain.com` | No login |
| Kong Manager | `https://kong.yourdomain.com` | admin / (see AWS SM: `online-boutique/kong-admin-password`) — Basic Auth prompt |
| Grafana | `https://grafana.yourdomain.com` | admin / (see AWS SM: `online-boutique/grafana-password`) |
| Kibana | `https://kibana.yourdomain.com` | elastic / (see AWS SM: `online-boutique/efk-password`) — Native xpack login |
| Jaeger | `https://jaeger.yourdomain.com` | No login |
| Falco (Runtime Security) | `https://falco.yourdomain.com` | admin / (see AWS SM: `online-boutique/falco-password`) |
| SonarQube | `http://BASTION-IP:9000` | admin / admin |

---

## Step 11: Test Rollback

1. Edit `Episode-10/src/frontend/main.go` — add invalid code (e.g., `asdfghjkl` on line 5)
2. Commit + push to `main`
3. Run pipeline again → CI builds broken image → pushes to ECR
4. GitOps stage: UpdateReleaseRepo → Approve → Merge → Sync
5. ArgoCD syncs → pods crash → Verify step detects degradation
6. **Automatic rollback:**
   - RevertPR creates revert commit
   - MergePR merges revert to main
   - GitOpsSync syncs reverted state
   - Old working version is back ✅
7. Slack notification: "Pipeline failed — auto-rolled back"

---

## Step 12: Destroy (Bill = $0)

1. GitHub → **Actions** → **"Episode 10 — Harness Automation Setup"**
2. Click **Run workflow**
3. Select:
   - action: **destroy**
   - confirm_destroy: **yes**
4. Click **Run workflow**
5. Wait ~10-15 minutes

**Everything deleted:**
- EKS cluster + all pods/services
- VPC + subnets + NAT + Internet Gateway
- Bastion EC2
- ECR repositories (all images deleted)
- EBS volumes
- Load Balancers
- All Harness resources (service, envs, connectors, policies)
- CloudWatch log groups

**Your AWS bill = $0 after destroy completes.**

---

## Cost

| Resource | Per Day | Per Month |
|----------|---------|-----------|
| EKS cluster (Auto Mode) | ~$2.40 | ~$72 |
| RDS PostgreSQL (db.t3.micro) | ~$0.50 | ~$15 |
| Bastion EC2 (t2.medium) | ~$1.10 | ~$33 |
| NAT Gateway | ~$1.10 | ~$33 |
| ALB (1 shared) | ~$0.70 | ~$21 |
| EBS volumes | ~$0.20 | ~$6 |
| ECR storage | ~$0.10 | ~$3 |
| **TOTAL (running)** | **~$6.10** | **~$183** |
| **After destroy** | **$0.00** | **$0.00** |

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Terraform timeout on EKS | EKS takes ~15 min | Wait, re-run apply |
| Delegate not connecting | Token wrong/expired | Verify `HARNESS_DELEGATE_TOKEN` in GitHub secrets |
| OPA blocks pipeline | Friday deploy or missing approval | Change OPA policy or run Monday-Thursday |
| Pods ImagePullBackOff | ECR images don't exist | Run pipeline first (builds images) |
| GitOpsSync fails "no app" | Application not created | Check `gitops.tf` ran, verify in GitOps → Applications |
| Verify fails "no data" | Prometheus not scraping | Check monitoring ArgoCD app is Synced |
| ArgoCD app OutOfSync | First sync needs manual trigger | GitOps → Applications → Sync button |
| ALB not creating | Kong not running | `kubectl get pods -n kong` |
| ESO not creating secrets | Secret doesn't exist in AWS SM | Go to AWS Console → Secrets Manager → add values |
| Terraform destroy fails | ENIs/LBs not released | Wait 2 min, run destroy again (retry built-in) |
| Verify step 401 Elasticsearch | Harness CV perpetual task caches old credentials | Go to Connectors → elasticsearch → Edit → Save (re-save refreshes cache). Then re-run pipeline. |
| Elasticsearch readiness probe stuck 0/1 | Single-node ES waits for green status (impossible with 1 replica) | `clusterHealthCheckParams: wait_for_status=yellow&timeout=1s` already set in code |

---

## What Episode 10 Automates (vs Manual in Ep 6-9)

| Resource | Episodes 6-9 | Episode 10 |
|----------|-------------|-----------|
| EKS Cluster | `infra.yml` (separate workflow) | `terraform apply` (same command) |
| RDS Database | Not used (MySQL in K8s pod) | Terraform `aws_db_instance` (managed, encrypted, auto-backup) |
| K8s Delegate | Manual Helm install on Bastion | Terraform module `delegate` (HA + autoscale) |
| GitOps Agent | Manual in Harness UI | Terraform module `gitops` (HA) |
| ECR Repos | `aws ecr create-repository` in pipeline | Terraform module `ecr` (lifecycle policies) |
| Harness Service | Manual in UI (click, click, click) | Terraform module `harness-platform` |
| Harness Environment | Manual in UI | Terraform module `harness-platform` |
| Connectors | Manual in UI (3 screens each) | Terraform module `harness-platform` |
| OPA Policies | Manual in UI (paste Rego) | Terraform module `harness-platform` |
| Monitored Service | Manual after first deploy | Terraform module `harness-platform` |
| Observability | Harness pipeline + kubectl | Terraform module `observability` (ArgoCD Helm apps) |
| Secrets | Harness Built-in SM | External Secrets Operator + AWS SM (module `external-secrets`) |
| Database Credentials | Hardcoded in K8s secret | Auto-generated + stored in AWS SM (module `rds`) |
| Ingress | 4 LoadBalancers ($$$) | 1 ALB + Ingress (module `ingress`) |
| SonarQube Config | Single `sonar-project.properties` | Multi-service scan (11 source dirs) |
| Terraform Structure | Flat files | Production modules (11 reusable modules) |
| Total setup time | ~45 min clicking | ~20 min terraform apply |
