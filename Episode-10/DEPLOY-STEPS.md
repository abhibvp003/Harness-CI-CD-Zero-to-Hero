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
│  │ Connectors  │  │ OPA Policy   │  │ Monitored  │  │ ALB Ingress│  │
│  │Prometheus   │  │ + PolicySet  │  │ Service    │  │ Controller │  │
│  │AWS SM, K8s  │  │ (On Run)     │  │ (CV)       │  │(1 ALB all) │  │
│  └─────────────┘  └──────────────┘  └────────────┘  └────────────┘  │
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
│  OBSERVABILITY (ArgoCD App-of-Apps — Helm charts)                    │
│                                                                       │
│  Prometheus + Grafana → kube-prometheus-stack Helm (auto-sync)       │
│  Jaeger              → jaeger Helm chart (auto-sync)                 │
│  OTel Collector      → Git manifests (auto-sync)                     │
│  EFK                 → Git manifests (auto-sync)                     │
│  All via Ingress → 1 ALB → subdomains (grafana., kibana., jaeger.)  │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  SECRETS (External Secrets Operator)                                  │
│                                                                       │
│  AWS Secrets Manager → ESO → K8s Secret → Pods (auto-refresh 1h)   │
│  No secrets in Git. No Harness runtime resolution needed.            │
│                                                                       │
├──────────────────────────────────────────────────────────────────────┤
│  GOVERNANCE (OPA Policy — evaluated On Run)                          │
│                                                                       │
│  Rules: No Friday deploys │ Require approval │ Require rollback     │
│         No hardcoded IDs  │ Must use KubernetesDirect               │
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
| **Stage 1** | | **CI (KubernetesDirect)** | **Security scans + Build 11 images** |
| 1 | Gitleaks Scan | Run (parallel) | Detects hardcoded secrets in source code |
| 2 | Trivy Scan | Run (parallel) | Finds vulnerabilities in source code filesystem |
| 3 | OWASP Dependency Check | Run (parallel) | Checks dependencies for known CVEs (fails CVSS 9+) |
| 4 | SonarQube Analysis | Run (parallel) | Code quality + security analysis |
| 5-15 | BuildAndPushECR × 11 | BuildAndPushECR (parallel) | Builds all microservices, pushes to ECR (OIDC) |
| **Stage 2** | | **CI** | **AI Security Analysis** |
| 16 | AI Security Agent | Run | Reads scan JSONs → generates prioritized report |
| **Stage 3** | | **CI** | **AI Risk Assessment** |
| 17 | AI Risk Agent | Run | Decides SAFE/RISKY/BLOCK based on context |
| **Stage 4** | | **GitOps CD** | **Deploy via ArgoCD** |
| 18 | Update Release Repo | GitOpsUpdateReleaseRepo | Updates ALL 11 image tags in values.yaml, creates PR |
| 19 | Approve Deployment | HarnessApproval | Human reviews and approves |
| 20 | Merge PR | MergePR | Merges PR into main, deletes source branch |
| 21 | Sync Application | GitOpsSync | Triggers ArgoCD sync immediately |
| 22 | Get App Status | GitOpsGetAppDetails | Returns health: Synced/Healthy/Degraded |
| 23 | Verify Deployment | Verify | Continuous Verification — compares Prometheus metrics |
| **Rollback** | | **Auto on failure** | **Reverts Git → ArgoCD syncs old version** |
| R1 | Revert PR | RevertPR | Reverts the commit from step 18 |
| R2 | Merge Revert PR | MergePR | Merges revert into main |
| R3 | Rollback Sync | GitOpsSync | ArgoCD syncs reverted state → old version deployed |
| **Notifications** | | **Slack** | **Success/failure alerts** |

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

### A. Domain + Route53 + ACM Certificate

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

> All 6 variables are **required**.
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

## Step 5: Verify in Harness UI

After Terraform completes, verify everything appeared:

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

---

## Step 7: Create Secrets in Harness (Manual — NOT automated by Terraform)

> These secrets are used by the pipeline at runtime. They can't be in Terraform because they're personal tokens (different per user).

**7.1 — Create Secrets:**
1. Go to **Project Settings → Secrets → + New Secret → Text**
2. Secret Manager: **Harness Built-in Secret Manager** (default)
3. Create each:

| # | Secret Name (ID) | Value | Where to Get |
|---|-----------------|-------|-------------|
| 1 | `openai_api_key` | `sk-proj-...` | https://platform.openai.com/api-keys → + Create new secret key |
| 2 | `slack_webhook_url` | `https://hooks.slack.com/services/T.../B.../xxx` | Slack App → Incoming Webhooks → Add to channel → Copy URL |
| 3 | `sonar_token` | `squ_xxx...` | http://BASTION-IP:9000 → Login (admin/admin) → My Account → Security → Generate Token |

**7.2 — Create Variable:**
1. Go to **Project Settings → Variables → + New Variable**
2. Create:

| Name | Type | Value |
|------|------|-------|
| `sonar_host_url` | String | `http://BASTION-IP:9000` (replace BASTION-IP with actual IP from Terraform output) |

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
| Kong Manager | `https://kong.yourdomain.com` | admin / (see AWS SM: `online-boutique/kong-admin-password`) |
| Grafana | `https://grafana.yourdomain.com` | admin / (see AWS SM: `online-boutique/grafana-password`) |
| Kibana | `https://kibana.yourdomain.com` | elastic / (see AWS SM: `online-boutique/efk-password`) |
| Jaeger | `https://jaeger.yourdomain.com` | No login |
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
