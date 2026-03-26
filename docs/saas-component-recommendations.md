# Open Source Component Recommendations — SkieSecure FIM Module

Detailed evaluation and recommendation for each component of the SkieSecure FIM module.
Every recommendation includes alternatives considered, selection rationale, and risk
assessment. Components already in the SkieSecure MSSP platform (Redpanda, ClickHouse,
PostgreSQL, Kong, Keycloak, Redis, MinIO, NestJS, Next.js) are retained — this document
covers only **new component decisions** specific to the FIM capability.

---

## Current SkieSecure MSSP Stack — Review & Upgrade Recommendations

These components are already deployed in the SkieSecure platform. Most are sound choices.
Where the analysis suggests a better alternative, it's flagged with a recommendation.

| Component | SkieSecure Role | FIM Usage | Recommendation |
|---|---|---|---|
| **Redpanda** | Event streaming | New FIM topics | **Evaluate Kafka 4.0 at scale** — see §5 below |
| **ClickHouse** | SIEM data lake | New `siem.fim_events` table | **Keep** — excellent choice, see §6 |
| **PostgreSQL** | Service databases | New `fim_db` | **Keep** — excellent choice, see §7 |
| **Redis** | Cache, dedup | Baseline cache, anomaly scores | **Keep** — no better alternative |
| **MinIO** (S3) | Object storage | AIDE baselines, ML models, SBOMs | **Keep** — S3-compatible, good for air-gapped |
| **Kong** | API gateway | Route `/api/fim/*` | **Keep** — battle-tested, DB-less mode is clean |
| **Keycloak** | IAM | Same JWT + new `fim_admin` role | **Keep but evaluate Clerk for customer-portal** — see §11 |
| **NestJS** | Service framework | fim-service | **Keep for CRUD services; Python for ML** — see §8 |
| **Next.js + React** | Frontends | New Integrity/FIM tabs | **Keep** — solid choice |
| **Vector** (via collector) | Log shipping | auditd + Tetragon events | **Keep** — best agent for this use case, see §4 |
| **Prometheus/Grafana** | Observability | FIM agent health metrics | **Keep** — industry standard |

---

## New Component Decisions (FIM-Specific)

## 1. Data Plane — Host FIM Agent

### Recommendation: auditd + AIDE (current project stack)

| Criterion | auditd | osquery | Wazuh Agent |
|---|---|---|---|
| Kernel-level syscall capture | Yes (native) | Partial (periodic queries) | Yes (via auditd) |
| Real-time attribution (auid) | Yes | No | Yes (wraps auditd) |
| Hash-based verification | No | Yes (FIM table) | Yes |
| Resource overhead | Minimal (~1% CPU) | Moderate (~3-5% CPU) | Moderate (~3-5% CPU) |
| Maturity | 20+ years in Linux kernel | 10 years (Meta origin) | 10+ years |
| Compliance evidence | Direct (PCI-DSS 10.2) | Indirect | Direct |

**Decision: auditd + AIDE**

**Basis:**
- auditd is the only agent that provides **kernel-native, zero-overhead syscall capture**
  with login UID attribution. Every other tool either wraps auditd or reimplements it with
  higher overhead.
- AIDE provides the hash-based verification that auditd lacks, closing the PCI-DSS 11.5.2 gap.
- The combination is already production-proven in this project with tested rules, sizing data,
  and Tanium deployment scripts.
- osquery was considered but rejected because its polling model (scheduled queries, not
  real-time events) introduces detection latency and misses transient changes.
- Wazuh agent was considered but rejected for host FIM because it adds unnecessary complexity
  (agent → manager → indexer) when we already have a direct pipeline. However, Wazuh is
  reconsidered at the SIEM integration layer.

**Risk:** auditd's event format is non-standard and requires custom normalisation. The
normalisation engine must handle multi-line auditd records reliably.

---

## 2. Data Plane — Container Runtime Monitor

### Recommendation: Tetragon (primary) + Falco (complementary)

| Criterion | Tetragon | Falco | Tracee | KubeArmor |
|---|---|---|---|---|
| Detection speed | 5-26ms | ~10ms | 110-114ms | ~15ms |
| CPU overhead | Lowest | Low | Highest | Low |
| Memory overhead | Moderate | Lowest | Highest | Moderate |
| Enforcement (kill/deny) | Yes (in-kernel) | No (alert only) | No (alert only) | Yes (LSM-based) |
| Kubernetes-aware | Deep (Cilium origin) | Good | Good | Deep |
| CNCF status | Sandbox | Graduated | Sandbox | Sandbox |
| Community size | Growing fast | Largest | Moderate | Growing |
| File integrity events | Yes | Yes | Yes | Yes |
| Network policy | Yes (Cilium integration) | No | Partial | Yes |

