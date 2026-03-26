# SkieSecure FIM — Competitive Landscape Analysis

## Market Context

The SkieSecure FIM module competes at the intersection of three converging markets:

| Market | 2025 Size | 2030 Projection | CAGR |
|---|---|---|---|
| CWPP (Cloud Workload Protection Platform) | $5.1B | $15.4B | ~19% |
| CNAPP (Cloud-Native Application Protection Platform) | $11-15B | $40-51B | ~19-28% |
| FIM (File Integrity Monitoring, standalone) | ~$1.2B | ~$2.5B | ~13% |

**Market dynamic:** Standalone FIM is being absorbed into CWPP/CNAPP platforms. The top 5
(Microsoft, CrowdStrike, Wiz, Palo Alto, Trend Micro) hold **~65% CWPP market share**.
However, all of them are enterprise-priced ($20-100/host/month) and target Fortune 500.

**SkieSecure's position:** MSSP-delivered CWPP+FIM for SMBs at $2-4K/month all-in — a
market segment the enterprise vendors don't serve directly.

---

## Head-to-Head Competitive Comparison

### Tier 1: Enterprise CNAPP/CWPP Platforms

#### Palo Alto Networks — Prisma Cloud

| Criterion | Prisma Cloud | SkieSecure FIM |
|---|---|---|
| **FIM capability** | Built-in file system monitoring for hosts and containers. Detects changes to binaries, SSH configs, certificates. Custom path rules. Automatic behavioural profiling. | auditd (host) + Tetragon (container) + AIDE (hash baselines) + ML anomaly scoring |
| **Container runtime** | Proprietary agent with eBPF + behavioural profiling | Tetragon (eBPF, open source) + Falco rules |
| **Supply chain** | Image scanning (Twistlock heritage), admission control | cosign + Kyverno + Syft SBOM |
| **ML/AI** | Automatic workload profiling, anomaly detection | Isolation Forest + VAE + ReplicaWatcher + XGBoost drift classifier with SHAP explainability |
| **Compliance** | PCI-DSS, HIPAA, SOC 2, CIS benchmarks (built-in) | PCI-DSS 11.5.2, ISO 27001, SOC 2 (auto-generated evidence) |
| **Multi-tenancy** | Single-tenant (per-customer deployment) | Multi-tenant SaaS (8-layer isolation) |
| **Pricing** | ~$30-50/host/month (enterprise contracts) | Bundled in $2-4K/month MSSP tiers |
| **Target** | Enterprise (5000+ employees) | SMB (50-500 employees) |
| **Deployment** | SaaS + agent | SaaS + lightweight agent (fim-agent or collector) |
| **Open source** | No | Core components are open source |

**Prisma Cloud strengths:** Deepest CNAPP integration (CSPM + CWPP + CIEM + CDR in one
platform). Automatic behavioural profiling is mature (Twistlock heritage since 2018).
Largest security research team. CIS benchmark scanning built-in.

**Prisma Cloud weaknesses vs SkieSecure FIM:**
- **No MSSP model** — each customer needs their own Prisma Cloud tenant, managed separately
- **No host-level auditd** — Prisma's host FIM uses its own agent, missing auditd's
  kernel-native attribution (`auid`) and syscall-level detail
- **Black-box ML** — Prisma's anomaly detection doesn't provide SHAP-level explanations;
  auditors get "anomaly detected" without feature attribution
- **Price** — $30-50/host/month is 4-6x SkieSecure's effective per-host cost

---

#### CrowdStrike — Falcon FileVantage + Falcon Cloud Security

| Criterion | CrowdStrike Falcon | SkieSecure FIM |
|---|---|---|
| **FIM product** | Falcon FileVantage — dedicated FIM module. Monitors files, folders, registries. Predefined + custom policies. Threat intel enrichment. | auditd + AIDE + Tetragon + ML scoring |
| **Container runtime** | Falcon sensor for containers (proprietary) | Tetragon (eBPF, open source) |
| **Unique strength** | Threat intelligence integration — FileVantage correlates file changes with known adversary TTPs from CrowdStrike's intel database | ML-based anomaly detection — learns what "normal" looks like per workload, flags deviations without predefined rules |
| **ML/AI** | AI-powered via Charlotte AI. Primarily signature + behavioural. | Unsupervised + supervised ensemble with explainability |
| **Compliance** | PCI-DSS, HIPAA, NIST, CIS (FileVantage specifically designed for compliance FIM) | PCI-DSS 11.5.2, ISO 27001, SOC 2 |
| **Pricing** | FileVantage is an add-on module (~$8-15/endpoint/month on top of Falcon base ~$15-25/endpoint/month) | Bundled in MSSP tiers |
| **Target** | Mid-market to Enterprise | SMB to mid-market |

