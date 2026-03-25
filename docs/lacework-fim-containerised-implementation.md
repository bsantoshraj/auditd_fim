# Implementing FIM Using Lacework FortiCNAPP in Containerised Environments

A step-by-step implementation guide for deploying File Integrity Monitoring (FIM) across
Kubernetes clusters using Lacework FortiCNAPP (formerly Lacework, acquired by Fortinet
August 2024).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Architecture Overview](#2-architecture-overview)
3. [Phase 1: Cloud Account Integration](#3-phase-1-cloud-account-integration)
4. [Phase 2: Deploy Lacework Agent on Kubernetes](#4-phase-2-deploy-lacework-agent-on-kubernetes)
5. [Phase 3: Configure FIM for Container Workloads](#5-phase-3-configure-fim-for-container-workloads)
6. [Phase 4: EKS Audit Log Integration](#6-phase-4-eks-audit-log-integration)
7. [Phase 5: Kubernetes Admission Controller](#7-phase-5-kubernetes-admission-controller)
8. [Phase 6: Polygraph Behavioural Baseline Tuning](#8-phase-6-polygraph-behavioural-baseline-tuning)
9. [Phase 7: Custom Policies and LQL Queries](#9-phase-7-custom-policies-and-lql-queries)
10. [Phase 8: Alert Routing and SIEM Integration](#10-phase-8-alert-routing-and-siem-integration)
11. [Phase 9: Compliance Evidence Generation](#11-phase-9-compliance-evidence-generation)
12. [Phase 10: Operationalisation and Runbook](#12-phase-10-operationalisation-and-runbook)
13. [Limitations and Gaps](#13-limitations-and-gaps)
14. [Reference Architecture Diagrams](#14-reference-architecture-diagrams)

---

## 1. Prerequisites

### Lacework Account Requirements

| Requirement | Detail |
|---|---|
| Lacework FortiCNAPP subscription | Enterprise tier (FIM requires Enterprise licence) |
| Lacework account region | US, EU, or AU (determines API endpoint) |
| API credentials | API key + secret from Settings > API Keys |
| Lacework CLI installed | `brew install lacework/tap/lacework-cli` or download from [GitHub](https://github.com/lacework/go-sdk) |

### Infrastructure Requirements

| Requirement | Detail |
|---|---|
| Kubernetes cluster | EKS, AKS, GKE, or self-managed (v1.10 - v1.30 supported) |
| Helm 3.x | For agent deployment |
| Terraform >= 1.0 | For cloud integrations and EKS audit log setup |
| kubectl access | Cluster admin role |
| Container runtime | containerd, CRI-O, or Docker (all supported) |

### Network Requirements

| Endpoint | Port | Purpose |
|---|---|---|
| `api.lacework.net` (US) | 443 | Agent → Lacework API |
| `api.fra.lacework.net` (EU) | 443 | Agent → Lacework API (EU tenants) |
| `api.aus.lacework.net` (AU) | 443 | Agent → Lacework API (AU tenants) |
| `ds.lacework.net` | 443 | Agent data submission |

Ensure Kubernetes nodes have outbound HTTPS to these endpoints. If using a proxy, configure
the agent with `HTTPS_PROXY` environment variable.

### Verify CLI Access

```bash
# Configure CLI
lacework configure
# Enter: account, API key, API secret, region

# Verify connectivity
lacework agent list
lacework policy list --severity critical
```

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                        │
│                                                            │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐          │
│  │ App Pod    │  │ App Pod    │  │ App Pod    │          │
│  │ (nginx)    │  │ (api)      │  │ (worker)   │          │
│  └────────────┘  └────────────┘  └────────────┘          │
│                                                            │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Lacework Agent DaemonSet (one per node)             │  │
│  │                                                      │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │ datacollector                                 │   │  │
│  │  │  ├ Process monitoring (all containers)        │   │  │
│  │  │  ├ File Integrity Monitoring (FIM)            │   │  │
│  │  │  ├ Network connection monitoring              │   │  │
│  │  │  ├ Host intrusion detection                   │   │  │
│  │  │  └ Vulnerability scanning                     │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  └────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Admission Controller (optional)                     │  │
│  │  ├ Proxy scanner (image vulnerability check)        │  │
│  │  └ Policy enforcement (block/warn on deploy)        │  │
│  └────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Cluster Agent (optional, for K8s compliance)        │  │
│  │  └ CIS Kubernetes Benchmark scanning                │  │
│  └────────────────────────────────────────────────────┘  │
│                                                            │
└──────────────────────────┬───────────────────────────────┘
                           │ HTTPS (443)
                           ▼
┌──────────────────────────────────────────────────────────┐
│                  Lacework FortiCNAPP SaaS                  │
│                                                            │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ Polygraph│  │ FIM Engine   │  │ Alert Engine      │  │
│  │ (ML      │  │ (hash-based  │  │ (anomaly +        │  │
│  │  baseline│  │  file change │  │  policy-based)     │  │
│  │  24-48h) │  │  detection)  │  │                    │  │
│  └──────────┘  └──────────────┘  └───────────────────┘  │
│                                                            │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ EKS Audit│  │ Vuln Scanner │  │ Compliance        │  │
│  │ Logs     │  │ (container   │  │ Reports           │  │
│  │          │  │  images)     │  │                    │  │
│  └──────────┘  └──────────────┘  └───────────────────┘  │
│                                                            │
└──────────────────────────────────────────────────────────┘
                           │
                           ▼ Webhooks / S3 / SIEM
┌──────────────────────────────────────────────────────────┐
│  SIEM / SOC (Splunk, Sentinel, SkieSecure, etc.)          │
└──────────────────────────────────────────────────────────┘
```

### How Lacework FIM Works in Containers

Lacework's approach to container FIM is **node-level, not pod-level**:

1. The agent runs as a **privileged DaemonSet** on every Kubernetes node
2. It has access to the **host PID namespace** and **host filesystem**
3. It monitors file changes across **all containers on that node** by inspecting the
   overlay filesystem layers at the host level (e.g., `/var/lib/containerd/`)
4. The **Polygraph engine** builds a behavioural baseline within 24-48 hours
5. FIM scans run periodically (default: daily) and detect new/changed/deleted files
6. Anomalous file changes trigger alerts with Polygraph context

**Key insight:** Lacework does NOT run inside containers. It monitors from the node level,
which means ephemeral pod lifecycle doesn't affect the agent — it persists on the node.

---

## 3. Phase 1: Cloud Account Integration

Before deploying agents, integrate your cloud account so Lacework has context about your
infrastructure.

### Step 1.1: AWS Account Integration (Terraform)

```bash
# Create a new Terraform workspace
mkdir -p lacework-integration && cd lacework-integration

cat > providers.tf << 'PROVIDERS_EOF'
terraform {
  required_version = ">= 1.0"
  required_providers {
    lacework = {
      source  = "lacework/lacework"
      version = "~> 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "lacework" {
  # Credentials from environment variables:
  #   LW_ACCOUNT, LW_API_KEY, LW_API_SECRET
}

provider "aws" {
  region = var.aws_region
}
PROVIDERS_EOF

cat > variables.tf << 'VARS_EOF'
variable "aws_region" {
  description = "AWS region for Lacework integration resources"
  type        = string
  default     = "us-east-1"
}

variable "lacework_integration_name" {
  description = "Name for the Lacework integration"
  type        = string
  default     = "fim-eks-integration"
}
VARS_EOF
```

### Step 1.2: CloudTrail Integration

```bash
cat > cloudtrail.tf << 'CT_EOF'
module "aws_cloudtrail" {
  source  = "lacework/cloudtrail/aws"
  version = "~> 3.0"

  # Use existing CloudTrail if you have one
  # use_existing_cloudtrail = true
  # bucket_arn              = "arn:aws:s3:::your-existing-trail-bucket"

  # Or create a new dedicated trail
  use_existing_cloudtrail = false
  bucket_force_destroy    = true

  # Enable SNS notifications for real-time processing
  use_existing_sns_topic = false
}
CT_EOF
```

### Step 1.3: Apply

```bash
export LW_ACCOUNT="your-lacework-account"
export LW_API_KEY="your-api-key"
export LW_API_SECRET="your-api-secret"

terraform init
terraform plan
terraform apply
```

### Step 1.4: Verify Integration

```bash
lacework integration list

# Expected output:
# INTEGRATION GUID          NAME                    TYPE         STATUS
# ABC123...                 fim-eks-integration     AwsCtSqs     Ok
```

---

## 4. Phase 2: Deploy Lacework Agent on Kubernetes

### Step 2.1: Obtain Agent Access Token

```bash
# Via CLI
lacework agent token list

# If no token exists, create one
lacework agent token create \
  --description "EKS FIM Agent Token" \
  --enabled

# Note the token value — you'll need it for Helm
export LACEWORK_AGENT_TOKEN="your-agent-token-here"
```

Or via console: **Settings > Agents > Agent Access Tokens > Create New**

### Step 2.2: Add Lacework Helm Repository

```bash
helm repo add lacework https://lacework.github.io/helm-charts/
helm repo update

# Verify
helm search repo lacework
# NAME                     CHART VERSION  APP VERSION
# lacework/lacework-agent  7.x.x         7.x.x
```

### Step 2.3: Create Namespace and Values File

```bash
kubectl create namespace lacework
```

Create the Helm values file with FIM-specific configuration:

```bash
cat > lacework-agent-values.yaml << 'VALUES_EOF'
# ============================================================
# Lacework Agent Helm Values — FIM for Containerised Workloads
# ============================================================

laceworkConfig:
  # --- Required ---
  accessToken: "${LACEWORK_AGENT_TOKEN}"

  # --- Cluster identification ---
  kubernetesCluster: "production-eks-01"
  env: "production"

  # --- Server URL (adjust for your region) ---
  # US:   https://api.lacework.net
  # EU:   https://api.fra.lacework.net
  # AU:   https://api.aus.lacework.net
  serverUrl: "https://api.lacework.net"

  # --- FIM Configuration ---
  # Enable FIM (requires Enterprise licence)
  fim:
    # Custom file paths to monitor (overrides defaults)
    # These paths are monitored ON THE HOST — which includes container overlay FS
    filepath:
      # --- Critical host paths (node-level) ---
      - "/etc/passwd"
      - "/etc/shadow"
      - "/etc/group"
      - "/etc/sudoers"
      - "/etc/sudoers.d"
      - "/etc/ssh"
      - "/etc/kubernetes"
      - "/etc/cni"
      - "/var/lib/kubelet/config.yaml"
      - "/var/lib/kubelet/kubeconfig"

      # --- Kubernetes PKI and secrets on disk ---
      - "/etc/kubernetes/pki"
      - "/etc/kubernetes/manifests"

      # --- Container runtime configuration ---
      - "/etc/containerd"
      - "/etc/docker"

      # --- System binaries ---
      - "/usr/bin"
      - "/usr/sbin"
      - "/usr/local/bin"

      # --- Persistent volume mount points (if applicable) ---
      # Add your PV mount paths here
      # - "/mnt/data"

    # Paths to EXCLUDE from monitoring
    fileignore:
      # --- High-churn paths that generate noise ---
      - "/var/log"
      - "/var/cache"
      - "/tmp"
      - "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs"
      - "/var/lib/docker/overlay2"
      - "/var/lib/kubelet/pods"
      - "/var/lib/kubelet/pod-resources"
      - "/run"
      - "/proc"
      - "/sys"

    # Scan frequency (default: 1440 = once per day in minutes)
    # For containerised environments, consider more frequent scans
    # Minimum: 60 (once per hour)
    # Recommended for production: 360 (every 6 hours)
    scanfrequencyminutes: 360

  # --- Process Monitoring ---
  # The agent monitors ALL processes across all containers on the node
  # No additional configuration needed — this is always on

  # --- Tags for identification ---
  tags:
    environment: "production"
    team: "platform-security"
    compliance: "pci-dss"
    fim-profile: "containerised"

# --- DaemonSet Configuration ---
# The agent needs privileged access to monitor all containers
daemonset:
  priorityClassName: "system-node-critical"

  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"

  # Tolerations to ensure agent runs on ALL nodes including masters
  tolerations:
    - effect: NoSchedule
      operator: Exists
    - effect: NoExecute
      operator: Exists

  # Node affinity — run on all Linux nodes
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                  - linux

# --- Cluster Agent (for Kubernetes compliance) ---
clusterAgent:
  enabled: true
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "200m"
      memory: "256Mi"

# --- Image settings ---
image:
  registry: "docker.io"
  repository: "lacework/datacollector"
  # Pin to specific version for reproducibility
  # tag: "7.x.x"
VALUES_EOF
```

### Step 2.4: Deploy the Agent

```bash
# Substitute the token
envsubst < lacework-agent-values.yaml > lacework-agent-values-rendered.yaml

# Install via Helm
helm upgrade --install lacework-agent lacework/lacework-agent \
  --namespace lacework \
  --values lacework-agent-values-rendered.yaml \
  --wait

# Verify deployment
kubectl -n lacework get daemonset
# NAME             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# lacework-agent   3         3         3       3            3

kubectl -n lacework get pods -o wide
# NAME                   READY   STATUS    NODE
# lacework-agent-abc12   1/1     Running   ip-10-0-1-100
# lacework-agent-def34   1/1     Running   ip-10-0-2-200
# lacework-agent-ghi56   1/1     Running   ip-10-0-3-300
```

### Step 2.5: Verify Agent Registration

```bash
# Wait 10-15 minutes for agents to appear in the console

# Via CLI
lacework agent list

# Or check agent status on a specific node
kubectl -n lacework exec -it daemonset/lacework-agent -- \
  /var/lib/lacework/datacollector status

# Expected: connected, FIM enabled
```

### Step 2.6: Deploy via Terraform (Alternative)

If you prefer Terraform over Helm:

```hcl
module "lacework_k8s_agent" {
  source  = "lacework/agent/kubernetes"
  version = "~> 3.0"

  lacework_access_token = var.lacework_agent_token
  lacework_server_url   = "https://api.lacework.net"

  namespace        = "lacework"
  cluster_name     = "production-eks-01"
  cluster_region   = var.aws_region
  enable_cluster_agent = true

  # FIM configuration via agent config
  lacework_config_data = jsonencode({
    fim = {
      filepath = [
        "/etc/passwd",
        "/etc/shadow",
        "/etc/ssh",
        "/etc/kubernetes",
        "/usr/bin",
        "/usr/sbin"
      ]
      fileignore = [
        "/var/log",
        "/var/cache",
        "/tmp",
        "/run",
        "/proc",
        "/sys"
      ]
      scanfrequencyminutes = 360
    }
    tags = {
      environment = "production"
      compliance  = "pci-dss"
    }
  })

  tolerations = [
    {
      effect   = "NoSchedule"
      operator = "Exists"
    },
    {
      effect   = "NoExecute"
      operator = "Exists"
    }
  ]
}
```

---

## 5. Phase 3: Configure FIM for Container Workloads

### Step 3.1: Understanding What Lacework Monitors on Container Nodes

The Lacework agent monitors files at the **node level**, which includes:

| What's Monitored | How | Container Visibility |
|---|---|---|
| Host filesystem (`/etc`, `/usr`, `/var`) | Direct file access | Full |
| Container overlay FS | Via `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/` | Full (agent sees all layers) |
| Container writable layer | Via overlay mount upperdir | Full (sees runtime modifications) |
| Persistent Volumes (hostPath) | Direct file access | Full |
| Persistent Volumes (EBS/EFS CSI) | Via mount point on host | Full |
| emptyDir volumes | Via `/var/lib/kubelet/pods/<pod-uid>/volumes/` | Excluded by default (high churn) |

**Critical understanding:** FIM sees the **node's view** of the container filesystem, not
the container's view. File paths in FIM alerts will be host paths like:
```
/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/1234/fs/usr/bin/curl
```
Not the container-relative path `/usr/bin/curl`. The Polygraph engine correlates this
back to the container/pod context.

### Step 3.2: Configure FIM Paths for Container-Specific Monitoring

Update the agent config to monitor container-specific paths. This can be done either via
the Helm values (as above) or by updating the ConfigMap directly:

```bash
# Edit the lacework config ConfigMap
kubectl -n lacework edit configmap lacework-config
```

Add container-specific paths:

```json
{
  "tokens": {
    "AccessToken": "your-token"
  },
  "tags": {
    "environment": "production",
    "KubernetesCluster": "production-eks-01"
  },
  "fim": {
    "filepath": [
      "/etc/passwd",
      "/etc/shadow",
      "/etc/group",
      "/etc/sudoers",
      "/etc/sudoers.d",
      "/etc/ssh",
      "/etc/kubernetes",
      "/etc/kubernetes/pki",
      "/etc/kubernetes/manifests",
      "/etc/containerd",
      "/etc/cni",
      "/var/lib/kubelet/config.yaml",
      "/var/lib/kubelet/kubeconfig",
      "/usr/bin",
      "/usr/sbin",
      "/usr/local/bin"
    ],
    "fileignore": [
      "/var/log",
      "/var/cache",
      "/tmp",
      "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs",
      "/var/lib/docker/overlay2",
      "/var/lib/kubelet/pods",
      "/run",
      "/proc",
      "/sys"
    ],
    "scanfrequencyminutes": 360
  }
}
```

**Note:** Changes to config.json are picked up automatically by the agent without restart.

### Step 3.3: Configure FIM via the FortiCNAPP Console

1. Navigate to **Settings > Agents > Agent Configuration**
2. Select the agent configuration group (or create one for your K8s cluster)
3. Under **File Integrity Monitoring**:
   - Toggle FIM to **Enabled**
   - Set **Scan Frequency**: 360 minutes (every 6 hours)
   - Under **File Paths to Monitor**, add the paths from Step 3.2
   - Under **File Paths to Ignore**, add the exclusion paths
4. Click **Save**

The console configuration takes precedence over local config.json if both are set.

### Step 3.4: Validate FIM is Working

Wait for the first scan cycle (up to 6 hours with the 360-minute config, or trigger
manually):

```bash
# Force a FIM scan by restarting the agent on one node (for testing)
kubectl -n lacework delete pod lacework-agent-abc12
# DaemonSet will recreate it, and FIM runs on startup

# After 15-20 minutes, check the console
# Navigate to: Workloads > Hosts > Files
```

Create a test file to verify detection:

```bash
# SSH to a Kubernetes node (or exec into a privileged pod)
# Create a test file in a monitored path
sudo touch /usr/local/bin/fim-test-file
sudo chmod +x /usr/local/bin/fim-test-file

# Wait for next FIM scan cycle
# The file should appear in: Workloads > Hosts > Files > New Files
```

---

## 6. Phase 4: EKS Audit Log Integration

EKS audit logs provide Kubernetes API-level visibility: who created/deleted pods, modified
RBAC, accessed secrets, etc. This complements FIM (filesystem changes) with control plane
activity.

### Step 4.1: Enable EKS Audit Logging

```bash
# Enable audit logging on your EKS cluster
aws eks update-cluster-config \
  --region us-east-1 \
  --name production-eks-01 \
  --logging '{"clusterLogging":[{"types":["audit","authenticator"],"enabled":true}]}'

# Verify
aws eks describe-cluster \
  --region us-east-1 \
  --name production-eks-01 \
  --query 'cluster.logging'
```

### Step 4.2: Deploy EKS Audit Log Integration (Terraform)

```bash
cat > eks-audit.tf << 'EKS_EOF'
module "lacework_eks_audit" {
  source  = "lacework/eks-audit-log/aws"
  version = "~> 1.0"

  # Specify which EKS clusters to monitor
  cluster_names = ["production-eks-01"]

  # The module creates:
  # - CloudWatch Subscription Filter (per cluster)
  # - Kinesis Firehose (delivers logs to S3)
  # - S3 Bucket (stores audit logs)
  # - SNS Topic (notifies Lacework of new logs)
  # - IAM Cross-Account Role (Lacework reads from S3)

  # Optional: use existing S3 bucket
  # use_existing_bucket = true
  # bucket_arn          = "arn:aws:s3:::your-bucket"

  # Tags
  tags = {
    environment = "production"
    managed_by  = "terraform"
    purpose     = "lacework-fim"
  }
}

output "eks_audit_integration_guid" {
  value = module.lacework_eks_audit.lacework_integration_guid
}
EKS_EOF

terraform init -upgrade
terraform plan
terraform apply
```

### Step 4.3: Verify EKS Audit Integration

```bash
lacework integration list --type AwsEksAudit

# Expected:
# INTEGRATION GUID   NAME                  TYPE          STATUS
# DEF456...          production-eks-01     AwsEksAudit   Ok
```

After 15-30 minutes, navigate to **Workloads > Kubernetes** in the console to see:
- Pod creation/deletion events
- RBAC changes
- Secret access events
- Service account usage

### Step 4.4: AKS / GKE Alternatives

**Azure AKS:**
```bash
# Use the Lacework Azure integration module
module "lacework_aks_audit" {
  source  = "lacework/aks-audit-log/azurerm"
  version = "~> 1.0"

  cluster_name    = "production-aks-01"
  resource_group  = "rg-production"
}
```

**Google GKE:**
```bash
# Use the Lacework GCP integration module
module "lacework_gke_audit" {
  source  = "lacework/audit-log/gcp"
  version = "~> 4.0"

  # GKE audit logs flow through Cloud Audit Logs
  # The GCP audit log module captures these automatically
}
```

---

## 7. Phase 5: Kubernetes Admission Controller

The admission controller scans container images for vulnerabilities **before** they're
deployed, preventing vulnerable workloads from running.

### Step 5.1: Deploy the Proxy Scanner

The proxy scanner runs inside your cluster and communicates with Lacework to scan images:

```bash
# Create values file for proxy scanner
cat > proxy-scanner-values.yaml << 'PS_EOF'
config:
  lacework:
    account_name: "your-account"
    integration_access_token: "your-proxy-scanner-token"
  scan:
    # Automatically scan all images seen by the admission controller
    auto_scan: true
    # Cache scan results for 24 hours
    cache_ttl_hours: 24
  registry:
    # Add private registry credentials if needed
    # - domain: "your-ecr-url.dkr.ecr.us-east-1.amazonaws.com"
    #   username: "AWS"
    #   password_env: "ECR_PASSWORD"

resources:
  requests:
    cpu: "200m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
PS_EOF

# Deploy proxy scanner
helm upgrade --install lacework-proxy-scanner lacework/proxy-scanner \
  --namespace lacework \
  --values proxy-scanner-values.yaml \
  --wait
```

### Step 5.2: Deploy the Admission Controller

```bash
cat > admission-controller-values.yaml << 'AC_EOF'
# Lacework Admission Controller Configuration
lacework:
  account_name: "your-account"
  api_key: "your-api-key"
  api_secret: "your-api-secret"

# Admission policy
admission:
  # What to do when a vulnerable image is detected
  # "warn" = allow but log a warning
  # "deny" = block the deployment
  default_action: "warn"

  # Deny deployments with critical CVEs
  deny_on_severity:
    enabled: true
    severity: "critical"

  # Deny deployments with specific CVEs
  deny_on_cve:
    enabled: true
    cves:
      - "CVE-2024-3094"  # xz-utils backdoor
      # Add other CVEs to block

  # Namespaces to exclude from admission checks
  excluded_namespaces:
    - "kube-system"
    - "lacework"
    - "cert-manager"

  # Maximum scan time before defaulting to allow (fail-open)
  timeout_seconds: 30

  # Scanning limit: 1000 image assessments per hour
  rate_limit: 1000

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "200m"
    memory: "256Mi"
AC_EOF

helm upgrade --install lacework-admission-controller lacework/admission-controller \
  --namespace lacework \
  --values admission-controller-values.yaml \
  --wait
```

### Step 5.3: Test the Admission Controller

```bash
# Deploy a known-vulnerable image (for testing)
kubectl run vuln-test \
  --image=nginx:1.14 \
  --namespace=default \
  --dry-run=server

# Expected: Warning or denial depending on policy
# Warning: Image nginx:1.14 has 12 critical vulnerabilities (Lacework)
```

### Step 5.4: Create Admission Policies in the Console

1. Navigate to **Policies > Container Vulnerability Policies**
2. Create a new policy:
   - **Name:** `block-critical-in-production`
   - **Severity:** Critical
   - **Action:** Deny
   - **Namespaces:** `production`, `staging`
   - **Exceptions:** None
3. Save and activate

---

## 8. Phase 6: Polygraph Behavioural Baseline Tuning

The Polygraph is Lacework's ML engine. It automatically builds behavioural baselines for
all monitored workloads within 24-48 hours. After the baseline is established, deviations
generate anomaly alerts.

### Step 6.1: Wait for Baseline Creation

After deploying the agent, the Polygraph needs 24-48 hours to build a complete baseline.
During this period:

- The agent collects process, file, and network data from all containers
- Polygraph builds behavioural models at the **process level** (smallest unit)
- Models understand natural hierarchies: process → container → pod → node

**Do NOT deploy during a maintenance window or unusual activity period.** The baseline
should capture normal operational behaviour.

### Step 6.2: Review the Polygraph

After 48 hours, navigate to:

1. **Workloads > Containers** — View container-level behavioural graph
2. **Workloads > Hosts** — View host-level behavioural graph
3. **Polygraph** — Interactive graph showing:
   - Normal process relationships (which processes spawn which)
   - Normal file access patterns (which processes access which files)
   - Normal network connections (which processes connect where)

### Step 6.3: Validate Baseline Accuracy

Before tuning, validate that the baseline reflects reality:

```bash
# List all processes the Polygraph has baselined for a specific host
# Navigate to: Workloads > Hosts > [select node] > Polygraph

# Check:
# 1. Are all expected container processes present? (nginx, node, java, etc.)
# 2. Are kubelet, containerd, and kube-proxy present?
# 3. Are there any unexpected processes?
```

### Step 6.4: Suppress Known False Positives

During initial deployment, some alerts will be false positives from expected operational
activity. Suppress them:

1. Navigate to **Alerts > Anomalies**
2. For each false positive alert:
   - Click the alert
   - Review the Polygraph context (what deviated from baseline)
   - Click **Suppress** if it's expected behaviour
   - Select suppression scope:
     - **This host only** — suppress on the specific node
     - **This cluster** — suppress across all nodes with this cluster tag
     - **All hosts** — global suppression

Common false positives to suppress in Kubernetes environments:

| Alert Type | Cause | Suppression Scope |
|---|---|---|
| New process: `coredns` | CoreDNS version upgrade | Cluster |
| New file: `/var/lib/kubelet/pods/*/volumes` | Normal pod scheduling | All hosts |
| New network connection: `kube-apiserver:6443` | Normal kubelet communication | Cluster |
| New process: `pause` | Kubernetes pause container | All hosts |
| File changed: `/etc/resolv.conf` | Pod DNS configuration | All hosts |

### Step 6.5: Configure Anomaly Alert Sensitivity

Via the console:

1. Navigate to **Settings > Alert Policies > Behavior Anomaly Policies**
2. Review and adjust:
   - **Kubernetes Behavior Anomalies** — enabled, severity: High
   - **Host Behavior Anomalies** — enabled, severity: High
   - **Container Behavior Anomalies** — enabled, severity: Critical
   - **New Binary Execution** — enabled, severity: Critical
   - **File System Activity Anomaly** — enabled, severity: High

---

## 9. Phase 7: Custom Policies and LQL Queries

Lacework Query Language (LQL) allows you to create custom detection rules specific to
your containerised environment.

### Step 7.1: List Available Data Sources

```bash
lacework query list-sources

# Key sources for container FIM:
# LW_HA_FILES          — Host/container file events
# LW_HA_MACHINE_DETAILS — Machine (node) metadata
# LW_HA_PROCESSES      — Process events
# LW_HA_CONNECTIONS    — Network connections
# LW_K8S_AUDIT         — Kubernetes audit log events
```

### Step 7.2: Create Custom FIM Queries

**Query 1: Detect new executables in container overlay FS**

```bash
cat > query-new-exe-container.yaml << 'QUERY_EOF'
queryId: FIM_NewExeInContainer
queryText: |-
  {
    source {
      LW_HA_FILES f
    }
    filter {
      f.FILE_TYPE = 'File'
      AND f.FILEDATA_HASH != ''
      AND f.PATH LIKE '/var/lib/containerd/%'
      AND f.PATH LIKE '%/usr/bin/%'
      AND f.CREATED_TIME > 0
    }
    return distinct {
      f.MID as machine_id,
      f.PATH as file_path,
      f.FILEDATA_HASH as file_hash,
      f.FILE_OWNER as owner,
      f.FILE_PERMISSIONS as permissions,
      f.CREATED_TIME as created_at
    }
  }
QUERY_EOF

lacework query create -f query-new-exe-container.yaml
```

**Query 2: Detect SUID binaries in containers**

```bash
cat > query-suid-container.yaml << 'QUERY_EOF'
queryId: FIM_SuidInContainer
queryText: |-
  {
    source {
      LW_HA_FILES f
    }
    filter {
      f.FILE_TYPE = 'File'
      AND f.PATH LIKE '/var/lib/containerd/%'
      AND (
        f.FILE_PERMISSIONS LIKE '%s%'
        OR f.FILE_PERMISSIONS LIKE '4%'
      )
    }
    return distinct {
      f.MID as machine_id,
      f.PATH as file_path,
      f.FILE_OWNER as owner,
      f.FILE_PERMISSIONS as permissions,
      f.FILEDATA_HASH as file_hash
    }
  }
QUERY_EOF

lacework query create -f query-suid-container.yaml
```

**Query 3: Detect modifications to Kubernetes PKI**

```bash
cat > query-k8s-pki-change.yaml << 'QUERY_EOF'
queryId: FIM_K8sPkiChange
queryText: |-
  {
    source {
      LW_HA_FILES f
    }
    filter {
      f.FILE_TYPE = 'File'
      AND (
        f.PATH LIKE '/etc/kubernetes/pki/%'
        OR f.PATH LIKE '/etc/kubernetes/manifests/%'
        OR f.PATH LIKE '/var/lib/kubelet/kubeconfig'
        OR f.PATH LIKE '/var/lib/kubelet/config.yaml'
      )
      AND f.CHANGED = 1
    }
    return distinct {
      f.MID as machine_id,
      f.PATH as file_path,
      f.FILEDATA_HASH as file_hash,
      f.FILE_OWNER as owner,
      f.LAST_MODIFIED_TIME as modified_at
    }
  }
QUERY_EOF

lacework query create -f query-k8s-pki-change.yaml
```

**Query 4: Detect execution from /tmp in containers (attacker staging)**

```bash
cat > query-exec-tmp.yaml << 'QUERY_EOF'
queryId: FIM_ExecFromTmpInContainer
queryText: |-
  {
    source {
      LW_HA_PROCESSES p
    }
    filter {
      (
        p.EXE_PATH LIKE '/tmp/%'
        OR p.EXE_PATH LIKE '/dev/shm/%'
        OR p.EXE_PATH LIKE '/var/tmp/%'
      )
      AND p.CONTAINER_TYPE != ''
    }
    return distinct {
      p.MID as machine_id,
      p.EXE_PATH as exe_path,
      p.CMDLINE as command_line,
      p.PID as process_id,
      p.USERNAME as user,
      p.CONTAINER_TYPE as container_runtime,
      p.CONTAINER_NAME as container_name,
      p.START_TIME as start_time
    }
  }
QUERY_EOF

lacework query create -f query-exec-tmp.yaml
```

### Step 7.3: Create Custom Policies from Queries

```bash
# Create a policy that alerts on new executables in containers
cat > policy-new-exe.yaml << 'POLICY_EOF'
policyId: FIM-CONTAINER-001
title: "New executable detected in container filesystem"
description: "A new binary was created in a container's /usr/bin directory. In immutable container environments, this indicates potential compromise."
queryId: FIM_NewExeInContainer
severity: critical
alertEnabled: true
alertProfile: LW_HA_FILES_DEFAULT_PROFILE.Violation
tags:
  - "fim"
  - "container"
  - "pci-dss"
  - "runtime-integrity"
POLICY_EOF

lacework policy create -f policy-new-exe.yaml

# Create policies for other queries
cat > policy-suid.yaml << 'POLICY_EOF'
policyId: FIM-CONTAINER-002
title: "SUID binary detected in container"
description: "A SUID bit was detected on a file in the container overlay filesystem, indicating potential privilege escalation."
queryId: FIM_SuidInContainer
severity: critical
alertEnabled: true
alertProfile: LW_HA_FILES_DEFAULT_PROFILE.Violation
tags:
  - "fim"
  - "container"
  - "privilege-escalation"
POLICY_EOF

lacework policy create -f policy-suid.yaml

cat > policy-k8s-pki.yaml << 'POLICY_EOF'
policyId: FIM-K8S-001
title: "Kubernetes PKI or manifest file modified"
description: "A file in /etc/kubernetes/pki or /etc/kubernetes/manifests was modified, indicating potential control plane tampering."
queryId: FIM_K8sPkiChange
severity: critical
alertEnabled: true
alertProfile: LW_HA_FILES_DEFAULT_PROFILE.Violation
tags:
  - "fim"
  - "kubernetes"
  - "control-plane"
POLICY_EOF

lacework policy create -f policy-k8s-pki.yaml

cat > policy-exec-tmp.yaml << 'POLICY_EOF'
policyId: FIM-CONTAINER-003
title: "Execution from /tmp in container"
description: "A process was executed from /tmp, /dev/shm, or /var/tmp inside a container, commonly seen in attacker staging and exploitation."
queryId: FIM_ExecFromTmpInContainer
severity: high
alertEnabled: true
alertProfile: LW_HA_PROCESSES_DEFAULT_PROFILE.Violation
tags:
  - "fim"
  - "container"
  - "execution-anomaly"
POLICY_EOF

lacework policy create -f policy-exec-tmp.yaml
```

### Step 7.4: Verify Policies

```bash
lacework policy list --tag fim

# Expected output:
# POLICY ID          SEVERITY  ENABLED  TITLE
# FIM-CONTAINER-001  critical  true     New executable detected in container filesystem
# FIM-CONTAINER-002  critical  true     SUID binary detected in container
# FIM-K8S-001        critical  true     Kubernetes PKI or manifest file modified
# FIM-CONTAINER-003  high      true     Execution from /tmp in container
```

---

## 10. Phase 8: Alert Routing and SIEM Integration

### Step 8.1: Configure Alert Channels

Navigate to **Settings > Notifications > Alert Channels** and configure:

**Slack Integration:**

```bash
lacework alert-channel create slack \
  --name "fim-alerts-slack" \
  --slack-url "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

**PagerDuty Integration:**

```bash
lacework alert-channel create pagerduty \
  --name "fim-alerts-pagerduty" \
  --pagerduty-integration-key "YOUR_INTEGRATION_KEY"
```

**Email:**

```bash
lacework alert-channel create email \
  --name "fim-alerts-email" \
  --recipients "security-team@company.com,soc@company.com"
```

### Step 8.2: Configure Alert Rules

Create alert rules that route FIM-specific alerts to the right channels:

1. Navigate to **Settings > Notifications > Alert Rules**
2. Create rule:
   - **Name:** `FIM Critical Alerts`
   - **Severity:** Critical
   - **Event Categories:** Anomaly, Policy Violation
   - **Tags:** `fim`, `container`, `pci-dss`
   - **Channels:** Slack + PagerDuty
3. Create rule:
   - **Name:** `FIM High Alerts`
   - **Severity:** High
   - **Tags:** `fim`
   - **Channels:** Slack + Email

### Step 8.3: SIEM Integration (Splunk / Sentinel / SkieSecure)

**Option A: S3 Data Export (for Splunk, Elastic, etc.)**

```bash
# Configure Lacework to export events to S3
lacework alert-channel create s3 \
  --name "fim-events-s3" \
  --bucket-arn "arn:aws:s3:::your-siem-bucket" \
  --external-id "lacework-export"
```

Then configure your SIEM to ingest from this S3 bucket.

**Option B: Webhook (for SkieSecure or custom SIEM)**

```bash
lacework alert-channel create webhook \
  --name "fim-events-skiesecure" \
  --webhook-url "https://ingest.skiesecure.io/api/ingest/events" \
  --headers "x-tenant-id=YOUR_TENANT_ID,x-agent-token=YOUR_TOKEN"
```

**Option C: Splunk HEC Direct**

```bash
lacework alert-channel create splunk-hec \
  --name "fim-events-splunk" \
  --hec-url "https://splunk.company.com:8088" \
  --hec-token "YOUR_HEC_TOKEN" \
  --index "lacework_fim" \
  --source "lacework"
```

**Option D: Amazon EventBridge**

```bash
lacework alert-channel create aws-eventbridge \
  --name "fim-events-eventbridge" \
  --event-bus-arn "arn:aws:events:us-east-1:123456789:event-bus/security-events"
```

### Step 8.4: API-Based Alert Retrieval

For custom integrations, pull alerts via the API:

```bash
# Get recent FIM-related alerts
curl -s -X POST "https://your-account.lacework.net/api/v2/Alerts/search" \
  -H "Authorization: Bearer $(lacework access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "timeFilter": {
      "startTime": "2026-03-24T00:00:00Z",
      "endTime": "2026-03-25T23:59:59Z"
    },
    "filters": [
      {
        "field": "severity",
        "expression": "in",
        "values": ["Critical", "High"]
      }
    ]
  }' | jq '.data[] | select(.alertType | test("File|FIM|Integrity"))'
```

---

## 11. Phase 9: Compliance Evidence Generation

### Step 9.1: PCI-DSS 11.5.2 Evidence

Lacework provides built-in compliance reporting. To generate FIM evidence:

1. Navigate to **Compliance > Reports**
2. Select **PCI DSS** framework
3. Filter to **Requirement 11.5** — File Integrity Monitoring
4. Export as PDF or CSV

Evidence includes:
- List of monitored file paths per host/node
- FIM scan frequency configuration
- File change events with timestamps
- Alert history for FIM policy violations
- Baseline comparison results

### Step 9.2: CIS Kubernetes Benchmark

With the Cluster Agent enabled:

1. Navigate to **Compliance > Kubernetes**
2. Select your cluster
3. View CIS Kubernetes Benchmark results:
   - 1.1.x — Control Plane Configuration
   - 1.2.x — API Server
   - 2.x — etcd
   - 3.x — Control Plane Configuration
   - 4.x — Worker Node Security
   - 5.x — Policies
4. Export compliance report

### Step 9.3: Automated Compliance Reporting

Schedule automated compliance reports via the API:

```bash
# Create a scheduled report
curl -s -X POST "https://your-account.lacework.net/api/v2/Reports" \
  -H "Authorization: Bearer $(lacework access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "reportName": "Weekly FIM Compliance Report",
    "reportType": "PCI",
    "frequency": "weekly",
    "emailRecipients": ["compliance@company.com", "auditor@company.com"],
    "filters": {
      "resourceTags": {
        "compliance": "pci-dss"
      }
    }
  }'
```

---

## 12. Phase 10: Operationalisation and Runbook

### Daily Operations Checklist

| Task | How | Frequency |
|---|---|---|
| Review FIM alerts | Console: Alerts > filter by `fim` tag | Daily |
| Check agent health | `kubectl -n lacework get pods` + Console: Workloads > Agents | Daily |
| Validate FIM scan completed | Console: Workloads > Hosts > Files > Last Scan Time | Daily |
| Triage anomaly alerts | Console: Alerts > Anomalies > sort by severity | Daily |

### Weekly Operations Checklist

| Task | How | Frequency |
|---|---|---|
| Review Polygraph baselines | Console: Workloads > Containers > Polygraph | Weekly |
| Update FIM suppression rules | Console: Settings > Alert Policies > Suppressions | Weekly |
| Check for new K8s node types | Ensure new node groups have Lacework DaemonSet | Weekly |
| Review custom policy performance | `lacework policy list --tag fim` + alert counts | Weekly |

### Monthly Operations Checklist

| Task | How | Frequency |
|---|---|---|
| Generate compliance report | Console: Compliance > Reports > PCI DSS | Monthly |
| Review and update FIM paths | Update Helm values for new critical paths | Monthly |
| Tune Polygraph false positives | Suppress recurring FPs, document exceptions | Monthly |
| Verify admission controller efficacy | Review block/warn counts | Monthly |

### Incident Response Runbook: FIM Alert

```
1. ALERT RECEIVED: FIM violation detected
   │
2. IDENTIFY SCOPE
   ├─ Which node?    → Console: Alert detail > Machine ID
   ├─ Which container? → Console: Alert detail > Container info (if available)
   ├─ Which file?    → Console: Alert detail > File path
   └─ What changed?  → Console: Alert detail > File hash (before/after)
   │
3. ASSESS SEVERITY
   ├─ Is the file in a container overlay FS?
   │   ├─ YES → Container compromise likely. Move to step 4.
   │   └─ NO  → Host-level change. Check if it's a known deployment.
   │
   ├─ Is the file a binary or config file?
   │   ├─ BINARY → High severity. Possible malware drop.
   │   └─ CONFIG → Medium severity. Possible persistence mechanism.
   │
   └─ Does the Polygraph show related anomalies?
       ├─ YES → Correlate (new process + new file + new connection = kill chain)
       └─ NO  → Isolated change. May be benign.
   │
4. CONTAIN
   ├─ Cordon the node:
   │     kubectl cordon <node-name>
   │
   ├─ If container compromise:
   │     kubectl delete pod <pod-name> -n <namespace>
   │     (ephemeral — killing the pod removes the compromised container)
   │
   └─ If host compromise:
         Isolate the node from the cluster network
         Do NOT terminate — preserve for forensics
   │
5. INVESTIGATE
   ├─ Check Polygraph for full behavioural context
   ├─ Check EKS audit logs for related API activity
   ├─ Check container image for known CVEs
   ├─ Retrieve file hash and check against threat intel
   │     lacework query run --query-id FIM_NewExeInContainer
   │
   └─ Collect evidence:
         - Screenshot of Polygraph anomaly
         - FIM alert detail (export JSON)
         - EKS audit log entries
         - Node system logs (journalctl)
   │
6. REMEDIATE
   ├─ If container compromise:
   │   ├─ Identify the attack vector (CVE in image? Stolen creds? Exposed service?)
   │   ├─ Patch the image and redeploy
   │   ├─ Rotate any secrets the container had access to
   │   └─ Uncordon the node: kubectl uncordon <node-name>
   │
   └─ If host compromise:
       ├─ Drain the node: kubectl drain <node-name>
       ├─ Terminate and replace the node (immutable infra)
       └─ Investigate root cause before restoring
   │
7. DOCUMENT
   ├─ Record incident in alert-case-service / ticketing system
   ├─ Update FIM policies if new detection rules are needed
   └─ Update suppression rules if this was a false positive
```

### Agent Upgrade Procedure

```bash
# Check current agent version
kubectl -n lacework get daemonset lacework-agent -o jsonpath='{.spec.template.spec.containers[0].image}'

# Upgrade via Helm
helm repo update
helm upgrade lacework-agent lacework/lacework-agent \
  --namespace lacework \
  --values lacework-agent-values-rendered.yaml \
  --wait

# Monitor rollout
kubectl -n lacework rollout status daemonset/lacework-agent

# Verify new version
kubectl -n lacework get pods -o jsonpath='{.items[0].spec.containers[0].image}'
```

---

## 13. Limitations and Gaps

### What Lacework FIM Does Well in Containers

| Capability | Rating | Notes |
|---|---|---|
| Node-level file monitoring | Excellent | Sees all container overlay FS from host |
| Behavioural baselining (Polygraph) | Excellent | 24-48h automatic baseline, process-level granularity |
| Anomaly detection | Good | ML-based, low false positive rate after tuning |
| EKS/AKS/GKE audit log integration | Excellent | Control plane visibility |
| Admission controller | Good | Pre-deployment image scanning, CVE blocking |
| Compliance reporting | Good | PCI-DSS, CIS Kubernetes Benchmark |

### What Lacework FIM Lacks in Containers

| Gap | Impact | Mitigation |
|---|---|---|
| **No real-time FIM** — scans are periodic (minimum hourly) | Attackers can modify and revert files between scans | Polygraph process monitoring catches execution anomalies in near-real-time even if FIM scan misses the file |
| **No eBPF-based monitoring** — agent uses traditional syscall interception | Higher overhead than Tetragon/Falco; less granular kernel-level visibility | Accept higher resource cost (~200-500m CPU per node) |
| **No in-kernel enforcement** — detection only, no prevention | Cannot kill a malicious process at syscall boundary | Use Kubernetes Pod Security Standards (`readOnlyRootFilesystem`) for prevention; Lacework for detection |
| **No SHAP explainability on Polygraph alerts** | Auditors get "anomaly detected" without feature-level attribution | Document the Polygraph context manually in incident reports |
| **FIM paths are host-relative, not container-relative** | Analysts see `/var/lib/containerd/.../fs/usr/bin/curl` not `/usr/bin/curl` | Polygraph provides container context; train analysts on path mapping |
| **No image signing verification** | Cannot verify that running image matches a signed digest at runtime | Use external tools (cosign + Kyverno) alongside Lacework |
| **No SBOM integration** | Cannot browse container dependencies from FIM alerts | Use Syft externally; correlate via image digest |
| **Scan frequency minimum is hourly** | Insufficient for high-security environments requiring sub-minute detection | Combine with Falco or Tetragon for real-time detection alongside Lacework's periodic FIM |
| **No cross-replica comparison** (ReplicaWatcher approach) | Cannot detect single compromised pod by comparing to siblings | Polygraph partially addresses this by detecting deviation from container image baseline |

### Complementary Tools to Fill Gaps

| Gap | Tool | How |
|---|---|---|
| Real-time detection | **Falco** | Deploy Falco DaemonSet alongside Lacework. Falco detects in real-time; Lacework provides hash-based verification and compliance. |
| In-kernel enforcement | **Tetragon** | Deploy Tetragon for enforcement policies (kill on unauthorized write). Lacework for audit trail. |
| Image signing | **cosign + Kyverno** | Sign images in CI/CD. Kyverno admission controller verifies signatures. Lacework scans for CVEs. |
| Read-only rootfs | **Pod Security Standards** | Enforce `readOnlyRootFilesystem: true` via Kubernetes. Lacework detects violations to writable emptyDir mounts. |

---

## 14. Reference Architecture Diagrams

### Production Deployment (EKS)

```
┌──────────────────────────────────────────────────────────────┐
│                        AWS Account                            │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  EKS Cluster: production-eks-01                       │    │
│  │                                                        │    │
│  │  ┌─────────────────────────────────────────────────┐  │    │
│  │  │  namespace: lacework                             │  │    │
│  │  │  ┌───────────────┐ ┌──────────────────────────┐ │  │    │
│  │  │  │ DaemonSet:    │ │ Deployment:              │ │  │    │
│  │  │  │ lacework-agent│ │ lacework-cluster-agent   │ │  │    │
│  │  │  │ (per node)    │ │ (1 replica)              │ │  │    │
│  │  │  │               │ │                          │ │  │    │
│  │  │  │ - FIM         │ │ - K8s compliance         │ │  │    │
│  │  │  │ - Process mon │ │ - CIS benchmarks         │ │  │    │
│  │  │  │ - Network mon │ │                          │ │  │    │
│  │  │  │ - Vuln scan   │ │                          │ │  │    │
│  │  │  └───────┬───────┘ └──────────┬───────────────┘ │  │    │
│  │  │          │                     │                  │  │    │
│  │  │  ┌───────┴─────────────────────┴───────────────┐ │  │    │
│  │  │  │ Deployment: admission-controller            │ │  │    │
│  │  │  │ + proxy-scanner                             │ │  │    │
│  │  │  │ (image CVE scanning on admission)           │ │  │    │
│  │  │  └─────────────────────────────────────────────┘ │  │    │
│  │  └─────────────────────────────────────────────────┘  │    │
│  │                                                        │    │
│  │  ┌─────────────────────────────────────────────────┐  │    │
│  │  │  namespace: production (application workloads)   │  │    │
│  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐           │  │    │
│  │  │  │ nginx   │ │ api     │ │ worker  │           │  │    │
│  │  │  └─────────┘ └─────────┘ └─────────┘           │  │    │
│  │  └─────────────────────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  CloudWatch Log Group: /aws/eks/production-eks-01     │    │
│  │  └─ Subscription Filter → Kinesis Firehose → S3       │    │
│  │                                        │               │    │
│  │                                        ▼               │    │
│  │  ┌──────────────────────────────────────────────┐     │    │
│  │  │  S3 Bucket: lacework-eks-audit-logs           │     │    │
│  │  │  └─ SNS → Lacework FortiCNAPP                 │     │    │
│  │  └──────────────────────────────────────────────┘     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  CloudTrail → S3 → SNS → Lacework FortiCNAPP         │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                                │
└────────────────────────────────┬─────────────────────────────┘
                                 │ HTTPS (443)
                                 ▼
                    ┌──────────────────────────┐
                    │  Lacework FortiCNAPP SaaS │
                    │                          │
                    │  - Polygraph (ML)         │
                    │  - FIM Engine             │
                    │  - Alert Engine           │
                    │  - Compliance Reports     │
                    │  - Custom Policies (LQL)  │
                    │                          │
                    │  Outputs:                │
                    │  ├─ Slack alerts          │
                    │  ├─ PagerDuty             │
                    │  ├─ S3 export → SIEM      │
                    │  ├─ Webhook → SkieSecure  │
                    │  └─ Compliance PDF        │
                    └──────────────────────────┘
```

### Terraform Module Dependency Graph

```
                    ┌─────────────────────┐
                    │ providers.tf         │
                    │ (lacework + aws)     │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                 │
              ▼                ▼                 ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
   │ cloudtrail.tf│ │ eks-audit.tf │ │ lacework-agent   │
   │              │ │              │ │ (Helm values)    │
   │ AWS CT → S3  │ │ CW → Firehose│ │                  │
   │ → SNS → LW   │ │ → S3 → LW   │ │ DaemonSet +      │
   │              │ │              │ │ Cluster Agent +   │
   │              │ │              │ │ Admission Ctrl    │
   └──────────────┘ └──────────────┘ └──────────────────┘
```

---

## Appendix A: Complete Terraform for EKS + Lacework FIM

```hcl
# main.tf — Complete Lacework FIM for EKS

terraform {
  required_version = ">= 1.0"
  required_providers {
    lacework = {
      source  = "lacework/lacework"
      version = "~> 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# --- Variables ---

variable "aws_region" {
  default = "us-east-1"
}

variable "eks_cluster_name" {
  default = "production-eks-01"
}

variable "lacework_agent_token" {
  sensitive = true
}

# --- Providers ---

provider "lacework" {}
provider "aws" { region = var.aws_region }

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# --- 1. CloudTrail Integration ---

module "aws_cloudtrail" {
  source  = "lacework/cloudtrail/aws"
  version = "~> 3.0"

  use_existing_cloudtrail = false
  bucket_force_destroy    = false
}

# --- 2. EKS Audit Log Integration ---

module "eks_audit" {
  source  = "lacework/eks-audit-log/aws"
  version = "~> 1.0"

  cluster_names = [var.eks_cluster_name]

  tags = {
    environment = "production"
    purpose     = "lacework-fim"
  }
}

# --- 3. Lacework Agent (DaemonSet + Cluster Agent) ---

module "lacework_agent" {
  source  = "lacework/agent/kubernetes"
  version = "~> 3.0"

  lacework_access_token = var.lacework_agent_token
  lacework_server_url   = "https://api.lacework.net"

  namespace          = "lacework"
  cluster_name       = var.eks_cluster_name
  cluster_region     = var.aws_region
  enable_cluster_agent = true

  lacework_config_data = jsonencode({
    fim = {
      filepath = [
        "/etc/passwd", "/etc/shadow", "/etc/group",
        "/etc/sudoers", "/etc/sudoers.d", "/etc/ssh",
        "/etc/kubernetes", "/etc/kubernetes/pki",
        "/etc/kubernetes/manifests", "/etc/containerd",
        "/etc/cni", "/var/lib/kubelet/config.yaml",
        "/var/lib/kubelet/kubeconfig",
        "/usr/bin", "/usr/sbin", "/usr/local/bin"
      ]
      fileignore = [
        "/var/log", "/var/cache", "/tmp",
        "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs",
        "/var/lib/docker/overlay2", "/var/lib/kubelet/pods",
        "/run", "/proc", "/sys"
      ]
      scanfrequencyminutes = 360
    }
    tags = {
      environment = "production"
      compliance  = "pci-dss"
      fim-profile = "containerised"
    }
  })

  tolerations = [
    { effect = "NoSchedule", operator = "Exists" },
    { effect = "NoExecute", operator = "Exists" }
  ]
}

# --- Outputs ---

output "cloudtrail_integration" {
  value = module.aws_cloudtrail.lacework_integration_guid
}

output "eks_audit_integration" {
  value = module.eks_audit.lacework_integration_guid
}
```

---

## Appendix B: Validation Test Suite

Run these tests to validate the FIM deployment:

```bash
#!/usr/bin/env bash
# validate-lacework-fim.sh — Run after deployment to verify FIM is working

set -euo pipefail

echo "=== Lacework FIM Validation Suite ==="

# Test 1: Agent pods running on all nodes
echo "[1/8] Checking agent pods..."
NODES=$(kubectl get nodes --no-headers | wc -l)
AGENTS=$(kubectl -n lacework get pods -l app=lacework-agent --no-headers | grep Running | wc -l)
if [ "$NODES" -eq "$AGENTS" ]; then
  echo "  PASS: $AGENTS agents running on $NODES nodes"
else
  echo "  FAIL: $AGENTS agents running but $NODES nodes exist"
fi

# Test 2: Cluster agent running
echo "[2/8] Checking cluster agent..."
CLUSTER_AGENT=$(kubectl -n lacework get pods -l app=lacework-cluster-agent --no-headers | grep Running | wc -l)
if [ "$CLUSTER_AGENT" -ge 1 ]; then
  echo "  PASS: Cluster agent running"
else
  echo "  FAIL: Cluster agent not running"
fi

# Test 3: Agent connected to Lacework
echo "[3/8] Checking agent connectivity..."
REGISTERED=$(lacework agent list --json 2>/dev/null | jq '.data | length')
if [ "$REGISTERED" -ge "$NODES" ]; then
  echo "  PASS: $REGISTERED agents registered in Lacework"
else
  echo "  WARN: Only $REGISTERED agents registered (expected $NODES)"
fi

# Test 4: FIM policies active
echo "[4/8] Checking custom FIM policies..."
FIM_POLICIES=$(lacework policy list --tag fim --json 2>/dev/null | jq '.data | length')
echo "  INFO: $FIM_POLICIES FIM policies active"

# Test 5: Cloud integrations healthy
echo "[5/8] Checking cloud integrations..."
lacework integration list --json 2>/dev/null | jq -r '.data[] | "\(.intgGuid[:8])  \(.name)  \(.state)"' | while read line; do
  echo "  $line"
done

# Test 6: Create test file and verify detection
echo "[6/8] Creating test file for FIM detection..."
TEST_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl run fim-test --image=busybox --restart=Never --overrides='{
  "spec": {
    "nodeName": "'$TEST_NODE'",
    "containers": [{
      "name": "fim-test",
      "image": "busybox",
      "command": ["sh", "-c", "echo FIM_TEST > /usr/local/bin/fim-test-marker && sleep 10"],
      "securityContext": {"runAsUser": 0}
    }],
    "hostPID": true
  }
}' 2>/dev/null || true
echo "  INFO: Test file created. Check Lacework console in 6 hours (next FIM scan)."
kubectl delete pod fim-test --ignore-not-found 2>/dev/null

# Test 7: Admission controller responding
echo "[7/8] Checking admission controller..."
AC_PODS=$(kubectl -n lacework get pods -l app=lacework-admission-controller --no-headers 2>/dev/null | grep Running | wc -l)
if [ "$AC_PODS" -ge 1 ]; then
  echo "  PASS: Admission controller running"
else
  echo "  SKIP: Admission controller not deployed"
fi

# Test 8: EKS audit logs flowing
echo "[8/8] Checking EKS audit log integration..."
EKS_INTG=$(lacework integration list --type AwsEksAudit --json 2>/dev/null | jq '.data | length')
if [ "$EKS_INTG" -ge 1 ]; then
  echo "  PASS: $EKS_INTG EKS audit log integration(s) active"
else
  echo "  WARN: No EKS audit log integration found"
fi

echo ""
echo "=== Validation Complete ==="
echo "Note: FIM detection of test file will appear after next scan cycle."
echo "Navigate to: Workloads > Hosts > Files to verify."
```

---

## Sources

- [FortiCNAPP FIM FAQs](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/777250/file-integrity-monitoring-fim-faqs)
- [Configure Linux Agent (Console)](https://docs.fortinet.com/document/forticnapp/latest/administration-guide/748186/configure-linux-agent-using-the-lacework-forticnapp-console)
- [Configure Linux Agent (config.json)](https://docs.fortinet.com/document/forticnapp/25.4.0/administration-guide/628180/configure-linux-agent-using-agent-configuration-file)
- [Installing Agent on Kubernetes](https://docs.fortinet.com/document/forticnapp/26.1.0/administration-guide/663510/installing-linux-agent-on-kubernetes)
- [Kubernetes Compliance via Helm](https://docs.fortinet.com/document/lacework-forticnapp/latest/administration-guide/116902/kubernetes-compliance-integration-using-helm)
- [EKS Audit Log Integration (Terraform)](https://docs.fortinet.com/document/forticnapp/25.2.0/administration-guide/772330/eks-audit-log-integration-using-terraform)
- [Terraform Kubernetes Agent Module](https://registry.terraform.io/modules/lacework/agent/kubernetes/latest)
- [Terraform EKS Audit Log Module](https://github.com/lacework/terraform-aws-eks-audit-log)
- [Kubernetes Admission Controller](https://docs.lacework.net/vulnerabilities/integrate-with-kubernetes-admission-controller)
- [Lacework Polygraph](https://docs.lacework.net/console/view-the-lacework-polygraph)
- [Kubernetes Behavior Anomaly Policies](https://docs.fortinet.com/document/lacework-forticnapp/latest/administration-guide/181947/kubernetes-behavior-anomaly-policies)
- [Custom Policies via CLI](https://docs.lacework.net/cli/custom-policy-walkthrough-cli)
- [LQL Queries](https://docs.lacework.net/cli/commands/lacework_query_list)
- [Container Vulnerability Policies](https://docs.lacework.net/console/container-vulnerability-policies)