**Decision: Tetragon as primary, Falco as complementary**

**Basis:**
- Tetragon provides **in-kernel enforcement** — it can kill a malicious process at the syscall
  boundary before the operation completes. Falco and Tracee can only alert after the fact. For
  a SaaS selling security, prevention > detection.
- Tetragon has the **lowest CPU overhead** per the 2025 comparative analysis paper (SciTePress).
  At SaaS scale (thousands of customer nodes), agent overhead directly impacts customer
  satisfaction and our cost-to-serve.
- Falco is added as complementary because it has the **largest rule ecosystem** (CNCF Graduated
  project, years of community rules). Many customers will have existing Falco rules they want
  to migrate. The platform should ingest Falco alerts as a data source even if Tetragon is
  the primary engine.
- Tracee was rejected due to **highest resource consumption** (110-114ms latency overhead) and
  smaller community.
- KubeArmor was considered for its LSM-based enforcement but rejected because Tetragon's
  eBPF-native enforcement is more portable (works without AppArmor/SELinux kernel support).

**Risk:** Tetragon is younger than Falco (CNCF Sandbox vs Graduated). Mitigated by running
both: Tetragon for enforcement, Falco for detection breadth.

**References:**
- [Comparative Analysis of eBPF-Based Runtime Security Monitoring (SciTePress 2025)](https://www.scitepress.org/Papers/2025/142727/142727.pdf)
- [Container Runtime Security Tooling Comparison (AccuKnox)](https://accuknox.com/wp-content/uploads/Container_Runtime_Security_Tooling.pdf)

---

## 3. Data Plane — Supply Chain Integrity

### Recommendation: cosign (Sigstore) + Syft + Kyverno

| Component | Purpose | Alternative Considered | Why Chosen |
|---|---|---|---|
| cosign | Image signing & verification | Notary v2 | cosign is simpler, keyless signing via OIDC, wider adoption, Sigstore ecosystem |
| Syft | SBOM generation | Trivy (SBOM mode) | Syft is purpose-built for SBOM with richer format support (SPDX, CycloneDX) |
| Kyverno | Admission control (policy enforcement) | OPA Gatekeeper | Kyverno uses Kubernetes-native CRDs (no Rego language), lower learning curve, built-in image verification policies |

**Basis:**
- The Sigstore ecosystem (cosign + Rekor transparency log + Fulcio CA) provides **keyless
  signing** — developers sign with their OIDC identity (GitHub, Google), no GPG key management
  needed. This dramatically lowers adoption friction for SaaS customers.
- Kyverno over OPA Gatekeeper because our target customers (mid-market) will not have Rego
  expertise. Kyverno policies are YAML — the same language they already use for Kubernetes
  manifests.
- Syft over Trivy for SBOM because Syft supports more output formats and is maintained by
  Anchore who are focused exclusively on supply chain security.

**Risk:** Sigstore's public Rekor transparency log means image signatures are publicly visible.
Enterprise customers may need a private Rekor instance. The platform should support both.

---

## 4. Data Plane — Log Shipping Agent

### Recommendation: Vector

| Criterion | Vector | Fluent Bit | Filebeat | OpenTelemetry Collector |
|---|---|---|---|---|
| Language | Rust | C | Go | Go |
| Performance | Highest throughput | High | Moderate | Moderate |
| Memory usage | ~10MB baseline | ~5MB baseline | ~50MB baseline | ~30MB baseline |
| auditd parsing | Native (built-in) | Plugin | Module | Requires config |
| Kubernetes metadata | Native enrichment | Plugin | Module | Native |
| Transform/filter | VRL (Vector Remap Language) | Limited | Limited | OTTL |
| Licence | MPL-2.0 | Apache-2.0 | Elastic Licence | Apache-2.0 |

**Decision: Vector**

**Basis:**
- Vector has **native auditd log parsing** — critical for this project's host FIM pipeline.
  Fluent Bit requires a custom parser. Filebeat requires the Auditbeat module (which is
  a different product).
- Vector's VRL (Vector Remap Language) allows us to implement the **normalisation to unified
  schema** at the agent level, reducing processing load on the SaaS backend.
- Rust implementation provides **highest throughput with lowest memory** — important for
  customers running on resource-constrained nodes.
- OpenTelemetry Collector was considered for its standards-based approach but rejected because
  OTLP is optimised for traces/metrics, not security event logs. Its security log support
  is immature compared to Vector's.

**Risk:** MPL-2.0 licence requires publishing modifications to Vector source files (but not
proprietary code that uses Vector). Acceptable for a SaaS where we configure but don't fork
Vector.

**Reference:**
- [Vector documentation](https://vector.dev/docs/)

---

## 5. Control Plane — Message Queue

> **SkieSecure currently uses Redpanda.** This analysis recommends evaluating a migration
> to Apache Kafka 4.0 as the platform scales. See rationale below.

### Recommendation: Evaluate migration to Apache Kafka 4.0 (via Strimzi)

| Criterion | Apache Kafka | Redpanda | NATS JetStream |
|---|---|---|---|
| Throughput | Millions msg/sec | Millions msg/sec | Millions msg/sec |
| Latency (p99) | ~5ms | ~2ms | ~1ms |
| Operational complexity | High (was ZooKeeper; KRaft since 4.0) | Low (single binary) | Lowest |
| Ecosystem (connectors) | Largest (Kafka Connect, 200+ connectors) | Kafka-compatible | Limited |
| Multi-tenancy | Topic ACLs, quotas | Topic ACLs, quotas | Account-based isolation |
| Kafka protocol compatibility | Native | Full | Partial (via bridge) |
| Licence | Apache-2.0 | BSL-1.1 | Apache-2.0 |
| CNCF/community | Massive (ASF top-level) | Growing | CNCF Incubating |
| Partition scale | 1.9M partitions (KRaft) | ~100K partitions | N/A (streams) |

**Decision: Apache Kafka 4.0+ (KRaft mode, deployed via Strimzi)**

**Basis:**
- Kafka 4.0 (March 2025) removed ZooKeeper entirely — the historical operational complexity
  argument against Kafka is now largely moot. KRaft mode supports 1.9M partitions.
- **Ecosystem is the deciding factor for a SaaS.** Kafka Connect has 200+ connectors (Splunk,
  S3, ClickHouse, etc.) that let us build customer integrations without custom code. Redpanda
  is compatible but the connector ecosystem is Kafka-native.
- Strimzi (CNCF Incubating) provides Kubernetes-native Kafka operations with CRDs for topics,
  users, and quotas — ideal for per-tenant isolation.
- **Licence matters for SaaS.** Kafka is Apache-2.0 (no restrictions). Redpanda is BSL-1.1
  which prohibits offering Redpanda as a managed streaming service — while we're not selling
  streaming, the licence creates ambiguity. Apache-2.0 has zero ambiguity.
- Redpanda's performance claims (10x lower latency) are contested by independent benchmarks.
  At our expected throughput (10K-100K events/sec initially), the latency difference is
  imperceptible.
- NATS JetStream was considered for its simplicity but rejected due to limited ecosystem and
  weaker multi-tenancy primitives.

**Risk:** Kafka still has higher operational complexity than Redpanda. Mitigated by Strimzi +
dedicated Kafka operator expertise. As scale grows, Kafka's ecosystem advantage compounds.

**References:**
- [Kafka 4.0 announcement (KRaft, ZooKeeper removal)](https://kafka.apache.org/)
- [Independent Kafka vs Redpanda benchmark (Jack Vanlightly)](https://jack-vanlightly.com/blog/2023/5/15/kafka-vs-redpanda-performance-do-the-claims-add-up)

---

## 6. Control Plane — Event Storage and Analytics

### Recommendation: ClickHouse

| Criterion | ClickHouse | Elasticsearch/OpenSearch | Apache Druid | DuckDB |
|---|---|---|---|---|
| Query speed (aggregations) | 10-100x faster than ES | Baseline | Fast | Fast (single-node) |
| Storage compression | 10-20:1 | 1.5:1 | 5-10:1 | 5-10:1 |
| Cost per TB stored | Lowest | Highest | Moderate | Lowest (but single-node) |
| Full-text search | Basic (since v22) | Best-in-class | Limited | Basic |
| Real-time ingestion | Excellent | Good | Good | Limited |
| Multi-tenancy | Database-per-tenant, row policies | Index-per-tenant | Datasource-per-tenant | N/A |
| Horizontal scaling | MergeTree sharding | Native sharding | Native | No (single process) |
| SQL support | Native SQL | DSL (painful) | SQL | SQL |
| Licence | Apache-2.0 | Apache-2.0 (OpenSearch) | Apache-2.0 | MIT |

**Decision: ClickHouse**

**Basis:**
- Security event analytics is an **aggregation-heavy workload** (top-N processes, time-series
  anomaly counts, group-by-namespace). ClickHouse outperforms Elasticsearch by 10-100x on
  these queries.
- **Storage cost is critical for SaaS economics.** At 10-20:1 compression vs Elasticsearch's
  1.5:1, ClickHouse stores the same events in 1/10th the disk space. For a multi-tenant SaaS
  retaining 90 days of events, this is the difference between viable and unprofitable unit
  economics.
- ClickHouse uses **native SQL** — our API server can query it directly without learning a
  DSL. Elasticsearch's Query DSL is a significant development tax.
- Database-per-tenant isolation in ClickHouse provides strong multi-tenancy without the
  index-sprawl problems of Elasticsearch.
- Full-text search is ClickHouse's weakness, but for security events we need **structured
  queries** (filter by path, process, namespace, time), not free-text search. The basic
  full-text support in ClickHouse v22+ is sufficient.
- DuckDB was considered for its extreme simplicity but rejected because it's single-process
  (no horizontal scaling for SaaS).

**Risk:** ClickHouse cluster operations require expertise. Mitigated by using ClickHouse
Cloud for initial deployment, migrating to self-managed as scale justifies it.

**References:**
- [ClickHouse vs Elasticsearch: The Billion-Row Matchup](https://clickhouse.com/blog/clickhouse_vs_elasticsearch_the_billion_row_matchup)
- [HyperDX: Why We Chose ClickHouse Over Elasticsearch for Observability](https://www.hyperdx.io/blog/why-clickhouse-over-elasticsearch-observability)

---

## 7. Control Plane — Application Database

### Recommendation: PostgreSQL

| Criterion | PostgreSQL | MySQL | CockroachDB |
|---|---|---|---|
| JSON support | Excellent (JSONB) | Basic | Good |
| Row-level security | Native | No | No |
| Extensions ecosystem | Largest (pgvector, pg_cron, etc.) | Limited | Limited |
| Multi-tenancy | RLS + schemas | Separate databases | Built-in |
| Licence | PostgreSQL Licence (MIT-like) | GPL-2.0 | BSL-1.1 |

**Decision: PostgreSQL 16+**

**Basis:** Industry standard for SaaS application databases. Row-level security provides
tenant isolation at the database layer. JSONB stores flexible policy documents. pgvector
extension could be useful for ML embedding storage if we add semantic search later.
No serious alternative at this tier.

---

## 8. Control Plane — Stream Processing

### Recommendation: Bytewax (initially) → Apache Flink (at scale)

| Criterion | Bytewax | Apache Flink | Kafka Streams | Spark Structured Streaming |
|---|---|---|---|---|
| Language | Python | Java/Scala (PyFlink available) | Java/Scala | Python/Scala |
| ML integration | Native (PyTorch, scikit-learn in-process) | Requires external serving | Poor | Good but batch-oriented |
| Operational complexity | Low (pip install) | High (cluster management) | Low (embedded) | High |
| Stateful processing | Yes | Best-in-class | Yes | Yes |
| Exactly-once semantics | Yes (with Kafka) | Yes | Yes | Yes |
| Throughput ceiling | ~100K events/sec | Millions events/sec | ~500K events/sec | Millions (batch) |
| Licence | Apache-2.0 | Apache-2.0 | Apache-2.0 | Apache-2.0 |

**Decision: Bytewax initially, migrate to Flink at scale**

**Basis:**
- The ML pipeline is Python-native (PyTorch, scikit-learn, XGBoost). Bytewax runs ML
  inference **in the same Python process** as stream processing — no serialisation overhead,
  no external model serving infrastructure.
- At early SaaS stage (<100 tenants), event volumes are manageable (~100K events/sec).
  Bytewax handles this comfortably with a fraction of Flink's operational burden.
- Flink is the long-term choice once event volumes exceed Bytewax's ceiling or when we need
  Flink's superior checkpointing and state management for multi-million-event-per-second
  throughput.
- Kafka Streams was considered but rejected because embedding ML inference in JVM-based
  Kafka Streams requires JNI bridges to Python models — fragile and slow.

**Risk:** Bytewax is a younger project with a smaller community than Flink. Mitigated by
keeping the processing logic in pure Python functions that can be ported to PyFlink with
minimal refactoring.

---

## 9. ML Pipeline

### Recommendation: PyTorch + scikit-learn + XGBoost + SHAP + MLflow

| Component | Purpose | Alternative | Why Chosen |
|---|---|---|---|
| PyTorch | VAE / Autoencoder for baseline learning | TensorFlow | PyTorch is the research standard, better debugging, dominant in security ML literature |
| scikit-learn | Isolation Forest for real-time anomaly scoring | PyOD | scikit-learn is more mature, Isolation Forest implementation is production-hardened |
| XGBoost | Drift classifier (benign vs malicious) | LightGBM | XGBoost has better SHAP integration, marginal performance difference |
| SHAP | Model explainability for compliance | LIME | SHAP provides global + local explanations, mathematically grounded (Shapley values) |
| MLflow | Model versioning, A/B testing, registry | Weights & Biases | MLflow is fully open source (Apache-2.0). W&B is freemium/proprietary |
| Label Studio | Analyst feedback collection | Prodigy | Label Studio is open source (Apache-2.0). Prodigy requires commercial licence |

**Basis:**
- This stack is **100% open source** with no proprietary dependencies.
- PyTorch over TensorFlow because the security ML research papers we're building on
  (ReplicaWatcher, container anomaly detection) use PyTorch.
- SHAP over LIME because SHAP provides **mathematically consistent** feature attributions
  (based on cooperative game theory). For compliance, we need explanations that are
  defensible under audit scrutiny, not approximations.
- MLflow over W&B because MLflow is fully Apache-2.0 with self-hosted model registry.
  For a SaaS handling customer security data, we cannot depend on a third-party SaaS
  (W&B) for model management.

---

## 10. API Server

### Recommendation: Go

| Criterion | Go | Rust | Node.js (TypeScript) | Python (FastAPI) |
|---|---|---|---|---|
| Performance | Excellent | Best | Good | Good (async) |
| Concurrency model | Goroutines (simple) | Async (complex) | Event loop | asyncio |
| WebSocket support | Native (gorilla/websocket) | tokio-tungstenite | Native (ws) | websockets |
| ClickHouse drivers | clickhouse-go (mature) | clickhouse-rs | @clickhouse/client | clickhouse-driver |
| Kafka drivers | confluent-kafka-go | rdkafka | kafkajs | confluent-kafka-python |
| Build/deploy | Single static binary | Single static binary | Node runtime required | Python runtime required |
| Hiring pool | Large (infrastructure/DevOps) | Smaller | Largest | Large |
| Licence ecosystem | Strong OSS culture | Strong OSS culture | Mixed | Mixed |

**Decision: Go**

**Basis:**
- Go's **goroutine-per-connection model** is ideal for WebSocket-heavy workloads (live event
  streaming to frontend). Thousands of concurrent tenant connections without callback hell.
- Single static binary deployment simplifies container image builds and Kubernetes deployment.
- Go is the lingua franca of the cloud-native ecosystem (Kubernetes, Tetragon, Falco,
  ClickHouse, Kafka tooling are all Go). Engineers working on this platform will naturally
  move between the API server and the infrastructure tooling.
- Rust was considered for maximum performance but rejected due to slower development velocity
  and smaller hiring pool. The API server is I/O bound (database queries, Kafka, WebSocket),
  not CPU bound — Go's performance is more than sufficient.
- Python was rejected for the API server (despite being used for ML) because Python's GIL
  limits true parallelism for request handling. The ML pipeline runs as a separate service.

---

## 11. Web Frontend

### Recommendation: React 19 + TypeScript + Shadcn/ui + Apache ECharts

| Component | Purpose | Alternative | Why Chosen |
|---|---|---|---|
| React 19 | UI framework | Vue 3, Svelte 5 | Largest ecosystem, most hiring candidates, best ClickHouse/analytics dashboard libraries |
| TypeScript | Type safety | JavaScript | Non-negotiable for a SaaS codebase. Catches schema mismatches at compile time |
| Shadcn/ui | Component library | Material UI, Ant Design, Chakra UI | Copy-paste components (no npm dependency lock-in), Tailwind-based, highly customisable |
| Tailwind CSS 4 | Styling | CSS Modules, styled-components | Industry standard, utility-first, excellent DX |
| Apache ECharts | Visualisation (charts, heatmaps) | D3.js, Recharts, Nivo | Best performance for large datasets (100K+ points), built-in heatmap/timeline types |
| TanStack Table | Data tables | AG Grid, MUI DataGrid | Open source (MIT), virtual scrolling, headless (full styling control) |
| TanStack Query | Server state | SWR, Redux Toolkit Query | Best cache invalidation, WebSocket integration, optimistic updates |
| Clerk | Auth (multi-tenant SSO) | Auth0, Supabase Auth | Best DX, built-in org/team management, SOC 2 certified |

**Basis:**
- **Shadcn/ui over Material UI:** Shadcn components are copied into the project (not an npm
  dependency). This means zero breaking changes from upstream updates and full styling control.
  For a SaaS frontend that will be heavily customised, this is critical.
- **Apache ECharts over D3.js:** D3 is a low-level graphics library — building a security
  dashboard with D3 requires months of custom work. ECharts provides high-level chart types
  (heatmap, timeline, graph/network, sankey) out of the box with excellent performance on
  large datasets. The event timeline heatmap and process tree graph views are ECharts-native.
- **Clerk over Auth0:** Clerk provides built-in multi-tenant organisation management with
  per-org roles — exactly what a multi-tenant SaaS needs. Auth0 requires custom organisation
  implementation. Clerk is also SOC 2 Type II certified.

---

## 12. Infrastructure and Deployment

### Recommendation: Kubernetes (EKS/GKE) + Terraform + ArgoCD

| Component | Purpose | Why |
|---|---|---|
| Kubernetes (EKS or GKE) | Container orchestration | The platform monitors Kubernetes — dogfooding builds expertise |
| Terraform | Infrastructure provisioning | Industry standard, multi-cloud |
| ArgoCD | GitOps deployment | Kubernetes-native, declarative, audit trail |
| Cert-Manager | TLS certificate management | Automated Let's Encrypt + private CA for mTLS |
| External Secrets Operator | Secret management | Syncs from AWS Secrets Manager / Vault to K8s |

---

## Architecture Decision Records — Summary

| # | Decision | Chosen | Runner-Up | Key Reason |
|---|---|---|---|---|
| 1 | Host FIM agent | auditd + AIDE | Wazuh agent | Kernel-native, already proven in this project |
| 2 | Container runtime | Tetragon + Falco | Tracee | Lowest overhead + in-kernel enforcement |
| 3 | Supply chain | cosign + Syft + Kyverno | Notary v2 + OPA | Keyless signing, YAML-native policies |
| 4 | Log shipping | Vector | Fluent Bit | Native auditd parsing, VRL transforms, Rust performance |
| 5 | Message queue | Apache Kafka 4.0 (Strimzi) | Redpanda | Apache-2.0 licence, largest connector ecosystem |
| 6 | Event storage | ClickHouse | OpenSearch | 10-100x faster aggregations, 10x better compression |
| 7 | App database | PostgreSQL | CockroachDB | Row-level security, mature, no licence risk |
| 8 | Stream processing | Bytewax → Flink | Kafka Streams | Python-native ML integration |
| 9 | ML stack | PyTorch + sklearn + XGBoost | TensorFlow | Research standard, SHAP compatibility |
| 10 | API server | Go | Rust | Cloud-native ecosystem alignment, goroutine concurrency |
| 11 | Frontend | React + Shadcn/ui + ECharts | Vue + Ant Design | Largest ecosystem, no dependency lock-in |
| 12 | Infra | K8s + Terraform + ArgoCD | — | Industry standard, dogfooding |

---

## Cost Estimate (SaaS Infrastructure for 100 Tenants)

| Component | Sizing | Monthly Cost (Cloud) |
|---|---|---|
| Kafka (Strimzi, 3 brokers) | 3x m6i.xlarge | ~$450 |
| ClickHouse (3-node cluster) | 3x m6i.2xlarge + 2TB gp3 | ~$1,200 |
| PostgreSQL (RDS) | db.r6g.large | ~$200 |
| API Server (Go, 3 replicas) | 3x 2vCPU, 4GB | ~$150 |
| ML Pipeline (Bytewax + GPU for training) | 1x g5.xlarge (on-demand for training) | ~$300 |
| Frontend (CDN-served) | CloudFront / Cloudflare | ~$50 |
| S3 (archives, baselines, models) | 5TB | ~$115 |
| Kubernetes control plane (EKS) | 1 cluster | ~$75 |
| **Total** | | **~$2,540/month** |

At $8/host/month (Team tier) with an average of 20 hosts per tenant:
- 100 tenants × 20 hosts × $8 = **$16,000/month revenue**
- Infrastructure cost: ~$2,540/month
- **Gross margin: ~84%** (healthy for SaaS)