**CrowdStrike strengths:** Best-in-class threat intelligence enrichment (when a file
changes, CrowdStrike can immediately tell you if the change matches a known APT technique).
Single lightweight agent across all workloads. FileVantage is purpose-built for compliance
FIM with dashboards designed for auditors.

**CrowdStrike weaknesses vs SkieSecure FIM:**
- **Expensive stack-up** — Falcon base ($15-25) + FileVantage ($8-15) + Cloud Security
  ($10-20) = $33-60/endpoint/month. For an SMB with 200 endpoints, that's $6,600-12,000/month
  vs SkieSecure's $3,000/month (Growth tier)
- **Proprietary lock-in** — No open-source components. Leaving CrowdStrike means losing all
  detection rules, baselines, and historical data
- **No cross-environment unification** — FileVantage (host FIM) and Falcon Cloud Security
  (container) are separate modules with separate dashboards. SkieSecure provides a unified view
- **No ML explainability** — Charlotte AI provides verdicts but not SHAP-level feature
  attribution for auditors

---

#### Lacework / FortiCNAPP (Fortinet)

| Criterion | FortiCNAPP (ex-Lacework) | SkieSecure FIM |
|---|---|---|
| **FIM capability** | Behavioural anomaly detection, file integrity monitoring, host intrusion detection | auditd + AIDE + Tetragon + ML |
| **ML approach** | "Polygraph" — unsupervised behavioural analytics. Learns baseline, detects anomalies. No manual rules. | Similar approach (VAE + Isolation Forest) but with SHAP explainability and analyst feedback loop |
| **Container runtime** | Agent-based monitoring | Tetragon eBPF (agent-less on K8s nodes) |
| **Pricing** | Starting ~$5,000/month. Add-ons (IaC, K8s Insights, extended retention) can increase by 40-60% | Starting $2,000/month (all-in MSSP) |
| **Status** | Acquired by Fortinet (Aug 2024). Rebranded FortiCNAPP. Integration in progress. | Independent, focused |

**FortiCNAPP strengths:** Lacework's Polygraph was the industry pioneer in unsupervised
ML-based workload profiling (before anyone else). Now backed by Fortinet's massive sales
channel and firewall customer base.

**FortiCNAPP weaknesses vs SkieSecure FIM:**
- **Acquisition integration risk** — Lacework → Fortinet transition is ongoing. Product
  direction uncertain. Fortinet historically favours appliance-based security.
- **No MSSP multi-tenancy** — FortiCNAPP is single-tenant SaaS per customer
- **Expensive** — $5K+ base, $7-8K with add-ons. 2-3x SkieSecure's comparable tier
- **No host-level auditd integration** — Lacework's agent replaces auditd rather than
  complementing it. Customers lose kernel-native audit trail

---

### Tier 2: Cloud-Native Security Specialists

#### Sysdig Secure

| Criterion | Sysdig Secure | SkieSecure FIM |
|---|---|---|
| **FIM** | Runtime FIM via Falco (Sysdig created Falco). Deep syscall-level monitoring. | auditd (host) + Tetragon (container) — uses Falco rules as secondary source |
| **ML** | Runtime profiling with ML-based anomaly detection (since 2019). Auto-generates container profiles within 24 hours. | Similar capability but with SHAP explainability |
| **Open source** | Created Falco (CNCF Graduated). Commercial platform is proprietary. | Core components fully open source |
| **Pricing** | ~$20-40/host/month | Bundled in $2-4K MSSP tiers |
| **Target** | DevSecOps teams at cloud-native companies | SMBs via MSSP model |

**Sysdig strengths:** Created Falco — deepest expertise in syscall-based container
security. 24-hour auto-profiling is production-proven at scale.

**Sysdig weaknesses vs SkieSecure FIM:**
- **Container-first bias** — Host FIM is secondary. No auditd integration.
- **No MSSP model** — Single-tenant per customer
- **Commercial Falco** — The best Sysdig features (ML profiling, compliance dashboards)
  are proprietary. Open-source Falco is detection-only.

---

#### Aqua Security

