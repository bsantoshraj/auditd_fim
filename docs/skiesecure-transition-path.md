# SkieSecure MSSP — Transition Path to Standard Open-Source Stack

**Purpose:** This document defines every change needed in the `skiesecure_mssp` repository
to add the FIM module and replace any proprietary/paid dependencies with open-source
alternatives. Pull this into a Claude Code session on the skiesecure_mssp project and
execute the transitions step by step.

**Current state:** SkieSecure v0.3.0, 14 NestJS services, 2 Next.js frontends, platform
running on DigitalOcean staging. Import path fixes in progress.

---

## Part 1: Non-FIM Transitions (Platform-Wide Open-Source Standardisation)

These changes replace paid/proprietary dependencies across the entire SkieSecure platform
with open-source alternatives. None require FIM — do these first.

### Transition 1.1: Stripe → Kill Bill (Open-Source Billing)

**Current state:** billing-service planned with Stripe integration ($0.30 + 2.9% per
transaction, proprietary API lock-in).

**Recommendation:** Replace with [Kill Bill](https://github.com/killbill/killbill)
(Apache-2.0), the most mature open-source billing platform.

| Criterion | Stripe | Kill Bill | LemonSqueezy |
|---|---|---|---|
| Licence | Proprietary | Apache-2.0 | Proprietary |
| Subscription management | Yes | Yes | Yes |
| Usage-based metering | Yes | Yes (with plugin) | Limited |
| Multi-tenant | No (per-account) | Yes (native) | No |
| Self-hosted | No | Yes | No |
| Payment gateway | Built-in | Pluggable (Stripe, Adyen, PayPal as plugins) | Built-in |
| Invoice generation | Yes | Yes | Yes |
| Cost | 2.9% + $0.30/txn | Free (self-hosted) + gateway fees only | 5% + $0.50/txn |

**What changes in skiesecure_mssp:**

```
File: services/billing-service/
Action: Replace Stripe SDK with Kill Bill client

Specific changes:
1. Replace `@stripe/stripe-node` with `killbill` npm package
2. billing-service connects to Kill Bill REST API (internal service)
3. Kill Bill handles subscription lifecycle, invoicing, payment retry
4. Payment gateway: configure Kill Bill's Stripe plugin (uses Stripe
   only for card processing, not billing logic — or switch to Adyen/PayPal)
5. Add Kill Bill to platform/ as a new Helm chart

New files:
- platform/killbill/Chart.yaml
- platform/killbill/values.yaml
- platform/killbill/templates/deployment.yaml
- platform/killbill/templates/service.yaml
- platform/killbill/templates/configmap.yaml
```

**Kill Bill platform deployment:**

```yaml
# platform/killbill/values.yaml
image:
  repository: killbill/killbill
  tag: "0.24.10"
  pullPolicy: IfNotPresent

service:
  port: 8080

database:
  # Kill Bill needs its own database
  host: platform-postgres-postgresql.platform.svc.cluster.local
  port: 5432
  name: killbill_db
  username: platform
  # password from platform-secrets

env:
  KILLBILL_DAO_URL: "jdbc:postgresql://platform-postgres-postgresql.platform.svc.cluster.local:5432/killbill_db"
  KILLBILL_SERVER_MULTITENANT: "true"

resources:
  requests:
    cpu: "200m"
    memory: "512Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"
```

**Alternative (simpler):** If Kill Bill is too heavy for early stage, use
[Lago](https://github.com/getlago/lago) (AGPL-3.0). Lago is more modern, built for
usage-based billing, and has a REST API that maps well to SkieSecure's metering needs.
Trade-off: AGPL requires offering source code if you modify Lago itself (but using its
API from billing-service does not trigger AGPL).

| If you need... | Use |
|---|---|
| Full subscription + usage + multi-tenant billing | Kill Bill (Apache-2.0) |
| Simpler usage-based billing with modern API | Lago (AGPL-3.0) |
| Manual billing for <20 customers (current plan) | Keep the stub, add Lago later |

---

### Transition 1.2: Notification Channels — All Open Source

**Current state:** notification-service planned for email, Slack, webhook, PagerDuty.

**Recommendation:** All channels can be implemented with open-source libraries. No paid
services required for the notification *delivery* (customers bring their own Slack
workspace, PagerDuty account, SMTP server).

| Channel | Open-Source Implementation | npm Package |
|---|---|---|
| Email (SMTP) | Nodemailer | `nodemailer` (MIT) |
| Slack | Slack Web API (webhook) | `@slack/webhook` (MIT) |
| Microsoft Teams | Incoming Webhook (HTTP POST) | Native `fetch` |
| PagerDuty | Events API v2 (HTTP POST) | `@pagerduty/pdjs` (Apache-2.0) |
| Webhook (generic) | HTTP POST with HMAC signing | Native `fetch` + `crypto` |
| SMS (if needed) | [Fonoster](https://github.com/fonoster/fonoster) or customer-provided Twilio | `fonoster` (MIT) |

**No platform changes needed** — these are all npm packages used inside notification-service.
No new infrastructure components.

---

### Transition 1.3: PDF Report Generation — Open Source

**Current state:** reporting-service planned for pen test reports, SOC reports, compliance
reports. PDF generation library not yet chosen.

**Recommendation:** [Typst](https://github.com/typst/typst) (Apache-2.0) or
[Puppeteer](https://github.com/puppeteer/puppeteer) (Apache-2.0).

| Criterion | Typst | Puppeteer (Headless Chrome) | PDFKit |
|---|---|---|---|
| Licence | Apache-2.0 | Apache-2.0 | MIT |
| Template language | Typst markup (like LaTeX, simpler) | HTML/CSS | JavaScript API |
| Branding/styling | Excellent (full typographic control) | Excellent (CSS) | Manual |
| Charts/graphs | Via CeTZ (built-in) | Via ECharts in HTML | Manual |
| Resource usage | Light (native binary, ~10MB) | Heavy (headless Chrome, ~200MB) | Light |
| Multi-page reports | Native | Native | Native |

**Recommendation: Typst** — lightweight, beautiful output, template-based, runs as a CLI
binary (no headless browser). Deploy as a sidecar or init container alongside
reporting-service.

```
File: services/reporting-service/
Action: Add Typst binary to Dockerfile, create report templates

New files:
- services/reporting-service/templates/pentest-report.typ
- services/reporting-service/templates/soc-monthly.typ
- services/reporting-service/templates/compliance-evidence.typ
- services/reporting-service/templates/fim-baseline-report.typ
```

---

### Transition 1.4: Threat Intelligence Enrichment — Open Source

**Current state:** enrichment-service planned with VirusTotal, AbuseIPDB, Shodan (all
paid APIs).

**Recommendation:** Use open-source threat intel feeds and self-hosted tools. Paid APIs
(VT, Shodan) are optional add-ons, not dependencies.

| Source | Type | Licence/Cost | Integration |
|---|---|---|---|
| [MISP](https://github.com/MISP/MISP) feeds (open) | IOC feeds (STIX/TAXII) | AGPL-3.0 | Consume feeds via TAXII client, don't run MISP instance |
| [AbuseIPDB](https://www.abuseipdb.com/api) (free tier) | IP reputation | Free (1000 checks/day) | HTTP API |
| [URLhaus](https://urlhaus.abuse.ch/) | Malicious URL feeds | CC0 (public domain) | CSV/JSON download |
| [MalwareBazaar](https://bazaar.abuse.ch/) | Malware hash feeds | CC0 | CSV/JSON download |
| [Feodo Tracker](https://feodotracker.abuse.ch/) | Botnet C2 feeds | CC0 | CSV download |
| [AlienVault OTX](https://otx.alienvault.com/) | Multi-type IOCs | Free | REST API |
| [OpenCTI](https://github.com/OpenCTI-Platform/opencti) | Threat intel platform | Apache-2.0 | GraphQL API, STIX/TAXII |
| VirusTotal (optional) | File/URL analysis | Freemium ($$$) | HTTP API (optional add-on) |
| Shodan (optional) | Internet scan data | Freemium ($$$) | HTTP API (optional add-on) |

**Architecture:** enrichment-service pulls free feeds on a schedule (cron), caches IOCs in
Redis (1h TTL), and enriches events by lookup. No paid APIs required for baseline
functionality.

```
File: services/enrichment-service/
Action: Implement feed ingestion from abuse.ch feeds + AlienVault OTX

New platform component (optional):
- platform/opencti/ (if you want a full threat intel platform later)
```

---

### Transition 1.5: Search/SIEM — OpenSearch (Already Planned)

**Current state:** siem-service planned with OpenSearch for log analytics (Phase 4).
ClickHouse already deployed for event storage.

**Recommendation:** Keep ClickHouse as the primary analytics engine. Add OpenSearch only
if full-text log search is needed (it may not be — ClickHouse's full-text support has
improved significantly).

| Approach | Pros | Cons |
|---|---|---|
| **ClickHouse only** (recommended) | Single data store, simpler ops, 10x cheaper storage, SQL queries | Weaker full-text search |
| **ClickHouse + OpenSearch** | Best of both (analytics + search) | Double the storage cost, sync complexity |
| **OpenSearch only** | Best full-text search | 10x more storage, slower aggregations |

**Recommendation: ClickHouse only for MVP.** Add OpenSearch later only if customers
specifically need grep-like log search. Most SOC queries are structured (filter by
severity, time, host, namespace) — ClickHouse handles these natively.

If OpenSearch is needed later:

```
New platform component:
- platform/opensearch/Chart.yaml    (use Bitnami or official Helm chart)
- platform/opensearch/values.yaml

Licence: Apache-2.0 (OpenSearch is fully open-source)
```

---

### Transition 1.6: CI/CD — Self-Hosted Runners (Fix GitHub Actions Minutes)

**Current state:** GitHub Actions minutes exhausted. Blocking image builds.

**Recommendation:** Deploy self-hosted GitHub Actions runners on DigitalOcean.

| Option | Cost | Setup |
|---|---|---|
| [actions-runner-controller](https://github.com/actions/actions-runner-controller) (ARC) | $0 (runs on existing K8s) | Helm chart, auto-scales runners as K8s pods |
| DigitalOcean Droplet runner | $12/month (2vCPU/4GB) | `gh` CLI to register, systemd service |
| [Gitea Actions](https://gitea.com/) | $0 (self-hosted) | Would require migrating from GitHub |

**Recommendation: ARC on existing K8s cluster.**

```
New platform component:
- platform/actions-runner/Chart.yaml
- platform/actions-runner/values.yaml

# Quick setup (one-time):
helm install arc \
  --namespace arc-systems \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

helm install arc-runner-set \
  --namespace arc-runners \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --set githubConfigUrl="https://github.com/bsantoshraj/skiesecure_mssp" \
  --set githubConfigSecret.github_token="ghp_YOUR_TOKEN"
```

---

### Transition 1.7: Container Registry — Move to Self-Hosted

**Current state:** GitHub Container Registry (ghcr.io). Works but tied to GitHub Actions
minutes/quotas.

**Recommendation:** Keep ghcr.io as primary (it's free for public repos, included with
GitHub plan for private). Add a self-hosted fallback if needed.

| Option | Cost | Notes |
|---|---|---|
| ghcr.io (keep) | Included | 500MB-50GB depending on plan |
| [Harbor](https://github.com/goharbor/harbor) (CNCF Graduated) | $0 (self-hosted) | Vulnerability scanning, image signing, replication |
| DigitalOcean Container Registry | $5-25/month | Managed, simple |

**Recommendation: Keep ghcr.io for now. Add Harbor when you need image signing (cosign)
and vulnerability scanning as part of the FIM supply chain module.**

---

### Transition 1.8: Secrets Management — External Secrets Operator

**Current state:** Hardcoded passwords in Kubernetes Secrets (`localdev`, `admin`).
Production hardening checklist calls this out.

**Recommendation:** [External Secrets Operator](https://github.com/external-secrets/external-secrets)
(Apache-2.0) syncing from [Infisical](https://github.com/Infisical/infisical) (MIT) or
[Vault](https://github.com/hashicorp/vault) (BSL-1.1).

| Option | Licence | Self-hosted | UX |
|---|---|---|---|
| **Infisical** | MIT | Yes | Best DX (web UI, CLI, K8s operator) |
| HashiCorp Vault | BSL-1.1 | Yes | Most mature, complex |
| AWS Secrets Manager | Proprietary | No | Cloud-only |
| SOPS + age | Apache-2.0 | Yes | Simple, git-based |

**Recommendation: Infisical** — fully open-source (MIT), great web UI for managing
secrets per environment, native Kubernetes operator.

```
New platform components:
- platform/infisical/Chart.yaml
- platform/external-secrets/Chart.yaml

Or simpler alternative:
- Use SOPS + age for encrypted secrets in git (zero infrastructure)
```

---

## Part 2: FIM Module Transitions (New Services + Agent)

These are the SkieSecure-specific changes to add the FIM capability.

### Transition 2.1: Create fim-service (NestJS)

**Action:** Scaffold from `_template/`, implement FIM policy management and event
normalisation.

```bash
# In skiesecure_mssp repo:
make new-service NAME=fim-service
```

**Then modify the scaffolded service:**

```
services/fim-service/
├── src/
│   ├── app.module.ts
│   ├── main.ts
│   ├── policy/
│   │   ├── policy.module.ts
│   │   ├── policy.controller.ts      # CRUD: /api/fim/policies
│   │   ├── policy.service.ts         # Business logic
│   │   ├── policy.entity.ts          # TypeORM entity (fim_db)
│   │   └── dto/
│   │       ├── create-policy.dto.ts
│   │       └── update-policy.dto.ts
│   ├── baseline/
│   │   ├── baseline.module.ts
│   │   ├── baseline.controller.ts    # CRUD: /api/fim/baselines
│   │   ├── baseline.service.ts
│   │   └── baseline.entity.ts
│   ├── normalizer/
│   │   ├── normalizer.module.ts
│   │   ├── normalizer.service.ts     # auditd → OCSF, Tetragon → OCSF, AIDE → OCSF
│   │   ├── auditd.parser.ts
│   │   ├── tetragon.parser.ts
│   │   └── aide.parser.ts
│   ├── consumer/
│   │   ├── consumer.module.ts
│   │   └── fim-events.consumer.ts    # Redpanda: fim.events.raw → normalise → fim.events.normalized
│   └── health/
│       └── health.controller.ts
├── k8s/
│   ├── deployment.yaml
│   └── service.yaml
├── test/
├── Dockerfile
├── package.json
└── tsconfig.json
```

**Wire into platform:**

```yaml
# services/skaffold.yaml — add under build.artifacts:
- image: fim-service
  context: services/fim-service
  docker: { dockerfile: Dockerfile }

# services/skaffold.yaml — add under deploy.kubectl.manifests:
- services/fim-service/k8s/*.yaml

# services/skaffold.yaml — add under portForward:
- resourceType: service
  resourceName: fim-service
  namespace: apps
  port: 3000
  localPort: 3050
```

**Kong route (platform/kong/templates/kong-config.yaml):**

```yaml
# Add under services:
- name: fim-service
  url: http://fim-service.apps.svc.cluster.local:3000
  routes:
    - name: fim-service-route
      paths:
        - /api/fim
      strip_path: false
  plugins:
    - name: jwt
      config:
        claims_to_verify:
          - exp
        key_claim_name: iss
        secret_is_base64: false
```

**Database migration (migrations/):**

```sql
-- migrations/fim_db/001_create_tables.sql
CREATE DATABASE fim_db;

\c fim_db;

CREATE TABLE fim_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  source_type VARCHAR(50) NOT NULL,  -- 'auditd', 'tetragon', 'aide'
  policy_config JSONB NOT NULL,       -- auditd rules, Tetragon TracingPolicy, AIDE paths
  enabled BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_fim_policies_tenant ON fim_policies(tenant_id);

CREATE TABLE fim_baselines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL,
  target_type VARCHAR(50) NOT NULL,   -- 'host_role', 'container_image'
  target_id VARCHAR(255) NOT NULL,    -- 'web-server' or 'nginx:1.25.3'
  baseline_data JSONB NOT NULL,       -- behavioural profile or AIDE hash set
  ml_model_id VARCHAR(255),           -- reference to model in MinIO
  status VARCHAR(50) DEFAULT 'learning',  -- 'learning', 'active', 'stale'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_fim_baselines_tenant ON fim_baselines(tenant_id);
CREATE INDEX idx_fim_baselines_target ON fim_baselines(tenant_id, target_type, target_id);

-- Row-level security
ALTER TABLE fim_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE fim_baselines ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policies ON fim_policies
  USING (tenant_id = current_setting('app.tenant_id')::UUID);
CREATE POLICY tenant_isolation_baselines ON fim_baselines
  USING (tenant_id = current_setting('app.tenant_id')::UUID);
```

**Redpanda topics (add to scripts/seed.sh):**

```bash
# FIM topics
rpk topic create fim.events.raw --partitions 6 --replicas 1
rpk topic create fim.events.normalized --partitions 12 --replicas 1
rpk topic create fim.alerts --partitions 6 --replicas 1
rpk topic create fim.baselines --partitions 3 --replicas 1
```

**ClickHouse table (add to platform/clickhouse/):**

```sql
CREATE TABLE IF NOT EXISTS siem.fim_events (
    event_id        UUID,
    tenant_id       UUID,
    timestamp       DateTime64(3),
    source_type     LowCardinality(String),
    category        LowCardinality(String),
    severity        UInt8,
    anomaly_score   Float32,
    host_name       String,
    host_role       LowCardinality(String),
    container_id    Nullable(String),
    image_name      Nullable(String),
    image_tag       Nullable(String),
    k8s_namespace   Nullable(String),
    k8s_pod_name    Nullable(String),
    process_name    String,
    process_pid     UInt32,
    process_exe     String,
    parent_process  String,
    file_path       String,
    file_hash       Nullable(String),
    file_prev_hash  Nullable(String),
    file_action     LowCardinality(String),
    user_name       String,
    user_auid       Nullable(String),
    anomaly_factors Array(Tuple(String, Float32)),
    baseline_id     Nullable(String),
    raw             String CODEC(ZSTD(3)),
    _date           Date DEFAULT toDate(timestamp),
    _hour           UInt8 DEFAULT toHour(timestamp)
)
ENGINE = MergeTree()
PARTITION BY (tenant_id, toYYYYMM(timestamp))
ORDER BY (tenant_id, category, source_type, timestamp)
TTL timestamp + INTERVAL 365 DAY DELETE
SETTINGS index_granularity = 8192;
```

---

### Transition 2.2: Create fim-ml-service (Python)

**Action:** Scaffold from `_template-python/`, implement ML inference pipeline.

```bash
# In skiesecure_mssp repo:
# Use the Python template
cp -r services/_template-python services/fim-ml-service
```

**Structure:**

```
services/fim-ml-service/
├── app/
│   ├── main.py                     # FastAPI entrypoint
│   ├── api/
│   │   ├── scoring.py              # POST /api/fim/ml/score
│   │   ├── training.py             # POST /api/fim/ml/train
│   │   ├── explain.py              # POST /api/fim/ml/explain
│   │   └── health.py               # GET /health
│   ├── models/
│   │   ├── isolation_forest.py     # Real-time anomaly scoring
│   │   ├── autoencoder.py          # VAE baseline learner
│   │   ├── replica_watcher.py      # Cross-replica comparison
│   │   └── drift_classifier.py     # XGBoost benign vs malicious
│   ├── kafka/
│   │   ├── consumer.py             # Consumes fim.events.normalized
│   │   └── producer.py             # Produces fim.alerts
│   ├── storage/
│   │   ├── clickhouse.py           # Feature queries
│   │   └── minio.py                # Model artifact storage
│   └── config.py
├── k8s/
│   ├── deployment.yaml
│   └── service.yaml
├── Dockerfile                       # Python 3.12 slim, multi-stage
├── requirements.txt
└── tests/
```

**requirements.txt:**

```
fastapi==0.115.*
uvicorn[standard]==0.34.*
confluent-kafka==2.6.*
clickhouse-connect==0.8.*
minio==7.2.*
torch==2.5.*
scikit-learn==1.6.*
xgboost==2.1.*
shap==0.46.*
mlflow==2.19.*
pydantic==2.10.*
```

**Dockerfile:**

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ ./app/
USER 1001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Wire into platform:**

```yaml
# services/skaffold.yaml — add:
- image: fim-ml-service
  context: services/fim-ml-service
  docker: { dockerfile: Dockerfile }

# portForward:
- resourceType: service
  resourceName: fim-ml-service
  namespace: apps
  port: 8000
  localPort: 3051
```

**Kong route:**

```yaml
- name: fim-ml-service
  url: http://fim-ml-service.apps.svc.cluster.local:8000
  routes:
    - name: fim-ml-route
      paths:
        - /api/fim/ml
      strip_path: false
  plugins:
    - name: jwt
      config:
        claims_to_verify:
          - exp
        key_claim_name: iss
        secret_is_base64: false
```

---

### Transition 2.3: Create fim-agent (Go binary, customer-side)

**Action:** New Go binary that deploys to customer hosts (VMs/bare-metal). Not a
Kubernetes service — this is a standalone agent binary.

```
fim-agent/
├── cmd/
│   └── fim-agent/
│       └── main.go                  # Entrypoint
├── internal/
│   ├── auditd/
│   │   ├── rules.go                 # Deploy/manage auditd rules
│   │   └── parser.go                # Parse auditd log events
│   ├── aide/
│   │   ├── config.go                # Generate aide.conf from policy
│   │   ├── scanner.go               # Schedule and run AIDE scans
│   │   └── parser.go                # Parse AIDE report output
│   ├── vector/
│   │   └── config.go                # Generate Vector config for log shipping
│   ├── shipper/
│   │   └── shipper.go               # HTTP client → SkieSecure ingestion API
│   └── config/
│       └── config.go                # Agent configuration (tenant_id, token, server URL)
├── configs/
│   ├── prod.rules                   # Default auditd rules (from this project)
│   └── aide.conf.tmpl               # AIDE config template
├── Dockerfile                        # Multi-stage Go build
├── Makefile
├── go.mod
└── go.sum
```

**This lives in a separate directory** (not under services/) or in its own repo. It's
distributed to customers, not deployed in SkieSecure's cluster.

---

### Transition 2.4: Extend ingestion-service for FIM Events

**Action:** Modify existing ingestion-service to accept FIM event payloads.

```
File: services/ingestion-service/src/
Action: Add FIM event type to OCSF normalisation pipeline

Changes:
1. Add new event type: 'fim' alongside existing 'osquery', 'wazuh', 'syslog'
2. Accept auditd JSON events (from fim-agent via Vector)
3. Accept Tetragon JSON events (from Tetragon export)
4. Accept AIDE report events (from fim-agent)
5. Route to fim.events.raw Redpanda topic (new)
```

---

### Transition 2.5: Extend detection-engine with FIM Sigma Rules

**Action:** Add FIM-specific Sigma detection rules.

```
File: services/detection-engine/rules/fim/
New files:
- binary-tamper.yml        # New/modified binary in /usr/bin, /usr/sbin
- suid-change.yml          # SUID/SGID bit set on file
- exec-from-tmp.yml        # Execution from /tmp, /dev/shm, /var/tmp
- k8s-pki-change.yml       # Changes to /etc/kubernetes/pki
- identity-file-change.yml # Changes to /etc/passwd, /etc/shadow
- persistence.yml          # Changes to cron, systemd units
- container-drift.yml      # Any file write in container overlay FS
- aide-hash-mismatch.yml   # AIDE hash comparison failure
```

Example Sigma rule:

```yaml
# services/detection-engine/rules/fim/binary-tamper.yml
title: Binary Tampering Detected
id: fim-001
status: stable
description: New or modified binary detected in system directories
logsource:
  category: file_change
  product: fim
detection:
  selection:
    file_action:
      - create
      - modify
    file_path|startswith:
      - /usr/bin/
      - /usr/sbin/
      - /usr/local/bin/
  condition: selection
level: critical
tags:
  - attack.persistence
  - attack.t1554
  - pci-dss.11.5.2
```

---

### Transition 2.6: Extend Frontends

**customer-portal changes:**

```
File: frontends/customer-portal/app/
New pages:
- app/integrity/page.tsx              # FIM Dashboard (main tab)
- app/integrity/baselines/page.tsx    # Baseline status per host/image
- app/integrity/supply-chain/page.tsx # Image signature verification status
- app/integrity/compliance/page.tsx   # PCI-DSS 11.5.2 evidence

New components:
- components/fim/timeline-heatmap.tsx  # Apache ECharts heatmap
- components/fim/baseline-card.tsx     # Per-host/image baseline card
- components/fim/anomaly-badge.tsx     # Anomaly score with colour coding

New dependency:
- echarts + echarts-for-react (Apache-2.0)
```

**analyst-portal changes:**

```
File: frontends/analyst-portal/app/
New pages:
- app/fim/page.tsx                    # Cross-tenant FIM alert queue
- app/fim/baselines/page.tsx          # Baseline manager (approve/reject drift)
- app/fim/insights/page.tsx           # ML model performance, SHAP explanations
- app/fim/policies/page.tsx           # Per-tenant FIM policy editor

New components:
- components/fim/shap-waterfall.tsx    # SHAP explanation chart
- components/fim/policy-editor.tsx     # Visual auditd/Tetragon rule editor
- components/fim/drift-diff.tsx        # Baseline vs current diff view
```

---

### Transition 2.7: Keycloak — Add fim_admin Role

**Action:** Add FIM-specific role to Keycloak realm.

```
File: platform/keycloak/templates/realm-config.yaml
Change: Add 'fim_admin' to realm roles

roles:
  realm:
    - name: platform_admin
    - name: soc_analyst
    - name: tenant_admin
    - name: tenant_user
    - name: fim_admin        # NEW — can manage FIM policies and baselines
```

---

## Part 3: Open-Source Component Additions (New Platform Helm Charts)

### Transition 3.1: MLflow (Model Registry)

```
platform/mlflow/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    └── configmap.yaml
```

```yaml
# platform/mlflow/values.yaml
image:
  repository: ghcr.io/mlflow/mlflow
  tag: "2.19.0"

service:
  port: 5000

env:
  MLFLOW_BACKEND_STORE_URI: "postgresql://platform:localdev@platform-postgres-postgresql.platform.svc.cluster.local:5432/mlflow_db"
  MLFLOW_ARTIFACT_ROOT: "s3://mlflow-artifacts"
  AWS_ACCESS_KEY_ID: "minioadmin"
  AWS_SECRET_ACCESS_KEY: "minioadmin"
  MLFLOW_S3_ENDPOINT_URL: "http://platform-minio.platform.svc.cluster.local:9000"

resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
```

**Port forward:**
```yaml
- resourceType: service
  resourceName: platform-mlflow
  namespace: platform
  port: 5000
  localPort: 5000
```

---

### Transition 3.2: Label Studio (Analyst Feedback for ML)

```yaml
# platform/label-studio/values.yaml
image:
  repository: heartexlabs/label-studio
  tag: "1.14.0"

service:
  port: 8080

env:
  DJANGO_DB: "default"
  POSTGRE_HOST: "platform-postgres-postgresql.platform.svc.cluster.local"
  POSTGRE_PORT: "5432"
  POSTGRE_NAME: "label_studio_db"
  POSTGRE_USER: "platform"
  POSTGRE_PASSWORD: "localdev"

resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
```

**Kong route (internal, analyst-portal only):**

```yaml
- name: label-studio
  url: http://platform-label-studio.platform.svc.cluster.local:8080
  routes:
    - name: label-studio-route
      paths:
        - /api/fim/labels
      strip_path: true
  plugins:
    - name: jwt
      config:
        claims_to_verify:
          - exp
        key_claim_name: iss
        secret_is_base64: false
```

---

## Part 4: Skaffold Profile for FIM

Add a `fim` Skaffold profile so FIM services can be deployed selectively:

```yaml
# Add to root skaffold.yaml under profiles:
profiles:
  - name: fim
    patches:
      - op: add
        path: /requires/-
        value:
          configs: [fim-services]
          activeProfiles:
            - name: fim
              activatedBy: [fim]
```

```yaml
# New file: services/fim-skaffold.yaml
apiVersion: skaffold/v4beta11
kind: Config
metadata:
  name: fim-services

build:
  artifacts:
    - image: fim-service
      context: services/fim-service
      docker: { dockerfile: Dockerfile }
    - image: fim-ml-service
      context: services/fim-ml-service
      docker: { dockerfile: Dockerfile }

deploy:
  kubectl:
    manifests:
      - services/fim-service/k8s/*.yaml
      - services/fim-ml-service/k8s/*.yaml

portForward:
  - resourceType: service
    resourceName: fim-service
    namespace: apps
    port: 3000
    localPort: 3050
  - resourceType: service
    resourceName: fim-ml-service
    namespace: apps
    port: 8000
    localPort: 3051
```

Usage:

```bash
# Full platform + FIM
skaffold dev -p fim

# Full platform + FIM + observability
skaffold dev -p fim,observability
```

---

## Part 5: GitHub Actions — Add FIM to CI/CD

```yaml
# .github/workflows/build-images.yml — add to service matrix:
fim-service:
  path: services/fim-service
  dockerfile: docker/service.Dockerfile
  build-arg: SERVICE_NAME=fim-service

fim-ml-service:
  path: services/fim-ml-service
  dockerfile: services/fim-ml-service/Dockerfile
```

---

## Execution Order

Execute these transitions in this order to minimise risk:

| Step | Transition | Dependency | Effort |
|---|---|---|---|
| **1** | 1.6 — Self-hosted CI runners (ARC) | None (unblocks everything) | 2 hours |
| **2** | 1.8 — Secrets management (Infisical or SOPS) | None | 1 day |
| **3** | 2.1 — fim-service (NestJS scaffold) | None | 1 week |
| **4** | 2.4 — Extend ingestion-service for FIM | fim-service topics exist | 3 days |
| **5** | 2.5 — FIM Sigma rules in detection-engine | ingestion-service FIM support | 3 days |
| **6** | 2.7 — Keycloak fim_admin role | None | 1 hour |
| **7** | 3.1 — MLflow deployment | MinIO exists | 1 day |
| **8** | 2.2 — fim-ml-service (Python) | MLflow, ClickHouse FIM table | 2 weeks |
| **9** | 2.3 — fim-agent (Go binary) | fim-service API ready | 2 weeks |
| **10** | 2.6 — Frontend extensions | fim-service + fim-ml-service APIs | 2 weeks |
| **11** | 3.2 — Label Studio | fim-ml-service ready | 1 day |
| **12** | 1.1 — Kill Bill / Lago (billing) | When needed (>20 customers) | 1 week |
| **13** | 1.3 — Typst (PDF reports) | reporting-service scaffold | 3 days |
| **14** | 1.4 — Threat intel feeds | enrichment-service scaffold | 1 week |
| **15** | 1.5 — OpenSearch (if needed) | ClickHouse limits hit | 1 week |

---

## Complete Open-Source Bill of Materials (After All Transitions)

| Component | Purpose | Licence | Status |
|---|---|---|---|
| Kong | API gateway | Apache-2.0 | Existing |
| Keycloak | IAM / SSO | Apache-2.0 | Existing |
| Redpanda | Event streaming | BSL-1.1 | Existing |
| PostgreSQL | Application databases | PostgreSQL | Existing |
| ClickHouse | Event analytics | Apache-2.0 | Existing |
| Redis | Cache | BSD-3 | Existing |
| MinIO | Object storage | AGPL-3.0 | Existing |
| Prometheus | Metrics | Apache-2.0 | Existing |
| Grafana | Dashboards | AGPL-3.0 | Existing |
| Loki | Log aggregation | AGPL-3.0 | Existing |
| NestJS | Service framework | MIT | Existing |
| Next.js | Frontend framework | MIT | Existing |
| **Kill Bill** or **Lago** | Billing | Apache-2.0 / AGPL-3.0 | **NEW (replaces Stripe)** |
| **Typst** | PDF report generation | Apache-2.0 | **NEW** |
| **Infisical** | Secrets management | MIT | **NEW** |
| **ARC** | Self-hosted CI runners | Apache-2.0 | **NEW** |
| **MLflow** | ML model registry | Apache-2.0 | **NEW (FIM)** |
| **Label Studio** | Analyst feedback UI | Apache-2.0 | **NEW (FIM)** |
| **PyTorch** | ML models (VAE) | BSD-3 | **NEW (FIM)** |
| **scikit-learn** | Isolation Forest | BSD-3 | **NEW (FIM)** |
| **XGBoost** | Drift classifier | Apache-2.0 | **NEW (FIM)** |
| **SHAP** | ML explainability | MIT | **NEW (FIM)** |
| **Tetragon** | Container eBPF runtime | Apache-2.0 | **NEW (FIM, customer-side)** |
| **Falco** | Container detection rules | Apache-2.0 | **NEW (FIM, customer-side)** |
| **auditd** | Host syscall monitoring | GPL-2.0 | **NEW (FIM, customer-side)** |
| **AIDE** | Hash-based FIM | GPL-2.0 | **NEW (FIM, customer-side)** |
| **cosign** | Image signing | Apache-2.0 | **NEW (FIM, customer-side)** |
| **Kyverno** | Admission control | Apache-2.0 | **NEW (FIM, customer-side)** |
| **Syft** | SBOM generation | Apache-2.0 | **NEW (FIM, customer-side)** |
| **Vector** | Log shipping agent | MPL-2.0 | Existing (collector) |
| **Nodemailer** | Email delivery | MIT | **NEW (notification-service)** |

**Proprietary/paid dependencies after transition: ZERO.**

The only external cost is the payment gateway (Stripe/Adyen/PayPal) for processing card
payments — which is unavoidable for any billing system. Kill Bill/Lago abstracts the
gateway so you can switch providers.

---

## Licence Risk Summary

| Licence | Components | Risk | Mitigation |
|---|---|---|---|
| Apache-2.0 | Most components | None | Permissive, no restrictions |
| MIT | NestJS, Next.js, SHAP, Infisical, Nodemailer | None | Permissive |
| BSD-3 | PyTorch, scikit-learn, Redis | None | Permissive |
| PostgreSQL | PostgreSQL | None | MIT-like |
| MPL-2.0 | Vector | Low | Must publish modifications to Vector source files |
| BSL-1.1 | Redpanda | Low | Cannot offer Redpanda as a streaming service (not our business) |
| AGPL-3.0 | MinIO, Grafana, Loki, Lago (if chosen) | Medium | Using via API/network does NOT trigger AGPL. Only modifying and distributing their source code triggers copyleft. |
| GPL-2.0 | auditd, AIDE | None | Customer-side tools, not linked into SkieSecure codebase |
