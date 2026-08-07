# Episode 9: GitOps & Observability — Deployment Steps

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  HARNESS CI + GITOPS PIPELINE                                     │
│                                                                    │
│  Stage 1: Build & Push (CI — runs on K8s delegate)                │
│  Builds Laravel Docker image, pushes to ECR, creates K8s secrets  │
│  ┌────────────┐  ┌──────────────────────┐  ┌──────────────────┐  │
│  │ Create ECR │→ │ BuildAndPushECR      │→ │ Create K8s       │  │
│  │ Repo       │  │ (OIDC, tag: v#)     │  │ Secrets (kubectl)│  │
│  └────────────┘  └──────────────────────┘  └──────────────────┘  │
│                                                                    │
│  Stage 2: GitOps Deploy (CD — gitOpsEnabled: true)                │
│  Pipeline updates Git, ArgoCD agent syncs cluster                 │
│  ┌──────────────────┐  ┌──────────┐  ┌─────────┐  ┌──────────┐  │
│  │UpdateReleaseRepo │→ │ Approval │→ │MergePR  │→ │GitOpsSync│  │
│  │(update values,   │  │ (human   │  │(merge to│  │(ArgoCD   │  │
│  │ create PR)       │  │  review) │  │ main)   │  │ syncs)   │  │
│  └──────────────────┘  └──────────┘  └─────────┘  └──────────┘  │
│         │                                                │        │
│         ▼                                                ▼        │
│  ┌──────────────────┐                    ┌──────────────────────┐ │
│  │ GetAppDetails    │                    │ App Status: Synced ✅│ │
│  │ (verify healthy) │                    │ Healthy ✅           │ │
│  └──────────────────┘                    └──────────────────────┘ │
│                                                                    │
│  Rollback (auto on failure):                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │
│  │ RevertPR         │→ │ MergePR (revert) │→ │ GitOpsSync       │ │
│  │ (uses commitId   │  │ (merges revert   │  │ (ArgoCD deploys  │ │
│  │  from step 4)    │  │  into main)      │  │  old version)    │ │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘ │
│                                                                    │
├──────────────────────────────────────────────────────────────────┤
│  GITOPS AGENT (in EKS cluster, namespace: gitops)                 │
│                                                                    │
│  Watches: GitHub repo → Episode-09/shop ecommerce app/k8s/       │
│  Action:  Auto-sync manifests to cluster after PR merged          │
│  Self-Heal: Reverts any manual drift (delete pod → recreated)     │
│                                                                    │
├──────────────────────────────────────────────────────────────────┤
│  OBSERVABILITY STACK (deployed via ArgoCD App-of-Apps)            │
│                                                                    │
│  Prometheus → Scrapes /nginx-status every 15s                     │
│  Grafana    → Dashboards (CPU, Memory, Requests, Latency)        │
│  EFK        → Elasticsearch + Fluentd + Kibana (logs)            │
│  Jaeger     → Distributed tracing (OpenTelemetry)                │
│  Alerts     → Slack on: HighErrorRate, PodCrash, MySQLDown       │
│                                                                    │
├──────────────────────────────────────────────────────────────────┤
│  NOTIFICATIONS                                                    │
│                                                                    │
│  Slack: Pipeline success/failure + alert firing                   │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
```

### Pipeline Steps Explained

| # | Step | Type | What It Does |
|---|------|------|-------------|
| **Stage 1** | | **CI** | **Builds image, pushes ECR, creates secrets** |
| 1 | Create ECR Repo | Run | Creates ECR repository if not exists |
| 2 | Build and Push to ECR | BuildAndPushECR | Builds Docker image, pushes with tag v# |
| 3 | Create App Secrets | Run | Creates K8s secret with app credentials via kubectl |
| **Stage 2** | | **GitOps CD** | **Updates Git, ArgoCD syncs cluster** |
| 4 | Update Release Repo | GitOpsUpdateReleaseRepo | Updates image tag in values.yaml, creates PR |
| 5 | Approve Deployment | HarnessApproval | Human reviews PR and approves |
| 6 | Merge PR | MergePR | Merges PR into main, deletes source branch |
| 7 | Sync Application | GitOpsSync | Triggers ArgoCD to sync NOW (not wait 3 min poll) |
| 8 | Get App Status | GitOpsGetAppDetails | Returns app health as JSON (Synced/Healthy/Degraded) |
| **Rollback** | | **Auto on failure** | **Reverts Git + merges revert + syncs old state** |
| R1 | Revert PR | RevertPR | Uses commitId from step 4 → creates revert commit → opens revert PR |
| R2 | Merge Revert PR | MergePR | Merges the revert PR → main goes back to old image tag |
| R3 | Rollback Sync | GitOpsSync | Forces ArgoCD sync → deploys previous version back |

### How GitOps Rollback Works

```


values.yaml BEFORE pipeline: image: shop-ecommerce:v3 (working)
                   ↓
Pipeline runs → UpdateReleaseRepo changes to: image: shop-ecommerce:v4
                   ↓
MergePR merges → GitOpsSync deploys v4 → v4 CRASHES (health check fails)
                   ↓
failureStrategy triggers rollbackSteps:
                   ↓
RevertPR → creates commit that reverts back to: image: shop-ecommerce:v3
MergePR → merges revert
GitOpsSync → ArgoCD deploys v3 again → app is healthy ✅

---

## Prerequisites (Already Done)

| What | Episode | Link |
|------|---------|------|
| GitHub connector (`account.Github`) | 1 | [Episode 1 — Step 3](../../Episode-01/hello-world-app/DEPLOY-STEPS.md#step-3-create-a-github-connector-first-time-only) |
| Docker Hub connector (`dockerhub`) | 2 | [Episode 2 — Prerequisites](../../Episode-02/python-project/DEPLOY-STEPS.md#prerequisites) |
| AWS OIDC connector (`account.aws_account`) | 3 | [Episode 3 — Connector 3](../../Episode-03/README.md#connector-3-aws--create-now) |
| Secret: `aws_access_key_id` | 3 | [Episode 3 — Step 2](../../Episode-03/terraform-project/README.md#step-2-get-aws-access-key--secret-key) |
| Secret: `aws_secret_access_key` | 3 | [Episode 3 — Step 3](../../Episode-03/terraform-project/README.md#step-3-add-secrets-in-harness) |
| Variable: `aws_account_id` | 4 | [Episode 4 — Step 1](../../Episode-04/README.md#step-1-add-variable-aws_account_id-in-harness) |
| Variable: `aws_region` | 3 | [Episode 3 — Step 4](../../Episode-03/terraform-project/README.md#step-4-add-variables-in-harness) |

> **Important:** Episode 9 uses `KubernetesDirect` (not Harness Cloud). This means every `Run` step needs `connectorRef: dockerhub` to pull container images. Harness Cloud (Episodes 1-8) pulled images internally without a connector. On KubernetesDirect, YOUR cluster pulls the image — so it needs a registry connector.

---

## Step 1: Create EKS Cluster

1. GitHub → Actions → **"EKS Terraform"** → Run workflow → `action: apply`
2. Wait ~12 minutes
3. Output: Bastion IP + Cluster name

---

## Step 2: SSH into Bastion + Install K8s Delegate

```bash
aws ssm start-session --target INSTANCE-ID --region us-east-1

aws eks update-kubeconfig --region us-east-1 --name harness-eks-cluster
kubectl get nodes
```

Install delegate:
1. Harness UI → Project Settings → **Delegates** → **+ New Delegate** → **Helm Chart**
2. Name: `eks-k8s-delegate`
3. On Bastion, run:

```bash
helm repo add harness-delegate https://app.harness.io/storage/harness-download/delegate-helm-chart/
helm repo update

helm upgrade -i eks-k8s-delegate harness-delegate/harness-delegate-ng \
  --namespace harness-delegate-ng --create-namespace \
  --set delegateName=eks-k8s-delegate \
  --set accountId=YOUR_ACCOUNT_ID \
  --set delegateToken=YOUR_TOKEN \
  --set managerEndpoint=https://app.harness.io \
  --set delegateDockerImage=harness/delegate:latest \
  --set replicas=1 \
  --set upgrader.enabled=true

kubectl get pods -n harness-delegate-ng
```

Wait 2 min → Harness UI → **Connected** ✅

- when you use **KubernetesDirect** for CI, Harness runs pipeline steps as pods using the `default` service account in `harness-delegate-ng` namespace. 

- By default, that service account has **zero permissions** — it can only run inside its own namespace. But our pipeline needs to:

- `kubectl apply` ArgoCD Applications in `gitops` namespace
- `kubectl get svc` in `monitoring`, `logging`, `tracing` namespaces
- `kubectl wait` for pods in other namespaces

Without `cluster-admin`, every `kubectl` command across namespaces fails with "Forbidden".


**Grant delegate permissions (one-time — production least-privilege, not cluster-admin):**
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: harness-delegate-role
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "namespaces", "secrets", "configmaps", "persistentvolumeclaims", "serviceaccounts", "events", "nodes", "nodes/proxy", "nodes/metrics"]
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]
  - apiGroups: ["argoproj.io"]
    resources: ["applications", "applicationsets", "appprojects"]
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterroles", "clusterrolebindings", "roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch", "create"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["servicemonitors", "prometheusrules"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: harness-delegate-binding
subjects:
  - kind: ServiceAccount
    name: default
    namespace: harness-delegate-ng
roleRef:
  kind: ClusterRole
  name: harness-delegate-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

---

**Verify permissions applied:**
```bash
kubectl get clusterrolebinding harness-delegate-binding
kubectl auth can-i create deployments --as=system:serviceaccount:harness-delegate-ng:default -n shop-ecommerce
```
> Should output: `yes`

## Step 3: Create K8s Connector (k8sdelegate)

1. Go to **Project Settings → Connectors → + New Connector**
2. Select **Kubernetes Cluster**
3. **Name:** `k8sdelegate`
4. **Details:** Select **Use the credentials of a specific Harness Delegate**
5. **Delegates Setup:** Select tag `eks-k8s-delegate`
6. **Connection Test:** ✅ Success
7. Click **Finish**

> This connector is used by pipelines for `KubernetesDirect` CI infrastructure (`connectorRef: k8sdelegate`).

---

## Step 4: Install Harness GitOps Agent

1. Go to **Harness → GitOps → Settings → GitOps Agents**
2. Click **+ New GitOps Agent**
3. **"Do you have any existing Argo CD or Flux instances?"** → Select **No** → Click **Start**
4. Fill in Overview:
   - **Name:** `gitopsagent`
   - **GitOps Operator:** Argo (default)
   - **Namespace:** `gitops`
5. Under **Advanced** (scroll down):
   - **Enable Helm Secrets Path Traversal:** ✅ Check (allows accessing secrets in Helm values from different paths)
   - **Enable ArgoCD Harness Plugin:** ✅ Check (required for `<+secrets.getValue()>` resolution)
   - Leave other Advanced settings empty
6.  Click **Continue**
7. Harness shows **Install Agent** screen (Helm Chart tab):
   - Click **"Download Values Yaml"** → saves `override.yaml` to your laptop
   - Transfer to Bastion: copy content → `nano override.yaml` → paste → save (Ctrl+X, Y, Enter)
   - On Bastion, run:

```bash
kubectl create namespace gitops
# Paste the Helm install command from Harness UI
```
```bash
# Add Helm repo
helm repo add gitops-agent https://harness.github.io/gitops-helm/

# Update repo
helm repo update gitops-agent

# Install agent (override.yaml must be in current directory)
helm install argocd gitops-agent/gitops-helm --values override.yaml --namespace gitops
```

9. Wait 2 min → Click **Continue** in Harness UI → Verification: **Healthy** ✅


---

## Step 5: Create GitOps Repository

1. Go to **Harness → GitOps → Settings → Repositories**
2. Click **+ New Repository**
3. **Specify Repository Type:** Select **Git**
4. **Overview** screen:
   - **Repository Name:** `Harness-CI-CD-Zero-to-Hero`
   - **GitOps Agent:** Select `gitopsagent` (from Step 3)
   - **Git Repository URL:** `https://github.com/YOUR-USER/Harness-CI-CD-Zero-to-Hero`
   - Click **Continue**
5. **Credentials** screen:
   - Select **"Specify Credentials For Repository"**
   - **Connection Type:** HTTPS
   - **Username:** your GitHub username
   - **Password/Token:** your GitHub PAT
   - Click **Continue**
6. **Verify Connection** → ✅ Success

---

## Step 6: Create Harness Service (GitOps)

> **Important:** For GitOps, the Service uses a **Release Repo Manifest** (not K8s Manifest). This tells the `GitOpsUpdateReleaseRepo` step which file to update

1. Go to **Services → + New Service**
2. **Name:** `shop-ecommerce` (ID auto-generates: `shopecommerce`)
3. **Setup:** Select **Inline**
4. Click **Save**
5. **Service Definition → Deployment Type:** Select **Kubernetes**
6. Check **Enable GitOps**
7. **Manifests → + Add Release Repo Manifest:**
   - Release Repo Store: **GitHub**
   - GitHub Connector: `account.Github`
   - Repo: `Harness-CI-CD-Zero-to-Hero`
   - Branch: `master`
   - File Path: `Episode-09/shop ecommerce app/k8s/values.yaml`
8. **Artifact → + Add Artifact Source:**
   - Type: ECR
   - Identifier: `ecr_image`
   - Connector: `account.aws_account`
   - Region: `<+variable.aws_region>`
   - Image Path: `shop-ecommerce`
   - Tag: `<+input>`
9. Click **Save**

---

## Step 7: Create Harness Environment + GitOps Cluster

**Environment:**
1. Go to **Project Settings → Environments → + New Environment**
2. **Name:** `production`
3. **Type:** Production

**Link GitOps Cluster to Environment:**
1. Open the `production` environment
2. Go to **GitOps Clusters** tab
3. Click **+ Select Cluster(s)**
4. Select the GitOps cluster from the agent installed in Step 4
   - Identifier: `incluster`
   - Agent: `gitopsagent`

> **Key difference from CD (Episodes 6-8):** In GitOps, there is NO Infrastructure Definition. Instead, you link GitOps Clusters directly to the Environment.

---

## Step 8: Configure Slack Notifications

### Step 8.1: Create Slack App + Webhook

1. Open: **https://api.slack.com/apps**
2. Click **Create New App** → **From scratch**
3. App Name: `Harness Notifications`, Workspace: select yours → **Create App**
4. Left sidebar → **OAuth & Permissions**
5. Under **Bot Token Scopes** → Add these scopes:
   - `chat:write` (send messages)
   - `chat:write.public` (send to any public channel)
6. Scroll up → Click **Install to Workspace** → **Allow**
7. Copy the **Bot User OAuth Token** (starts with `xoxb-...`)
8. Left sidebar → **Incoming Webhooks** → Toggle **ON**
9. Click **Add New Webhook to Workspace** → Select channel (e.g., `#deployments`) → **Allow**
10. Copy the **Webhook URL** (starts with `https://hooks.slack.com/services/...`)

### Step 8.2: Store Webhook URL in Harness

1. Go to **Project Settings** → **Secrets** → **+ New Secret** → **Text**
2. Secret ID: `slack_webhook_url`
3. Value: paste the Webhook URL from Step 8.1
4. Click **Save**

### Step 8.3: Add Webhook to User Group (for notifications to work)

1. Go to **Project Settings** → **User Groups** → click **`All Project Users`** (or `_project_all_users`)
2. Click **Edit**
3. Under **Notification Preferences** → find **Slack Webhook URL**
4. Paste the same webhook URL from Step 8.1
5. Save

> **How notifications work:**
> - Pipeline YAML has `notificationRules` with `webhookUrl: <+secrets.getValue("slack_webhook_url")>`
> - Harness sends Slack message on: Pipeline Success, Pipeline Failed
> - If YAML notifications don't work, the User Group webhook (Step 8.3) is the fallback

### Step 8.4: Create Slack Connector (Optional — for Bot features)

1. Go to **Project Settings** → **Connectors** → **+ New Connector**
2. Under **Communication Tools** → Select **Slack**
3. **Screen 1 (Overview):**
   - Name: `slack-notifications`
4. **Screen 2 (Authorization):**
   - Connection Mode: **Bot User Token**
   - Slack Bot User Token: Click **Create or Select a Secret** → **+ New Secret**
     - Secret Name: `slack_bot_token`
     - Value: paste your Slack Bot Token (from Step 8.1: `xoxb-...`)
     - Save
   - Select the secret `slack_bot_token`
5. **Screen 3 (Select Connectivity Mode):**
   - Select: **Connect through Harness Platform**
6. **Screen 4 (Connection Test):**
   - Click **Finish** → ✅ Success

---

## Step 9: Create Secrets in Harness (Built-in Secret Manager)

1. Go to **Project Settings → Secrets → + New Secret → Text**
2. Secret Manager: **Harness Built-in Secret Manager** (default)
3. Create these secrets:

| Secret ID | Value |
|-----------|-------|
| `shop_app_key` | `base64:dDJmWnVQYUhSME5SZGhKYW1WdnRSQkoyQzFYeWtyYWI=` |
| `shop_db_username` | `shop_admin` |
| `shop_db_password` | `ShopDB@2026secure` |
| `shop_stripe_key` | `pk_test_DUMMY_KEY_REPLACE_WITH_YOURS` |
| `shop_stripe_secret` | `sk_test_DUMMY_SECRET_REPLACE_WITH_YOURS` |
| `shop_mail_host` | `smtp.gmail.com` |
| `shop_mail_username` | `shopecommerce.notify@gmail.com` |
| `shop_mail_password` | `abcd efgh ijkl mnop` |

---

## Step 10: Create GitOps Application (Manual — BEFORE importing pipeline)

> **Important:** Create this application MANUALLY in the UI first. The pipeline does NOT create the application — it only UPDATES the image tag in an existing application. The order is:
> 1. Create Application (this step) → ArgoCD syncs current state from Git
> 2. Import pipeline (Step 12) → Pipeline builds new image → updates values.yaml → ArgoCD syncs new version

1. Go to **Harness → GitOps → Applications**
2. Click **+ New Application**
3. **Overview:**
   - **Application Name:** `shop-ecommerce`
   - **GitOps Operator:** Argo
   - **GitOps Agent:** `gitopsagent` (green, PROJECT)
   - **Source Namespace:** `gitops`
   - **Service:** Select `shop-ecommerce` (created in Step 6)
   - **Environment:** Select `production` (created in Step 7)
   - Click **Continue**
4. **Sync Policy:**
   - Select **Manual** (NOT Automatic yet — image doesn't exist in ECR until first pipeline run)
   - Check **Auto-Create Namespace**
   - Leave all other options unchecked
   - Click **Continue**

> **After first successful pipeline run (Step 13):** Come back here and enable Auto-Sync:
> 1. Go to **GitOps → Applications → `shop-ecommerce`**
> 2. Click **"App Details"** tab
> 3. Find **"Sync Policy"** section
> 4. Toggle **"Automated"** switch → ON
> 5. Now future Git changes will auto-deploy without running the pipeline
5. **Source:**
   - Repository: Select from Step 5
   - Path: `Episode-09/shop ecommerce app/k8s/`
   - Target Revision: `master`
6. **Destination:**
   - Cluster: `https://kubernetes.default.svc` (in-cluster)
   - Namespace: `shop-ecommerce`
7. Click **Finish**

> **Note:** The `k8s/` folder has a `Chart.yaml` — this tells the Harness ArgoCD plugin to process `values.yaml` with `<+secrets.getValue()>` expressions. Without `Chart.yaml`, the plugin fails.

---

## Step 11: Install Observability Stack (Prometheus + Grafana + EFK + Jaeger)

> **Fully automated!** One pipeline deploys everything via ArgoCD App-of-Apps.

1. Go to **Pipelines → + Create Pipeline → Import from Git**
2. YAML Path: `Episode-09/shop ecommerce app/.harness/observability-infra-pipeline.yaml`
3. Click **Run Pipeline**
4. Wait ~5 minutes — ArgoCD syncs all 3 stacks from Git
5. Pipeline output shows 3 LoadBalancer URLs:

```
1. GRAFANA:  http://xxx.elb.amazonaws.com     (admin / admin123)
2. KIBANA:   http://xxx.elb.amazonaws.com     (elastic / HarnessEFK@2026)
3. JAEGER:   http://xxx.elb.amazonaws.com
```

> ArgoCD App-of-Apps pattern — after this runs once, ArgoCD manages observability forever.

```bash
kubectl get applications -n gitops
```
```bash
kubectl get svc grafana -n monitoring
kubectl get svc kibana -n logging
kubectl get svc jaeger-query -n tracing
```
---

## Step 12: Create Prometheus Connector

1. Go to **Project Settings** → **Connectors** → **+ New Connector**
2. Select: **Monitoring and Logging Systems** → **Prometheus**
3. **Screen 1 (Overview):**
   - Name: `prometheus`
4. **Screen 2 (Credentials):**
   - URL: `http://prometheus.monitoring.svc.cluster.local:9090`
   - Authentication: leave **empty** (no username, no password, no headers)
5. **Screen 3 (Delegates Setup):**
   - Select: **Connect only via Delegates with tag** → `eks-k8s-delegate`
6. **Screen 4 (Connection Test):**
   - Click **Finish** → ✅ Success

---

## Step 13: Import Pipeline from Git

1. Go to **Pipelines → + Create Pipeline**
2. Select **Import from Git**
3. Configure:
   - Connector: `account.Github`
   - Repo: `Harness-CI-CD-Zero-to-Hero`
   - Branch: `master`
   - YAML Path: `Episode-09/shop ecommerce app/.harness/gitops-pipeline.yaml`

---
```bash
#Check the ArgoCD app status:
kubectl describe application shop-ecommerce -n gitops | grep -A5 "Message"
```
```bash
# Check app pods
kubectl get pods -n shop-ecommerce

# Check services (LoadBalancer URL)
kubectl get svc -n shop-ecommerce

# Check all observability
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n tracing

# Get all LoadBalancer URLs
kubectl get svc grafana -n monitoring
kubectl get svc kibana -n logging
kubectl get svc jaeger-query -n tracing
kubectl get svc shop-ecommerce -n shop-ecommerce
```

```bash
# Wait 2-3 minutes for ArgoCD to detect the change, then:
kubectl get pods -n shop-ecommerce
kubectl get svc -n shop-ecommerce

```


---

## Step 14: Configure Monitored Service (AFTER first successful deploy)

> This step is only possible AFTER the pipeline (Step 13) runs successfully. The Monitored Service auto-creates after the first deploy.

1. Go to left sidebar → **Monitored Services**
2. Find `shop-ecommerce_production` (auto-created after deploy)
3. Click on it → **+ Add Health Source**
4. Select: **Prometheus**
5. Configure:
   - Health Source Name: `prometheus-metrics`
   - Connector: Select `prometheus` (from Step 12)
   - Feature: **Prometheus Metrics**
6. **Metric Configuration:**
   - **Metric 1 (Request Count):**
     - Query: `sum(rate(nginx_http_requests_total{namespace="shop-ecommerce"}[5m]))`
     - Metric Name: `request_rate`
     - Category: Performance
     - Thresholds: Higher is better
   - **Metric 2 (Error Rate):**
     - Query: `sum(rate(nginx_http_requests_total{namespace="shop-ecommerce",status=~"5.."}[5m]))`
     - Metric Name: `error_rate`
     - Category: Errors
     - Thresholds: Lower is better
7. Click **Submit** → Save

> **After this:** Re-run the pipeline → the Verify step will now compare metrics before/after deployment. If degraded → auto-rollback.

---

## Step 15: Enable Auto-Sync

1. **GitOps** → **Applications** → `shop-ecommerce` → **App Details**
2. Find **Sync Policy** → Toggle **"Automated"** → ON
3. Now future Git changes auto-deploy without running the pipeline

---

## Step 16: Test Self-Heal

```bash
kubectl delete pod -l app=shop-ecommerce -n shop-ecommerce
kubectl get pods -n shop-ecommerce -w
# ArgoCD recreates the pod within seconds
```

---

## Troubleshooting: Reset Observability Stack

If observability apps are stuck (Progressing/Degraded), delete and recreate from scratch:

```bash
# Delete ArgoCD apps (cascades — deletes all pods/services)
kubectl delete application monitoring logging tracing -n gitops

# Delete namespaces (clean slate)
kubectl delete namespace monitoring logging tracing --ignore-not-found

# Wait for cleanup
sleep 30
```

Then re-run the `episode9-observability-infra` pipeline in Harness — it recreates everything from latest Git.

---

## Step 17: Cleanup

```bash
# Delete ArgoCD applications (this removes all observability pods)
kubectl delete application monitoring logging tracing -n gitops

# Delete GitOps application for the app
# Go to Harness UI → GitOps → Applications → Delete shop-ecommerce

# Delete namespaces (if ArgoCD didn't clean them)
kubectl delete namespace monitoring logging tracing shop-ecommerce

# Delete ECR repository
aws ecr delete-repository --repository-name shop-ecommerce --region us-east-1 --force

# Destroy EKS cluster (stop billing!)
# GitHub → Actions → "EKS Terraform" → destroy
```

---

## Notifications You'll Receive

| Event | Channel | Message |
|-------|---------|---------|
| Pipeline succeeds | Slack | "Pipeline Shop Ecommerce GitOps #N succeeded" |
| Pipeline fails | Slack | "Pipeline failed at stage X — view logs" |
| GitOps sync succeeds | Harness Dashboard | Application: Synced ✅ |
| GitOps drift detected | Harness Dashboard | Application: OutOfSync → Auto-healed |
| Alert fires (HighErrorRate) | Slack (via Alertmanager) | "CRITICAL: Error rate above 5%" |
| Pod crash looping | Slack (via Alertmanager) | "WARNING: Pod X restarting" |

---

## Key Concepts Demonstrated

| Concept | How It's Shown |
|---------|---------------|
| GitOps (Pull model) | Agent syncs from Git, no `kubectl apply` in pipeline |
| Self-Heal | Delete pod manually → agent recreates it |
| Auto-Sync | Push to Git → cluster updates within 3 min |
| Continuous Verification | Harness Verify compares pre/post metrics |
| Auto-Rollback | Verify fails → rollback GitOps sync |
| Prometheus Metrics | ServiceMonitor scrapes app every 15s |
| Grafana Dashboards | Visual CPU/Memory/Latency/Error graphs |
| Alert Rules | PrometheusRule fires on high errors/crashes |
| Notifications | Slack on pipeline and alert events |
| Secret Injection | `<+secrets.getValue()>` resolved by GitOps Agent plugin |