| Criterion | Aqua Security | SkieSecure FIM |
|---|---|---|
| **FIM** | Runtime protection via Tracee (eBPF). Drift prevention (blocks runtime changes to container filesystem). | Tetragon enforcement + auditd host FIM |
| **Unique feature** | Drift prevention: automatically blocks any runtime file modification that deviates from the original image. Zero configuration. | ML-based anomaly scoring with explainability |
| **Open source** | Created Tracee (CNCF Sandbox) | Uses Tetragon (CNCF Sandbox) + Falco (CNCF Graduated) |
| **Pricing** | ~$15-30/host/month | Bundled in MSSP tiers |

**Aqua strengths:** Drift prevention is a powerful concept — block all runtime filesystem
changes by default. Zero false positives for immutable containers.

**Aqua weaknesses vs SkieSecure FIM:**
- **Container-only** — Minimal host FIM capability
- **Tracee overhead** — 110-114ms latency overhead vs Tetragon's 5-26ms (SciTePress 2025)
- **Binary enforcement** — Drift prevention is all-or-nothing (block/allow), no ML-based
  risk scoring

---

#### Wiz

| Criterion | Wiz | SkieSecure FIM |
|---|---|---|
| **FIM** | Agentless scanning via cloud API snapshots. No real-time runtime FIM. | Real-time kernel-level FIM (auditd + Tetragon) |
| **Approach** | Scans disk snapshots for vulnerabilities, misconfigurations, secrets. No runtime behavioural monitoring. | Runtime behavioural monitoring + hash baselines + ML |
| **Pricing** | ~$30-50/workload/month | Bundled in MSSP tiers |

**Wiz strengths:** Agentless — zero deployment friction. Graph-based attack path
analysis is best-in-class for posture management.

**Wiz weaknesses vs SkieSecure FIM:**
- **No real-time FIM** — Wiz scans snapshots periodically, not continuously. Cannot
  detect a file change as it happens.
- **No runtime protection** — Wiz is posture management (what *could* happen), not
  runtime security (what *is* happening). Fundamentally different from FIM.
- **Agentless limitation** — Cannot see inside running containers or monitor syscalls

---

### Tier 3: Open-Source Alternatives (Self-Hosted)

#### Wazuh

| Criterion | Wazuh | SkieSecure FIM |
|---|---|---|
| **FIM** | Built-in FIM (hash-based, real-time inotify, scheduled scans). Mature, comprehensive. | auditd + AIDE + Tetragon + ML |
| **Container support** | Agent-based (runs inside container or on host). No eBPF. | Tetragon eBPF (no agent inside containers) |
| **ML** | Basic anomaly detection rules. No ML-based profiling or explainability. | Full ML pipeline (VAE + IF + ReplicaWatcher + XGBoost + SHAP) |
| **Multi-tenancy** | Multi-tenancy via agent groups + Wazuh indexer. Not true SaaS multi-tenant. | Native 8-layer multi-tenancy (SkieSecure) |
| **Pricing** | Free (self-hosted). Wazuh Cloud: ~$5-15/agent/month | Bundled in MSSP tiers |
| **Operations** | Requires dedicated Wazuh Manager, Indexer (Elasticsearch-fork), Dashboard per deployment | Managed SaaS — no customer-side infrastructure |

**Wazuh strengths:** Most complete open-source FIM. Free. Active community. PCI-DSS
compliance module built-in. 15+ years of maturity.

**Wazuh weaknesses vs SkieSecure FIM:**
- **No eBPF** — Agent-based container monitoring misses kernel-level events
- **No ML** — Rule-based only. No learned baselines, no anomaly scoring
- **Operational burden** — Self-hosted Wazuh requires significant infrastructure (Manager +
  Indexer + Dashboard). Many SMBs don't have the team to run it.
- **No supply chain** — No image signing, admission control, or SBOM integration
- **Elasticsearch dependency** — Wazuh Indexer (OpenDistro fork) requires significant
  resources and expertise

---

## Competitive Positioning Matrix

```
                    Enterprise ◄────────────────────► SMB
                         │                              │
         High            │  Prisma Cloud  CrowdStrike  │
         Price           │  FortiCNAPP                  │
         ($30-50/host)   │                              │
                         │  Sysdig    Aqua   Wiz       │
                         │                              │
         Mid Price       │                              │
         ($15-30/host)   │                              │
                         │                              │
                         │                    ┌─────────┤
         Low Price       │                    │SKIESECURE│
         ($8-15/host)    │                    │   FIM    │
                         │                    └─────────┤
                         │                              │
         Free/           │  Wazuh (self-hosted)         │
         Self-Hosted     │  Falco + AIDE (DIY)          │
                         │                              │
                         │                              │
         ─────────────── ┼ ─────────────────────────────┤
         Manual Rules    │              ML-Based        │
         Only            │              + Explainable   │
```

