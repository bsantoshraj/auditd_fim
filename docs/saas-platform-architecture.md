# SkieSecure FIM — Unified Integrity Monitoring Module

## Vision

A new **service module within the SkieSecure MSSP platform** that adds file integrity
monitoring and runtime integrity detection across containerised (Kubernetes) and
non-containerised (bare-metal, VM) customer environments, with ML-based behavioural
modelling as the differentiator.

**Brand:** SkieSecure FIM (bundled under the SkieSecure MSSP product line)

**The niche:** No existing MSSP platform unifies auditd-based host FIM, eBPF-based
container runtime monitoring, and image supply chain integrity into a single multi-tenant
offering with **learned behavioural baselines** that eliminate manual rule tuning. This
becomes a new subscription add-on and detection source within SkieSecure's existing
SOC-as-a-Service and XDR offerings.

---

## Integration with SkieSecure MSSP

### Existing Platform Infrastructure (Already Built)

The SkieSecure MSSP (git@github.com:bsantoshraj/skiesecure_mssp.git) provides the complete
SaaS foundation. The FIM module plugs into this — no new infrastructure to build:

| SkieSecure Component | How FIM Module Uses It |
|---|---|
| **Kong** (API Gateway) | New route: `/api/fim/*` → fim-service:3000 |
| **Keycloak** (IAM) | Same JWT with `tenant_id` claim; new role: `fim_admin` |
| **Redpanda** (Kafka-compatible) | New topics: `fim.events.raw`, `fim.events.normalized`, `fim.alerts`, `fim.baselines` |
| **ClickHouse** (SIEM data lake) | New table: `siem.fim_events` partitioned by `(tenant_id, toYYYYMM(timestamp))` |
| **PostgreSQL** | New database: `fim_db` (policies, baselines, ML metadata) |
| **Redis** | Baseline cache, dedup windows, real-time anomaly score cache |
| **MinIO** (S3) | AIDE baseline archives, ML model artifacts, SBOM storage |
| **ingestion-service** | Extended to accept FIM event payloads (auditd, Tetragon, AIDE) |
| **detection-engine** | Extended with FIM-specific Sigma rules for integrity violations |
| **alert-case-service** | FIM alerts flow into same triage queue — SOC analysts see unified view |
| **notification-service** | FIM alerts use same notification channels (email, Slack, PagerDuty) |
| **customer-portal** (Next.js) | New "Integrity" tab showing FIM dashboard |
| **analyst-portal** (Next.js) | New "FIM" section for baseline management, ML tuning |
| **collector** (on-prem Docker) | Extended to collect auditd logs and AIDE reports |
| **Prometheus/Grafana** | FIM agent health metrics, event throughput dashboards |
| **Terraform** (DigitalOcean) | No changes — FIM services deploy into existing `apps` namespace |
| **GitHub Actions CI/CD** | FIM services added to selective build matrix |

### What's New (FIM-Specific Components)

Only **4 new components** are needed:

| New Component | Type | Purpose |
|---|---|---|
| **fim-service** | NestJS microservice | FIM policy management, baseline CRUD, AIDE orchestration |
| **fim-ml-service** | Python (FastAPI) microservice | ML inference (anomaly scoring), model training |
| **fim-agent** | Go binary (customer-side) | auditd rule deployment + AIDE scheduling + Vector config |
| **Tetragon policies** | Kubernetes CRDs (customer-side) | eBPF runtime integrity for containerised workloads |

---

## Architecture (SkieSecure-Native)

