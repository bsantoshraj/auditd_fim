# SkieSecure FIM — Gartner Positioning & Feature Parity Analysis

## Target Quadrant: Niche Player → Visionary (18-Month Trajectory)

Gartner's CNAPP evaluation framework (2025 Market Guide) assesses platforms across
**completeness of vision** (x-axis) and **ability to execute** (y-axis). SkieSecure FIM
should target the **Visionary** quadrant — strong completeness of vision (unified
host+container+supply chain with ML explainability) with growing ability to execute
(MSSP delivery model, SMB customer base).

```
                        ABILITY TO EXECUTE
                              ▲
                              │
              CHALLENGERS     │     LEADERS
                              │
              ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─
                              │     Prisma Cloud
                              │     CrowdStrike
                              │     Wiz
                              │     Microsoft Defender
                              │
              ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─
                              │
              NICHE PLAYERS   │     VISIONARIES
                              │
              Wazuh (OSS)     │     ┌──────────────┐
              Qualys          │     │ SkieSecure   │ ← Target (18 months)
                              │     │ FIM          │
              ┌──────────┐    │     └──────────────┘
              │SkieSecure│    │     Sysdig
              │(today)   │    │     Aqua
              └──────────┘    │     Upwind
                              │
              ────────────────┼────────────────────►
                              │     COMPLETENESS OF VISION
```

**Today (Niche Player):** Strong in a narrow segment (MSSP-delivered FIM with ML) but
limited scope (no CSPM, no CIEM, no IaC scanning).

**Target (Visionary):** Differentiated vision (explainable ML, MSSP multi-tenancy, unified
host+container) with expanding scope to meet Gartner's CNAPP baseline.

---

## Gartner CNAPP Evaluation Criteria — Gap Analysis

The 2025 Gartner Market Guide for CNAPP defines these critical capabilities. Here's where
SkieSecure FIM stands today and what's needed for feature parity:

### Mandatory Capabilities (Must-Have for CNAPP Recognition)

| # | Gartner Criterion | Status | Gap | Priority | Effort |
|---|---|---|---|---|---|
| 1 | **Cloud API integrations (AWS, Azure, GCP)** | Not started | Need read-only API integration for cloud asset inventory | P0 | Medium (4-6 weeks) |
| 2 | **CSPM (Cloud Security Posture Management)** | Not started | Need misconfiguration scanning against CIS benchmarks | P1 | Large (8-12 weeks) |
| 3 | **CWPP (Cloud Workload Protection Platform)** | **Partial** — FIM + runtime protection | Need vulnerability scanning integration | P0 | Medium (4-6 weeks) |
| 4 | **CIEM (Cloud Infrastructure Entitlement Management)** | Not started | Need IAM policy analysis for least privilege | P2 | Large (8-12 weeks) |
| 5 | **Container image scanning** | **Planned** — Syft SBOM + cosign | Need CVE scanning (integrate Trivy or Grype) | P0 | Small (2-3 weeks) |
| 6 | **IaC scanning** | Not started | Need Terraform/CloudFormation misconfiguration detection | P1 | Medium (4-6 weeks) |
| 7 | **Agent-based AND agentless deployment** | **Partial** — agent-based (fim-agent, Tetragon) | Need agentless cloud API scanning for posture | P1 | Medium (4-6 weeks) |
| 8 | **Compliance reporting (CIS, NIST, PCI, HIPAA)** | **Partial** — PCI-DSS 11.5.2, ISO 27001 | Need CIS Kubernetes Benchmark, NIST 800-53, HIPAA | P1 | Medium (4-6 weeks) |
| 9 | **CI/CD pipeline integration** | **Planned** — cosign in CI/CD | Need image scan in CI, policy gate before deploy | P1 | Small (2-3 weeks) |
| 10 | **SOC/SIEM integration** | **Yes** — native (SkieSecure IS the SOC) | Unique advantage — most CNAPPs bolt-on SOC integration | ✓ Done | — |

### Differentiating Capabilities (Gartner "Nice-to-Have" That Move You Right)