**SkieSecure FIM occupies an uncontested position:** ML-based, explainable FIM delivered as
a managed MSSP service for SMBs at $8-15/host effective cost. No one else is here.

---

## Comparative Indicators

### Detection Capability

| Indicator | Prisma | CrowdStrike | Lacework | Sysdig | Aqua | Wiz | Wazuh | SkieSecure FIM |
|---|---|---|---|---|---|---|---|---|
| Real-time host FIM | Yes | Yes (FileVantage) | Yes | Partial | No | No | Yes | Yes (auditd) |
| Real-time container FIM | Yes | Yes | Yes | Yes (Falco) | Yes (Tracee) | No | Partial | Yes (Tetragon) |
| Hash-based verification | Yes | Yes | No | No | Yes | Yes (snapshot) | Yes | Yes (AIDE) |
| eBPF-based monitoring | Yes | Yes | No | Yes | Yes | No | No | Yes (Tetragon) |
| In-kernel enforcement | Yes | Yes | No | No | Yes | No | No | Yes (Tetragon) |
| ML behavioural profiling | Yes | Yes (Charlotte AI) | Yes (Polygraph) | Yes | No | No | No | Yes (VAE + IF) |
| ML explainability (SHAP) | No | No | No | No | No | No | No | **Yes** |
| Training-less detection | No | No | No | No | No | No | No | **Yes (ReplicaWatcher)** |
| Supply chain (image signing) | Yes | Partial | Yes | Yes | Yes | Yes | No | Yes (cosign) |
| SBOM integration | Yes | Yes | Yes | Yes | Yes | Yes | No | Yes (Syft) |
| Analyst feedback loop | No | No | No | No | No | No | No | **Yes** |

### Operational Model

| Indicator | Prisma | CrowdStrike | Lacework | Sysdig | Aqua | Wiz | Wazuh | SkieSecure FIM |
|---|---|---|---|---|---|---|---|---|
| Deployment model | SaaS | SaaS | SaaS | SaaS | SaaS | SaaS | Self-hosted | **MSSP SaaS** |
| Multi-tenant (MSSP-ready) | No | No | No | No | No | No | Partial | **Yes (native)** |
| Agent weight | Heavy | Light | Medium | Medium | Medium | None | Medium | **Light (auditd + Vector)** |
| Time to value | Days | Hours | Days | Hours | Hours | Minutes | Weeks | **Hours** (Day-1 ReplicaWatcher) |
| Open-source core | No | No | No | Falco only | Tracee only | No | Yes | **Yes** |
| Unified host+container view | Separate modules | Separate modules | Yes | Partial | No | N/A | Partial | **Yes (single schema)** |

### Compliance

| Indicator | Prisma | CrowdStrike | Lacework | Sysdig | Aqua | Wiz | Wazuh | SkieSecure FIM |
|---|---|---|---|---|---|---|---|---|
| PCI-DSS FIM evidence | Yes | Yes (FileVantage) | Yes | Yes | Yes | Partial | Yes | Yes |
| Auto-generated audit reports | Yes | Yes | Partial | Yes | Yes | Yes | Yes | Yes |
| CIS benchmark scanning | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No (roadmap) |
| ML alert audit trail (explainable) | No | No | No | No | No | No | No | **Yes (SHAP)** |

### Pricing (Effective per-endpoint/month for 200 endpoints)

| Vendor | Approximate Cost | Notes |
|---|---|---|
| Prisma Cloud | $30-50/endpoint | Enterprise contract, annual commitment |
| CrowdStrike (Falcon + FileVantage + Cloud) | $33-60/endpoint | Module stack-up |
| FortiCNAPP (ex-Lacework) | $25-40/endpoint | Post-acquisition pricing unclear |
| Sysdig Secure | $20-40/endpoint | Per-host pricing |
| Aqua Security | $15-30/endpoint | Per-host pricing |
| Wiz | $30-50/workload | Agentless, no runtime FIM |
| Wazuh Cloud | $5-15/agent | Limited features vs self-hosted |
| Wazuh (self-hosted) | $0 (+ ops cost ~$2-5K/month infra) | Requires dedicated team |
| **SkieSecure FIM (Growth tier)** | **~$15/endpoint effective** | **Bundled with SOC, XDR, detection** |
| **SkieSecure FIM-only add-on** | **$8/endpoint** | **FIM module only** |