```
┌─────────────────────────────────────────────────────────────────────┐
│                   CUSTOMER ENVIRONMENTS                             │
│                                                                     │
│  ┌────────────────────┐       ┌────────────────────────────────┐   │
│  │  Bare Metal / VM    │       │  Kubernetes Cluster             │   │
│  │                     │       │                                 │   │
│  │  ┌───────────────┐ │       │  ┌────────────┐ ┌────────────┐ │   │
│  │  │ fim-agent     │ │       │  │ Tetragon   │ │ cosign     │ │   │
│  │  │  ├ auditd     │ │       │  │ DaemonSet  │ │ admission  │ │   │
│  │  │  ├ AIDE       │ │       │  │ (eBPF)     │ │ (Kyverno)  │ │   │
│  │  │  └ Vector     │ │       │  └─────┬──────┘ └─────┬──────┘ │   │
│  │  └───────┬───────┘ │       │        │              │         │   │
│  └──────────┼─────────┘       └────────┼──────────────┼─────────┘   │
│             │                          │              │             │
│  ┌──────────┼──────────────────────────┼──────────────┼──────────┐ │
│  │  SkieSecure Collector (on-prem Docker, optional)              │ │
│  │  - Aggregates auditd + Tetragon + AIDE events                 │ │
│  │  - Batches & compresses                                       │ │
│  │  - POSTs to SkieSecure ingestion API                          │ │
│  └──────────────────────────────┬───────────────────────────────┘ │
│                                 │                                   │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │  HTTPS (mTLS)
                                  │  Headers: x-tenant-id, x-agent-token
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│              SKIESECURE PLATFORM (Existing Infrastructure)          │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Kong API Gateway                                             │  │
│  │  /api/ingest/events  → ingestion-service (existing)           │  │
│  │  /api/fim/*          → fim-service (NEW)                      │  │
│  │  /api/fim/ml/*       → fim-ml-service (NEW)                   │  │
│  └──────────────────────────────┬───────────────────────────────┘  │
│                                 │                                   │
│  ┌──────────────────────────────┼───────────────────────────────┐  │
│  │  Redpanda (Kafka)            │                                │  │
│  │                              ▼                                │  │
│  │  ingestion-service ──→ fim.events.normalized ──┬──→ ClickHouse│  │
│  │                                                │              │  │
│  │                                                ▼              │  │
│  │                                         fim-ml-service        │  │
│  │                                         (anomaly scoring)     │  │
│  │                                                │              │  │
│  │                                                ▼              │  │
│  │                                         fim.alerts ──→ detection-engine  │
│  │                                                       (existing)        │
│  │                                                              │  │
│  │                                                              ▼  │
│  │                                                  alert-case-service     │
│  │                                                  (existing)             │
│  │                                                              │  │
│  │                                                              ▼  │
│  │                                                  notification-service   │
│  │                                                  (existing)             │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐   │
│  │ ClickHouse    │  │ PostgreSQL   │  │ MinIO (S3)             │   │
│  │ siem.fim_events│ │ fim_db       │  │ {tenant_id}/fim/       │   │
│  │ (365d TTL)    │  │ (policies,   │  │  ├ baselines/          │   │
│  │               │  │  baselines,  │  │  ├ models/             │   │
│  │               │  │  ml_metadata)│  │  └ sboms/              │   │
│  └──────────────┘  └──────────────┘  └────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Frontends (Existing Next.js Apps — Extended)                 │  │
│  │                                                               │  │
│  │  customer-portal:3001                                         │  │
│  │  └─ NEW: /integrity tab                                       │  │
│  │     ├ FIM Dashboard (unified host + container view)           │  │
│  │     ├ Baseline Status (per host/image)                        │  │
│  │     ├ Supply Chain Trust (image signatures)                   │  │
│  │     └ Compliance Evidence (PCI-DSS 11.5.2)                   │  │
│  │                                                               │  │
│  │  analyst-portal:3002                                          │  │
│  │  └─ NEW: /fim section                                         │  │
│  │     ├ Cross-tenant FIM alert queue                            │  │
│  │     ├ Baseline Manager (approve/reject drift)                 │  │
│  │     ├ ML Model Insights (anomaly explanations, SHAP)          │  │
│  │     └ FIM Policy Editor (per-tenant rule management)          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Market Gap Analysis

| Existing Solution | Host FIM | Container Runtime | Supply Chain | ML Baselines | Multi-Tenant SaaS | Open Source |
|---|---|---|---|---|---|---|
| Wazuh | Yes | Partial (agent-based) | No | No | No (self-hosted) | Yes |
| Falco + Tetragon | No | Yes (eBPF) | No | No | No | Yes |
| AIDE + auditd (this project) | Yes | No | No | No | No | Yes |
| Kubescape | No | Yes | Yes (image scan) | No | Freemium | Yes |
| Sysdig Secure | Yes | Yes | Yes | Yes | Yes | No (proprietary) |
| Datadog Security | Yes | Yes | Partial | Yes | Yes | No (proprietary) |
| **SkieSecure FIM** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes (core)** |

**The gap:** No **open-source-core MSSP** offers unified integrity monitoring with ML across
both host and container workloads. The proprietary players (Sysdig, Datadog) charge
$20-50/host/month. SkieSecure FIM is bundled into existing tiers or offered as a $500/month
add-on per 100 endpoints.

---

## New Redpanda Topics

| Topic | Producer | Consumers | Purpose |
|---|---|---|---|
| **fim.events.raw** | ingestion-service | fim-service | Raw auditd/Tetragon/AIDE events before normalisation |
| **fim.events.normalized** | fim-service | fim-ml-service, ClickHouse consumer | OCSF-normalized FIM events |
| **fim.alerts** | fim-ml-service, fim-service | detection-engine | ML anomaly alerts + rule-based alerts |
| **fim.baselines** | fim-service | fim-ml-service | Baseline change events (new/updated/deleted) |

These follow SkieSecure's existing event envelope format:

```typescript
// Uses @skiesecure/event-envelope
{
  event_id: "uuid",
  event_type: "fim.file.modified",
  timestamp: "2026-03-25T10:15:00Z",
  metadata: {
    tenant_id: "11111111-1111-1111-1111-111111111111",
    org_id: "acme-corp",
    source: "fim-service",
    correlation_id: "uuid"
  },
  payload: {
    // OCSF-aligned FIM event (see unified schema below)
  }
}
```

---

## New ClickHouse Table

```sql
CREATE TABLE siem.fim_events (
    event_id        UUID,
    tenant_id       UUID,
    timestamp       DateTime64(3),
    source_type     LowCardinality(String),   -- 'auditd', 'tetragon', 'aide', 'cosign'
    category        LowCardinality(String),   -- 'file_modification', 'binary_tamper', 'suid_change', 'exec_tmp'
    severity        UInt8,                     -- 0-100
    anomaly_score   Float32,                  -- ML anomaly score (0.0-1.0)

    -- Host context
    host_name       String,
    host_role       LowCardinality(String),

    -- Container context (nullable for host events)
    container_id    Nullable(String),
    image_name      Nullable(String),
    image_tag       Nullable(String),
    image_digest    Nullable(String),
    k8s_namespace   Nullable(String),
    k8s_pod_name    Nullable(String),

    -- Process context
    process_name    String,
    process_pid     UInt32,
    process_exe     String,
    parent_process  String,

    -- File context
    file_path       String,
    file_hash       Nullable(String),
    file_prev_hash  Nullable(String),
    file_action     LowCardinality(String),   -- 'create', 'modify', 'delete', 'chmod', 'chown'

    -- User context
    user_name       String,
    user_auid       Nullable(String),

    -- ML context
    anomaly_factors Array(Tuple(String, Float32)),  -- SHAP feature attributions
    baseline_id     Nullable(String),

    -- Raw event
    raw             String CODEC(ZSTD(3)),

    -- Partitioning helpers
    _date           Date DEFAULT toDate(timestamp),
    _hour           UInt8 DEFAULT toHour(timestamp)
)
ENGINE = MergeTree()
PARTITION BY (tenant_id, toYYYYMM(timestamp))
ORDER BY (tenant_id, category, source_type, timestamp)
TTL timestamp + INTERVAL 365 DAY DELETE
SETTINGS index_granularity = 8192;
```

This mirrors the existing `siem.events` table structure but adds FIM-specific columns
(anomaly_score, file_hash, anomaly_factors, baseline_id).

---

## New Services (SkieSecure-Native)

### fim-service (NestJS)

Follows SkieSecure service conventions exactly — uses the `_template/` scaffold.

```
services/fim-service/
├── src/
│   ├── app.module.ts
│   ├── main.ts
│   ├── policy/              # FIM policy CRUD (per-tenant auditd rules, Tetragon policies)
│   │   ├── policy.controller.ts
│   │   ├── policy.service.ts
│   │   └── policy.entity.ts
│   ├── baseline/            # Baseline management (AIDE hashes, image digests)
│   │   ├── baseline.controller.ts
│   │   ├── baseline.service.ts
│   │   └── baseline.entity.ts
│   ├── normalizer/          # auditd → OCSF, Tetragon → OCSF, AIDE → OCSF
│   │   └── normalizer.service.ts
│   ├── consumer/            # Redpanda consumer (fim.events.raw → normalise → produce fim.events.normalized)
│   │   └── fim-events.consumer.ts
│   └── health/
│       └── health.controller.ts
├── test/
├── package.json
└── tsconfig.json
```

**Kong route:** `/api/fim/*` → `fim-service:3000`
**Database:** `fim_db` (PostgreSQL, tenant-scoped via @skiesecure/postgres-common)
**Auth:** JWT via @skiesecure/auth-middleware (roles: fim_admin, soc_analyst, tenant_admin)

### fim-ml-service (Python / FastAPI)

This is the **only Python service** in SkieSecure — justified because the ML stack is
Python-native. Uses the `_template-python/` scaffold.

```
services/fim-ml-service/
├── app/
│   ├── main.py              # FastAPI entrypoint
│   ├── api/
│   │   ├── scoring.py       # POST /score — real-time anomaly scoring
│   │   ├── training.py      # POST /train — trigger baseline learning
│   │   ├── explain.py       # POST /explain — SHAP explanations
│   │   └── health.py        # GET /health
│   ├── models/
│   │   ├── isolation_forest.py   # Real-time anomaly scoring
│   │   ├── autoencoder.py        # VAE baseline learner
│   │   ├── replica_watcher.py    # Cross-replica comparison (training-less)
│   │   └── drift_classifier.py   # XGBoost benign vs malicious
│   ├── kafka/
│   │   ├── consumer.py      # Consumes fim.events.normalized
│   │   └── producer.py      # Produces fim.alerts
│   ├── storage/
│   │   ├── clickhouse.py    # Feature queries from ClickHouse
│   │   └── minio.py         # Model artifact storage
│   └── config.py
├── Dockerfile               # Python 3.12 slim, multi-stage
├── requirements.txt
└── tests/
```

**Kong route:** `/api/fim/ml/*` → `fim-ml-service:8000`
**No database** — stateless inference service. Models stored in MinIO, features queried from ClickHouse.
**Auth:** Service-to-service JWT (internal calls from fim-service)

---

## The ML Differentiator: Learned Behavioural Baselines

This is the **niche**. Every other tool requires manual rule writing. The platform learns
what "normal" looks like and flags deviations automatically.

### Three ML Models Working Together

#### Model 1: Baseline Learner (Per-Image / Per-Host-Role)

**Problem:** Manually defining allowlists for thousands of container images and host roles
is infeasible.

**Approach:**
- During a **learning window** (configurable, default 7 days), observe all syscall events
  from a container image or host role
- Build a behavioural profile: which processes run, which files are accessed, which network
  connections are made, which syscalls are used
- Store as a compact feature vector per (image:tag, host_role) pair

**Implementation:**
```
Input:  Stream of normalised events from Redpanda (fim.events.normalized)
Model:  Variational Autoencoder (VAE) trained per-tenant
Output: Compressed behavioural embedding per (image:tag) or (host_role)
Store:  MinIO ({tenant_id}/fim/models/baselines/)
Track:  MLflow (deployed as internal service or SaaS)
```

**Why this is novel:** IBM's research (Big Data 2020) demonstrated that Kubernetes control
plane metadata can eliminate 99.999% of noise. We extend this by learning the remaining
0.001% that is *expected* behaviour, so only truly anomalous events surface.

#### Model 2: Anomaly Detector (Real-Time Scoring)

**Problem:** Even after filtering, thousands of events per minute need real-time classification.

**Approach — Hybrid of three techniques:**

1. **Isolation Forest** (unsupervised, fast)
   - Scores each event against the learned baseline
   - Low latency (~1ms per event), runs in fim-ml-service
   - Catches statistical outliers

2. **Autoencoder reconstruction error** (semi-supervised)
   - Events that the VAE cannot reconstruct well are anomalous
   - Better at catching subtle, multi-dimensional deviations
   - Runs as batch scoring every 60 seconds

3. **ReplicaWatcher-inspired cross-replica comparison** (training-less)
   - For Kubernetes workloads with replicas, compare behaviour across pods
   - A pod behaving differently from its siblings is suspicious
   - No training needed — works from day one
   - Based on NDSS 2024 research (91% precision, 98% recall)

**Ensemble scoring:**
```
anomaly_score = w1 * isolation_forest_score
              + w2 * autoencoder_reconstruction_error
              + w3 * replica_deviation_score

if anomaly_score > threshold → produce to fim.alerts
if anomaly_score > critical → produce to fim.alerts + detection-engine correlation
```

#### Model 3: Drift Classifier (Benign vs Malicious)

**Problem:** Not all drift is malicious. A developer running `apt-get install vim` on a
staging host is drift but not a threat.

**Approach:**
- Supervised classifier trained on **analyst verdicts** from alert-case-service
- Features: time of day, user identity, process lineage, file path sensitivity score,
  historical frequency, whether the change was preceded by a known deployment event
- Starts with heuristic rules, transitions to ML as labels accumulate
- SHAP values provide per-feature attribution for audit-ready explanations

**Implementation:**
```
Input:  Anomaly events + analyst verdicts (from alert-case-service feedback)
Model:  XGBoost / LightGBM
Output: P(malicious | event_features) + SHAP explanation
```

**Why explainability matters for compliance:** Auditors need to understand *why* an alert
fired. "The ML model said so" is not acceptable. SHAP values provide per-feature attribution:
"This alert fired because: (1) process wrote to /usr/bin, (2) at 03:17 UTC, (3) from a
process spawned by /tmp/x.sh, (4) no deployment event in the preceding 2 hours."

---

## Unified Event Schema (OCSF-Aligned)

SkieSecure already uses OCSF for event normalisation. FIM events extend this:

```json
{
  "class_uid": 3004,
  "class_name": "File System Activity",
  "category_uid": 3,
  "category_name": "System Activity",
  "activity_id": 2,
  "activity_name": "Update",
  "severity_id": 3,
  "time": "2026-03-25T10:15:00.000Z",

  "actor": {
    "user": { "name": "www-data", "uid": "33" },
    "process": {
      "name": "bash",
      "pid": 4521,
      "file": { "path": "/tmp/payload.sh" },
      "parent_process": { "name": "curl", "pid": 4520 }
    },
    "session": { "uid": "1001" }
  },

  "file": {
    "path": "/usr/bin/wget",
    "hashes": [{ "algorithm": "SHA-256", "value": "abc123..." }],
    "type": "Regular File"
  },

  "device": {
    "hostname": "prod-web-03",
    "os": { "name": "Ubuntu", "version": "22.04" },
    "container": {
      "uid": "abc123",
      "image": {
        "name": "nginx",
        "tag": "1.25.3",
        "uid": "sha256:..."
      },
      "orchestrator": "Kubernetes",
      "pod": { "name": "nginx-7d4f8b-x9k2p" },
      "namespace": "production"
    }
  },

  "metadata": {
    "product": { "name": "SkieSecure FIM", "vendor_name": "SkieSecure" },
    "version": "1.0.0",
    "original_time": "2026-03-25T10:15:00.000Z"
  },

  "unmapped": {
    "integrity": {
      "source": "tetragon",
      "anomaly_score": 0.87,
      "baseline_id": "baseline-2026-03-25-001",
      "anomaly_factors": [
        { "feature": "file.path_sensitivity", "contribution": 0.42 },
        { "feature": "process.spawn_location", "contribution": 0.31 },
        { "feature": "event.time_anomaly", "contribution": 0.14 }
      ]
    }
  }
}
```

This means a single ClickHouse query can show:
- "All modifications to `/usr/bin/*` across hosts AND containers, ranked by anomaly score"
- Without the analyst needing to know whether the event came from auditd or Tetragon

---

## Compliance Perspective

### PCI-DSS v4.0

| Requirement | Control | Evidence |
|---|---|---|
| 11.5.2 — Detect unauthorised changes | Image signing (cosign) + auditd + Tetragon + AIDE | SkieSecure FIM alerts + baseline comparison reports |
| 11.5.2 — Alert personnel | fim-ml-service → detection-engine → notification-service | Slack/email/PagerDuty alerts with SHAP explanations |
| 11.5.2 — Weekly comparisons | AIDE scheduled via fim-agent (continuous, not weekly) | Baseline diff reports in customer-portal |
| 10.2 — Audit logging | auditd + Kubernetes audit logs → ClickHouse | Centralised searchable audit trail |
| 10.3.4 — Log integrity | Immutable streaming to ClickHouse (no local storage) | ClickHouse partition immutability |

### ISO 27001:2022

| Control | FIM Coverage |
|---|---|
| A.8.19 — Software installation on operational systems | Admission control (cosign + Kyverno) + auditd binary watches |
| A.12.4.1 — Event logging | eBPF + auditd → ClickHouse with pod/host attribution |

### SOC 2 Type II (CC8.1 — Change Management)

In a GitOps model with SkieSecure FIM:
- All image changes flow through CI/CD (authorised via PR review)
- cosign proves the artifact matches the approved source
- Kyverno enforces that only signed artifacts deploy
- Tetragon catches any out-of-band runtime modifications
- Analyst verdicts in alert-case-service provide audit trail

---

## Engineering Perspective

### How It Fits SkieSecure's Existing Patterns

| Pattern | SkieSecure Convention | FIM Implementation |
|---|---|---|
| Language | NestJS (TypeScript) for services | fim-service: NestJS. fim-ml-service: Python (exception — ML requires it) |
| Shared libs | @skiesecure/auth-middleware, event-envelope, postgres-common | FIM services import same libs |
| Database | Per-service PostgreSQL database | fim_db with same tenant-scoped entity pattern |
| Kafka | Redpanda with tenant_id partition key | Same envelope format, new topics prefixed `fim.` |
| Auth | Keycloak JWT with tenant_id claim + RolesGuard | Same guards, new `fim_admin` role |
| Deployment | Skaffold + Helm + k3d (dev) / DigitalOcean (prod) | FIM services added to services/skaffold.yaml |
| CI/CD | GitHub Actions selective build | FIM services in build matrix |
| Multi-tenancy | 8-layer isolation model | Same 8 layers — no new isolation patterns |

### Performance at Scale

Real numbers from research:
- A single Kubernetes node: **100,000+ syscall events/sec**
- 500-node cluster: **billions of events/minute**
- IBM Research filtering: eliminates **99.999%** of noise via control-plane awareness
- Datadog production eBPF FIM: filters in-kernel, **95%+ reduction** before userspace

**Redpanda capacity:** SkieSecure's existing 3-broker Redpanda cluster can handle ~100K msg/sec.
For FIM at scale, add a dedicated Redpanda topic group with higher partition count (32 vs default 6).

### Ephemeral Forensics

When a compromised pod is killed, filesystem evidence is gone. Mitigations:
- **Tetragon captures events in real-time** → streamed to ClickHouse before pod death
- **cosign image digest** → if running image diverges, evidence is the digest mismatch
- **SkieSecure evidence-service** → FIM events auto-archived as case evidence (chain of custody)

---

## Frontend Extensions (SkieSecure Customer Portal + Analyst Portal)

### customer-portal — New "Integrity" Tab

Uses SkieSecure's existing Next.js 14 + React 18 + TanStack Query 5 stack.

**Views:**

1. **FIM Dashboard** — Unified timeline heatmap (Apache ECharts) showing integrity events
   across hosts and containers, coloured by anomaly score. Same card-based layout as
   existing alert overview.

2. **Baseline Status** — Per-host and per-image baseline cards showing:
   - Current deviation percentage from learned baseline
   - Last AIDE scan timestamp and result
   - Image signature verification status (cosign)

3. **Supply Chain Trust** — Image trust chain visualisation:
   - Image → signed by → verified at admission → running in pods
   - SBOM browser (click image to see dependencies)

4. **Compliance Evidence** — Auto-generated evidence for PCI-DSS 11.5.2, ISO 27001 A.8.19:
   - Exportable PDF/CSV per compliance control
   - Links to specific FIM events in ClickHouse

### analyst-portal — New "FIM" Section

1. **Cross-Tenant FIM Queue** — FIM alerts from all tenants, ranked by anomaly score.
   Same triage workflow as existing alert queue (acknowledge, escalate, close).

2. **Baseline Manager** — Visual diff between current behaviour and learned baseline.
   "Approve deviation" button feeds the drift classifier.

3. **ML Model Insights** — Per-tenant model performance (precision, recall, F1).
   SHAP waterfall charts explaining individual anomaly scores.

4. **FIM Policy Editor** — Per-tenant auditd rule and Tetragon policy management.
   Test rules against historical ClickHouse data ("what-if simulation").

---

## Open Source Components (Aligned with SkieSecure Stack)

### Already in SkieSecure (No New Decisions)

| Component | Purpose | Status |
|---|---|---|
| Redpanda | Event streaming | Deployed |
| ClickHouse | Event analytics | Deployed |
| PostgreSQL | Service databases | Deployed |
| Redis | Cache, dedup | Deployed |
| MinIO | Object storage | Deployed |
| Kong | API gateway | Deployed |
| Keycloak | IAM | Deployed |
| Prometheus/Grafana | Observability | Deployed |
| Next.js + React | Frontends | Deployed |
| NestJS | Services | Deployed |
| Vector (via collector) | Log shipping | Deployed |

### New for FIM Module

| Component | Purpose | Licence | Why This One |
|---|---|---|---|
| **auditd** | Host syscall monitoring | GPL-2.0 | Kernel-native, zero overhead, already proven in this project |
| **AIDE** | Host hash-based FIM | GPL-2.0 | Simplest hash verifier, single binary, no infrastructure |
| **Tetragon** | Container eBPF runtime | Apache-2.0 | In-kernel enforcement, lowest CPU overhead, Cilium/CNCF ecosystem |
| **Falco** (optional) | Container detection breadth | Apache-2.0 | Largest rule library; ingest as secondary source |
| **cosign** (Sigstore) | Image signing | Apache-2.0 | Keyless OIDC signing, widest adoption |
| **Kyverno** | Admission control | Apache-2.0 | YAML-native policies (no Rego), built-in image verification |
| **Syft** | SBOM generation | Apache-2.0 | Best format support (SPDX, CycloneDX) |
| **PyTorch** | VAE/Autoencoder | BSD-3 | Research standard for security ML |
| **scikit-learn** | Isolation Forest | BSD-3 | Production-hardened anomaly detection |
| **XGBoost** | Drift classifier | Apache-2.0 | Best SHAP integration for explainability |
| **SHAP** | ML explainability | MIT | Mathematically grounded explanations for compliance |
| **MLflow** | Model versioning | Apache-2.0 | Fully open-source model registry |

---

## Implementation Roadmap (SkieSecure Phases)

### Phase 1: Host FIM Integration (Weeks 1-4)

- [ ] Create `fim-service` from SkieSecure `_template/` scaffold
- [ ] Extend `ingestion-service` to accept auditd event payloads
- [ ] Create `fim.events.raw` and `fim.events.normalized` Redpanda topics
- [ ] Implement auditd → OCSF normaliser in fim-service
- [ ] Create `siem.fim_events` ClickHouse table
- [ ] Build `fim-agent` (Go binary: deploy auditd rules + Vector config)
- [ ] Extend collector to aggregate auditd events
- [ ] Add FIM Sigma rules to detection-engine
- [ ] Basic "Integrity" tab in customer-portal (event list view)

### Phase 2: Container Runtime + ML (Weeks 5-8)

- [ ] Create `fim-ml-service` from `_template-python/` scaffold
- [ ] Implement Isolation Forest real-time scoring
- [ ] Implement VAE baseline learner (per-image, per-host-role)
- [ ] Implement ReplicaWatcher-inspired cross-replica comparison
- [ ] Tetragon DaemonSet deployment scripts for customer K8s clusters
- [ ] Tetragon → OCSF normalisation in fim-service
- [ ] ML Insights view in analyst-portal (SHAP explanations)
- [ ] Baseline Manager view in analyst-portal

### Phase 3: Supply Chain + Compliance (Weeks 9-12)

- [ ] cosign integration (image signature verification events)
- [ ] Kyverno admission policy templates for customers
- [ ] SBOM ingestion (Syft) and browser in customer-portal
- [ ] AIDE hash baseline scheduling via fim-agent
- [ ] Drift classifier (XGBoost) with analyst feedback loop
- [ ] Compliance Evidence generator (PCI-DSS 11.5.2, ISO 27001)
- [ ] FIM Policy Editor in analyst-portal

### Phase 4: Polish + Launch (Weeks 13-16)

- [ ] FIM Dashboard with heatmap + anomaly timeline (Apache ECharts)
- [ ] Supply Chain Trust visualisation in customer-portal
- [ ] Cross-tenant FIM alert queue in analyst-portal
- [ ] FIM-specific Grafana dashboards (agent health, event throughput)
- [ ] Documentation, onboarding wizard, agent installer scripts
- [ ] Add FIM as subscription add-on in billing-service
- [ ] Production deployment on DigitalOcean

---

## Pricing (SkieSecure Add-On)

| Tier | Included FIM | Additional |
|---|---|---|
| **Starter** ($2K/mo) | 50 host endpoints, basic rules (no ML) | +$500/mo per 100 endpoints |
| **Growth** ($3K/mo) | 200 endpoints (host + container), ML anomaly scoring | +$500/mo per 100 endpoints |
| **Pro** ($4K/mo) | 500 endpoints, full ML + supply chain + compliance reports | +$500/mo per 100 endpoints |
| **FIM-only add-on** | For customers who only want FIM, not full SOC | $8/endpoint/month |

---

## Research Foundations

This platform design draws directly from published research:

1. **IBM Research — Container Integrity Monitoring (2020/2021)**
   - Control-plane-aware filtering eliminates 99.999% noise
   - [IEEE Xplore](https://ieeexplore.ieee.org/document/9377815/)
   - [Full PDF (open access)](https://www.jstage.jst.go.jp/article/ipsjjip/29/0/29_505/_pdf)

2. **ReplicaWatcher — Training-less Anomaly Detection (NDSS 2024)**
   - Cross-replica comparison for zero-day detection without training
   - 91% precision, 98% recall
   - [NDSS Paper](https://www.ndss-symposium.org/ndss-paper/replicawatcher-training-less-anomaly-detection-in-containerized-microservices/)
   - [GitHub](https://github.com/Asbatel/ReplicaWatcher)

3. **eBPF-PATROL (2025)**
   - Adaptive policy enforcement in containerised environments
   - [arXiv](https://arxiv.org/html/2511.18155v1)

4. **Datadog Engineering — eBPF FIM at Scale**
   - Production implementation filtering billions of events/minute
   - [Datadog Blog](https://www.datadoghq.com/blog/engineering/workload-protection-ebpf-fim/)

5. **SSTIC 2021 — Runtime Security Monitoring with eBPF**
   - eBPF superiority over auditd for container monitoring
   - [SSTIC Paper](https://www.sstic.org/media/SSTIC2021/SSTIC-actes/runtime_security_with_ebpf/SSTIC2021-Article-runtime_security_with_ebpf-fournier_afchain_baubeau.pdf)

6. **Comparative Analysis of eBPF-Based Runtime Security Monitoring (SciTePress 2025)**
   - Falco vs Tetragon vs Tracee evaluation
   - [Paper](https://www.scitepress.org/Papers/2025/142727/142727.pdf)