| # | Gartner Criterion | Status | SkieSecure Advantage |
|---|---|---|---|
| 11 | **Runtime behavioural analytics** | **Yes** — ML pipeline (VAE, IF, ReplicaWatcher) | Stronger than most — explainable ML with SHAP |
| 12 | **AI-driven remediation** | Not started | Opportunity: auto-remediation playbooks via workflow-service |
| 13 | **Graph-based attack path analysis** | Not started | Opportunity: correlate FIM events with asset-service for attack paths |
| 14 | **Risk prioritisation with context** | **Yes** — anomaly_score + SHAP factors | ML-based risk scoring with feature attribution |
| 15 | **Unified platform (not stitched tools)** | **Yes** — single SkieSecure platform | Native integration, single auth, single UI |
| 16 | **Developer-centric (shift-left)** | **Partial** — cosign + Kyverno | Need developer-facing UI, PR commenting, IDE integration |
| 17 | **Data security (DSPM)** | Not started | Long-term roadmap — scan for secrets/PII in workloads |

---

## Feature Parity Roadmap — Gartner-Aligned

### Phase A: CWPP Foundation (Current — Weeks 1-16)
*Already planned in saas-platform-architecture.md*

Delivers: Host FIM (auditd + AIDE), Container Runtime (Tetragon), Supply Chain (cosign +
Kyverno), ML Anomaly Detection, Compliance Evidence (PCI-DSS, ISO 27001, SOC 2).

**Gartner coverage after Phase A:** CWPP (partial) + FIM (complete) + SOC integration (native)

### Phase B: Vulnerability + Container Scanning (Weeks 17-22)

| Feature | Implementation | Effort |
|---|---|---|
| **CVE scanning for container images** | Integrate Grype (open source, Anchore) as a scanning step in ingestion pipeline. Images scanned at build (CI/CD) and at runtime (periodic re-scan). Results stored in ClickHouse. | 3 weeks |
| **Host vulnerability scanning** | Integrate Vuls (open source) or OpenSCAP via fim-agent. Scheduled scans, results normalised to OCSF and ingested. | 3 weeks |
| **Vulnerability dashboard** | New view in customer-portal showing CVEs by severity, affected workloads, remediation status. Link to SBOM for dependency context. | 2 weeks |

**New open-source components:**

| Component | Purpose | Licence |
|---|---|---|
| Grype | Container image CVE scanning | Apache-2.0 |
| Vuls | Host vulnerability scanning | GPL-3.0 |
| OpenSCAP | CIS benchmark compliance scanning | LGPL-2.1 |

**Gartner coverage after Phase B:** CWPP (complete) + Container scanning (complete)

### Phase C: Cloud Posture + IaC (Weeks 23-32)