---

## SkieSecure FIM Differentiators (Summary)

### 1. MSSP-Native Multi-Tenancy
No other CWPP/CNAPP is designed for MSSP delivery. Prisma Cloud, CrowdStrike, and Sysdig
are all single-tenant-per-customer. SkieSecure's 8-layer tenant isolation model means one
platform instance serves hundreds of SMB customers efficiently.

### 2. Explainable ML (SHAP)
Every competitor with ML (Prisma, CrowdStrike Charlotte AI, Lacework Polygraph, Sysdig)
provides black-box verdicts. SkieSecure FIM provides per-feature SHAP explanations on every
alert — making ML-generated alerts admissible as compliance evidence. This is unique in the
market.

### 3. Training-Less Day-1 Detection
ReplicaWatcher-inspired cross-replica comparison provides anomaly detection from the first
hour of deployment, without historical data. Competitors require days-to-weeks of baseline
learning before their ML becomes useful.

### 4. Unified Host + Container + Supply Chain Schema
Most competitors have separate modules for host FIM, container runtime, and supply chain
security, each with their own UI, query language, and alert format. SkieSecure normalises
everything to OCSF and presents it in a single ClickHouse-backed view.

### 5. Open-Source Core
The detection agents (auditd, AIDE, Tetragon, Falco, cosign) are all open source. Customers
are never locked into proprietary detection engines. The SaaS value-add is multi-tenant
ML, compliance reporting, and managed operations — not agent lock-in.

### 6. SMB Price Point
At $8-15/endpoint effective cost, SkieSecure FIM is 3-5x cheaper than enterprise alternatives.
For an SMB with 200 endpoints, that's $1,600-3,000/month vs $6,000-12,000/month for
CrowdStrike or Prisma Cloud.

---

## Competitive Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Enterprise vendors create SMB tiers | Medium | Build MSSP multi-tenancy moat — enterprise vendors won't redesign for multi-tenant MSSP delivery |
| Wazuh adds eBPF + ML | Medium | Wazuh is community-driven with slow feature velocity. eBPF would require kernel-module-level changes to their agent architecture |
| CrowdStrike acquires an MSSP platform | High | Move fast. Build customer base and switching cost before consolidation happens |
| Open-source alternatives mature (Falco + Kubescape + AIDE) | Low | The integration is the value, not the components. DIY assembly of 5+ OSS tools is what SMBs can't do |
| Fortinet bundles FortiCNAPP into FortiGate pricing | Medium | Fortinet's SMB customers get basic CNAPP free, but without MSSP SOC operations |

---

## Go-To-Market Positioning

> **For SMBs running hybrid infrastructure** (VMs + Kubernetes) who need compliance-grade
> file integrity monitoring but can't afford enterprise CWPP platforms or staff a security
> team to operate open-source tools — **SkieSecure FIM** delivers ML-powered, explainable
> integrity monitoring as a managed service, bundled with 24/7 SOC operations, at 3-5x
> lower cost than CrowdStrike or Prisma Cloud.

**One-line pitch:**
> "The CrowdStrike FileVantage + Prisma Cloud Runtime you can't afford, delivered as
> a managed service with ML that auditors actually understand."

---

## Sources

- [Prisma Cloud CWPP](https://www.paloaltonetworks.com/prisma/cloud/cloud-workload-protection-platform)
- [CrowdStrike Falcon FileVantage](https://www.crowdstrike.com/en-us/blog/introducing-falcon-filevantage/)
- [FortiCNAPP / Lacework](https://www.lacework.com/)
- [Sysdig Secure](https://www.sysdig.com/opensource/falco)
- [Aqua Security Tracee](https://www.aquasec.com/)
- [Wiz CNAPP](https://www.wiz.io/)
- [Wazuh](https://github.com/wazuh/wazuh)
- [CWPP Market Report 2024-2030 (Frost & Sullivan)](https://store.frost.com/cloud-workload-protection-platform-cwpp-and-cloud-security-posture-management-cspm-market-global-2024-2030.html)
- [CNAPP Market Size (P&S Market Research)](https://www.psmarketresearch.com/market-analysis/cloud-native-application-protection-platform-market)
- [eBPF Runtime Security Comparison (SciTePress 2025)](https://www.scitepress.org/Papers/2025/142727/142727.pdf)
- [AccuKnox CWPP Vendors 2026](https://accuknox.com/blog/cwpp-vendors)