| Feature | Implementation | Effort |
|---|---|---|
| **Cloud API integration** | New `cloud-connector-service` (NestJS). Read-only API access to AWS (boto3 via Lambda), Azure (SDK), GCP (SDK). Discovers assets, security groups, IAM policies, storage configs. | 6 weeks |
| **CSPM engine** | Evaluate cloud configs against CIS benchmarks (AWS CIS 1.5, Azure CIS 2.0, GCP CIS 1.3). Use [CloudSploit](https://github.com/aquasecurity/cloudsploit) or [Prowler](https://github.com/prowler-cloud/prowler) as scanning engine. | 4 weeks |
| **IaC scanning** | Integrate [Checkov](https://github.com/bridgecrewio/checkov) (open source, Bridgecrew/Palo Alto). Scan Terraform, CloudFormation, Kubernetes manifests in CI/CD. | 3 weeks |
| **CSPM dashboard** | Cloud posture score, misconfiguration findings, trend over time. | 2 weeks |

**New open-source components:**

| Component | Purpose | Licence |
|---|---|---|
| Prowler | AWS/Azure/GCP security auditing | Apache-2.0 |
| Checkov | IaC misconfiguration scanning | Apache-2.0 |
| CloudSploit | Cloud misconfiguration detection | GPL-3.0 |

**Gartner coverage after Phase C:** CSPM (complete) + IaC scanning (complete) + Cloud integrations (AWS, Azure, GCP)

### Phase D: CIEM + Attack Path (Weeks 33-40)

| Feature | Implementation | Effort |
|---|---|---|
| **CIEM engine** | Analyse IAM policies from cloud-connector-service. Identify over-privileged roles, unused permissions, cross-account trust. Use [iamlive](https://github.com/iann0036/iamlive) patterns. | 6 weeks |
| **Graph-based attack path** | Build asset-relationship graph (Neo4j or in-memory graph). Correlate: vulnerable image + excessive IAM + public exposure = attack path. Similar to Wiz's graph. | 6 weeks |
| **Risk prioritisation** | Combine: CVE severity + cloud exposure + IAM overprivilege + FIM anomaly score → unified risk score per workload. | 3 weeks |

**Gartner coverage after Phase D:** CIEM (complete) + Attack path (complete) + Risk prioritisation (complete)

### Phase E: AI Remediation + Developer Experience (Weeks 41-48)

| Feature | Implementation | Effort |
|---|---|---|
| **AI-driven remediation** | Integrate with SkieSecure workflow-service. For each finding, generate a remediation playbook (Terraform patch, K8s policy, IAM policy change). Use Claude API for context-aware remediation suggestions. | 4 weeks |
| **Developer-facing UI** | PR commenting (GitHub/GitLab integration) for IaC/image scan findings. Developer self-service portal for viewing their workload's security posture. | 4 weeks |
| **CIS Kubernetes Benchmark** | Integrate [kube-bench](https://github.com/aquasecurity/kube-bench) for K8s cluster hardening assessment. | 2 weeks |

**New open-source components:**

| Component | Purpose | Licence |
|---|---|---|
| kube-bench | CIS Kubernetes Benchmark | Apache-2.0 |

---

## Gartner Positioning Timeline

```
                    ABILITY TO EXECUTE
                          ▲
                          │
          CHALLENGERS     │     LEADERS
                          │
          ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─
                          │
                          │
          ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─
                          │
          NICHE PLAYERS   │     VISIONARIES
                          │
     ┌──────────┐         │          ┌──────────────┐
     │ Today    │─ ─ ─ ─ ─┼─ ─ ─ ─ ─│ Phase D-E    │
     │ Phase A  │         │          │ (Month 10)   │
     └──────────┘         │          └──────────────┘
              \           │         ↗
               \          │        /
                ┌─────────┴──────┐
                │ Phase B-C      │
                │ (Month 6)      │
                └────────────────┘
                          │
          ────────────────┼────────────────────►
                          │     COMPLETENESS OF VISION
```

| Phase | Timeline | Gartner Position | Key Capabilities Added |
|---|---|---|---|
| **A (today)** | Months 1-4 | Niche Player (FIM-only) | Host FIM, Container Runtime, Supply Chain, ML, SOC integration |
| **B** | Months 5-6 | Niche Player (CWPP) | Vulnerability scanning, container image scanning |
| **C** | Months 6-8 | Moving to Visionary | CSPM, IaC scanning, Cloud API integration (AWS/Azure/GCP) |
| **D** | Months 8-10 | Visionary | CIEM, Attack path analysis, Unified risk scoring |
| **E** | Months 10-12 | Strong Visionary | AI remediation, Developer experience, CIS K8s Benchmark |

---

## Feature Parity Matrix — Full CNAPP Comparison

After Phase E completion, SkieSecure's CNAPP coverage vs the Leaders:

| Capability | Prisma Cloud | CrowdStrike | Wiz | SkieSecure (Phase E) |
|---|---|---|---|---|
| CSPM | ★★★★★ | ★★★★ | ★★★★★ | ★★★ (Prowler-based) |
| CWPP - Runtime | ★★★★★ | ★★★★★ | ★★ (agentless) | ★★★★ (Tetragon + auditd) |
| CWPP - FIM | ★★★★ | ★★★★★ (FileVantage) | ★★ (snapshot) | ★★★★★ (ML + explainability) |
| CIEM | ★★★★ | ★★★ | ★★★★★ | ★★★ |
| Container Scanning | ★★★★★ | ★★★★ | ★★★★★ | ★★★★ (Grype + Syft) |
| IaC Scanning | ★★★★ | ★★★ | ★★★★ | ★★★ (Checkov) |
| Supply Chain | ★★★★ | ★★★ | ★★★★ | ★★★★ (cosign + Kyverno + SBOM) |
| SOC Integration | ★★★ (bolt-on) | ★★★★ (Falcon platform) | ★★ (bolt-on) | ★★★★★ (native SOC) |
| ML Explainability | ★★ | ★★ (Charlotte AI) | ★ | ★★★★★ (SHAP) |
| MSSP Multi-Tenancy | ★ | ★ | ★ | ★★★★★ |
| Attack Path | ★★★★ | ★★★ | ★★★★★ | ★★★ |
| AI Remediation | ★★★★ | ★★★ | ★★★★ | ★★★ (Claude API) |
| Developer UX | ★★★★ | ★★★ | ★★★★★ | ★★★ |
| Compliance Reporting | ★★★★★ | ★★★★★ | ★★★★ | ★★★★ |
| Pricing (SMB) | ★ ($30-50/host) | ★ ($33-60/host) | ★★ ($30-50/wkld) | ★★★★★ ($8-15/host) |

**SkieSecure wins on:** FIM depth, ML explainability, MSSP multi-tenancy, SOC integration,
price.

**SkieSecure trails on:** CSPM depth, CIEM depth, Attack path analysis, Developer UX.

**Strategic choice:** Don't try to match Leaders on CSPM/CIEM depth (they have 500+ engineers).
Instead, be **best-in-class on runtime integrity (FIM + CWPP)** and **good-enough on
posture (CSPM + CIEM)** by leveraging open-source engines (Prowler, Checkov). Win on the
dimensions Leaders can't easily replicate: MSSP delivery, ML explainability, SMB pricing.

---

## Gartner Recognition Strategy

### Year 1: Get on the Radar

1. **Submit to Gartner Peer Insights** — Customer reviews are the fastest path to Gartner
   analyst attention. Target 10+ verified reviews from paying customers.

2. **Respond to Gartner CNAPP Market Guide inquiries** — When Gartner analysts research
   CNAPP vendors, proactively brief them on SkieSecure's differentiated MSSP approach.

3. **Publish thought leadership** — Write about:
   - "Why CNAPP Needs MSSP Delivery for SMBs" (positions the market gap)
   - "Explainable ML in Cloud Security: Beyond Black-Box Detection" (positions the technical
     differentiator)
   - "Open-Source CNAPP: Building on Tetragon, Falco, and Prowler" (positions the community
     angle)

### Year 2: Target Niche Player → Visionary

4. **Complete Phase C** (CSPM + IaC) to meet Gartner's minimum CNAPP definition.

5. **Demonstrate customer traction** — Gartner's "ability to execute" axis requires:
   - Revenue growth
   - Customer count (target 50+ paying tenants)
   - Customer satisfaction (NPS, Peer Insights ratings)
   - Geographic presence

6. **Analyst briefing** — Request a formal Gartner analyst briefing. Present:
   - Unified host+container+supply chain architecture
   - ML explainability as compliance differentiator
   - MSSP multi-tenancy as delivery model innovation
   - Open-source core as community/trust differentiator

---

## Investment Priority (Engineering Resources)

Based on Gartner criteria and competitive gaps:

| Priority | Feature | Why | Weeks | Engineers |
|---|---|---|---|---|
| **P0** | FIM ML Pipeline (Phase A) | Core differentiator — this IS SkieSecure FIM | 16 | 3 |
| **P0** | Container image scanning (Grype) | Gartner mandatory; table-stakes for CNAPP | 3 | 1 |
| **P1** | CSPM via Prowler | Gartner mandatory; unlocks "CNAPP" label | 4 | 1 |
| **P1** | IaC scanning via Checkov | Gartner mandatory; CI/CD integration story | 3 | 1 |
| **P1** | CIS compliance reporting | Gartner mandatory; broadens compliance beyond PCI | 4 | 1 |
| **P1** | Cloud API integration (AWS first) | Foundation for CSPM + CIEM | 6 | 2 |
| **P2** | CIEM | Gartner mandatory but not urgent for SMB market | 6 | 1 |
| **P2** | Attack path analysis | Differentiating but complex; do after CIEM | 6 | 2 |
| **P2** | AI remediation (Claude API) | Gartner "reshaping" criterion; high impact | 4 | 1 |
| **P3** | DSPM (data security) | Emerging Gartner criterion; long-term | 8 | 2 |
| **P3** | Developer UX (PR comments, IDE) | Nice-to-have for SMB market | 4 | 1 |

**Total estimated effort for full Gartner CNAPP coverage:** ~64 engineering-weeks (~16 months
with a team of 4 engineers, or ~8 months with 8 engineers).

---

## Open-Source Components — Complete Bill of Materials (All Phases)

| Phase | Component | Purpose | Licence |
|---|---|---|---|
| A | auditd | Host syscall monitoring | GPL-2.0 |
| A | AIDE | Hash-based FIM | GPL-2.0 |
| A | Tetragon | Container eBPF runtime | Apache-2.0 |
| A | Falco | Container detection rules | Apache-2.0 |
| A | cosign | Image signing | Apache-2.0 |
| A | Kyverno | Admission control | Apache-2.0 |
| A | Syft | SBOM generation | Apache-2.0 |
| A | PyTorch | ML models (VAE, Autoencoder) | BSD-3 |
| A | scikit-learn | Isolation Forest | BSD-3 |
| A | XGBoost | Drift classifier | Apache-2.0 |
| A | SHAP | ML explainability | MIT |
| A | MLflow | Model versioning | Apache-2.0 |
| B | Grype | Container image CVE scanning | Apache-2.0 |
| B | Vuls | Host vulnerability scanning | GPL-3.0 |
| C | Prowler | Cloud security posture auditing | Apache-2.0 |
| C | Checkov | IaC misconfiguration scanning | Apache-2.0 |
| D | Neo4j Community | Graph database for attack paths | GPL-3.0 |
| E | kube-bench | CIS Kubernetes Benchmark | Apache-2.0 |

**All core components are Apache-2.0 or permissive.** GPL components (AIDE, Vuls, Neo4j
Community) are used as standalone tools, not linked into SkieSecure's codebase — no GPL
contamination risk.

---

## Sources

- [2025 Gartner Market Guide for CNAPP — Orca Takeaways](https://orca.security/resources/blog/gartner-2025-market-guide-for-cnapp/)
- [2025 Gartner Market Guide for CNAPP — Sysdig Takeaways](https://www.sysdig.com/blog/2025-gartner-cnapp-market-guide)
- [2025 Gartner Market Guide for CNAPP — Uptycs Takeaways](https://www.uptycs.com/blog/gartner-market-guide-for-cnapp-2025-key-takeaways)
- [2025 Gartner Market Guide for CNAPP — Wiz Takeaways](https://www.wiz.io/blog/unpacking-cnapp-gartner-market-guide)
- [2025 Gartner Market Guide for CNAPP — Upwind Takeaways](https://www.upwind.io/feed/2025-gartner-market-guide-for-cloud-native-application-protection-platforms-5-takeaways-that-we-believe-matter)
- [CNAPP Market Size (P&S Market Research)](https://www.psmarketresearch.com/market-analysis/cloud-native-application-protection-platform-market)
- [CWPP Market Report 2024-2030 (Frost & Sullivan)](https://store.frost.com/cloud-workload-protection-platform-cwpp-and-cloud-security-posture-management-cspm-market-global-2024-2030.html)
- [Gartner Peer Insights — CNAPP](https://www.gartner.com/reviews/market/cloud-native-application-protection-platforms)
