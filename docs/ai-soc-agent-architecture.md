# SkieSecure AI SOC Agents — Architecture and Training Strategy

## The Vision

Build AI agents within SkieSecure that replicate the decision-making of L1, L2, and L3
SOC analysts. Human analysts work cases during business hours; AI agents handle the same
workflows off-hours with equal or greater thoroughness. Over time, the agents learn from
analyst decisions and progressively take over more complex investigations.

**This is the real product.** FIM, detection rules, and telemetry are inputs. The AI SOC
agent is the differentiator that makes SkieSecure's $2-4K/month MSSP pricing viable
without requiring 24/7 human analyst staffing for every tenant.

---

## Why This Works Now (2026)

| Enabler | Status |
|---|---|
| LLMs can reason about security alerts | GPT-4, Claude can complete 61-67% of investigation tasks autonomously (AI SOC Benchmark, 2025) |
| Multi-agent architectures are proven | Enterprise adoption growing — 80% of enterprise workloads expected on AI-driven systems by 2026 |
| Threat intel APIs are mature | MISP, Recorded Future, abuse.ch, AlienVault OTX all have programmatic APIs |
| SOAR playbooks define the workflow | Decades of documented analyst workflows exist as SOAR playbook templates |
| SkieSecure already has the data pipeline | ingestion → detection → alert → case — the agent just needs to sit on top |

**Competitive landscape:**
- **Dropzone AI** — $300K+/year, patented LLM system, enterprise-only
- **Torq HyperSOC** — SOAR + AI, $100K+/year
- **Microsoft Copilot for Security** — Tied to Microsoft stack, $4/incident
- **SkieSecure** — Open-source core, Claude API, bundled in $2-4K/month MSSP

---

## Analyst Workflow Standardisation

Before building AI agents, we must define exactly what L1/L2/L3 analysts do. These
standardised workflows become both the **playbooks** for human analysts and the
**training curriculum** for AI agents.

### L1 Analyst Workflow (Triage)

**Trigger:** New alert in alert-case-service
**Time budget:** 3-5 minutes per alert
**Goal:** Determine true positive vs false positive, escalate or close

```
STEP 1: READ THE ALERT
├── What fired? (Sigma rule ID, detection type)
├── What severity? (critical/high/medium/low)
├── Which tenant? Which host/pod?
└── When? (timestamp, frequency)

STEP 2: CONTEXTUALISE
├── Is this host/pod known? (check asset-service)
├── What's the normal behaviour? (check baseline)
├── Has this alert fired before? (check alert history)
├── Is there a maintenance window? (check tenant calendar)
└── Are there related alerts? (check ±15min window)

STEP 3: ENRICH
├── IP reputation (MISP, AbuseIPDB, Recorded Future)
├── Hash reputation (MalwareBazaar, VirusTotal)
├── Domain reputation (URLhaus, Recorded Future)
├── CVE context (if vulnerability-related)
└── Threat actor context (MISP galaxy, RF actor profiles)

STEP 4: VERDICT
├── FALSE POSITIVE → Close alert, document reason
│   ├── Expected behaviour (deployment, patching, admin action)
│   ├── Known benign (allowlisted process, trusted IP)
│   └── Noise (duplicate, stale data, misconfiguration)
│
├── TRUE POSITIVE (Low/Medium) → Create case, document findings
│   └── Escalate to L2 with enrichment attached
│
└── TRUE POSITIVE (High/Critical) → Create case, escalate immediately
    └── Page L2/L3, attach all enrichment
```

### L2 Analyst Workflow (Investigation)

**Trigger:** Escalated case from L1 or AI agent
**Time budget:** 30-60 minutes per case
**Goal:** Determine scope, impact, root cause, recommend containment

```
STEP 1: SCOPE THE INCIDENT
├── How many hosts/pods affected? (query ClickHouse for related events)
├── Timeline reconstruction (first event → latest event)
├── Lateral movement? (network connections from affected host)
├── Data exfiltration? (unusual outbound traffic patterns)
└── Persistence? (new cron jobs, systemd units, SSH keys)

STEP 2: DEEP INVESTIGATION
├── Process tree analysis (parent → child → grandchild)
├── File change timeline (FIM events on affected host)
├── Network connection graph (source → destination, ports, protocols)
├── User activity (login events, sudo usage, privilege changes)
├── Container context (image version, admission status, drift events)
└── Kubernetes context (RBAC changes, secret access, API audit log)

STEP 3: CORRELATE WITH THREAT INTEL
├── Map to MITRE ATT&CK technique
├── Match IOCs against MISP events
├── Check Recorded Future for campaign context
├── Compare with known threat actor TTPs
└── Check if this matches any active advisories (CISA, vendor)

STEP 4: RECOMMEND
├── CONTAINMENT actions (isolate host, kill pod, revoke credentials)
├── ERADICATION actions (patch, remove persistence, rebuild node)
├── RECOVERY actions (restore from backup, redeploy, verify integrity)
└── EVIDENCE preservation (snapshot, log export, timeline document)

STEP 5: DOCUMENT
├── Executive summary (what happened, what we did, what's next)
├── Technical detail (IOCs, timeline, affected assets)
├── Lessons learned (detection gap? response improvement?)
└── Update detection rules if new TTP discovered
```

### L3 Analyst Workflow (Hunt + Response)

**Trigger:** Threat intel advisory, pattern from L2 investigations, proactive hunt
**Time budget:** 2-8 hours per hunt
**Goal:** Find undetected threats, create new detection rules, improve posture

```
STEP 1: HYPOTHESIS
├── Based on: threat advisory, MISP event, analyst intuition, trend
├── Example: "Are any tenants running containers with the xz-utils
│   backdoor (CVE-2024-3094)?"
└── Define search scope (tenants, time range, data sources)

STEP 2: HUNT
├── Write ad-hoc ClickHouse queries against siem.events + siem.fim_events
├── Search for IOCs across all tenant data (with authorisation)
├── Analyse behavioural patterns (unusual process trees, rare binaries)
├── Cross-reference with SBOM data (vulnerable dependencies)
└── Inspect Polygraph/baseline deviations across fleet

STEP 3: FINDINGS
├── If threat found → Create case, initiate incident response
├── If no threat → Document hunt, update baselines
└── Either way → Create new Sigma rule if detection gap identified

STEP 4: IMPROVE
├── Write new detection rules (Sigma YAML)
├── Update FIM baselines if new normal identified
├── Update enrichment sources if new IOC source discovered
└── Brief team on findings
```

---

## AI Agent Architecture

### Multi-Agent Design

Each analyst level maps to an AI agent with specific capabilities and autonomy:

```
┌─────────────────────────────────────────────────────────────────┐
│                    SkieSecure AI SOC Agents                       │
│                                                                   │
│  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │ L1 Triage Agent  │  │ L2 Investigation  │  │ L3 Hunt Agent  │ │
│  │                  │  │    Agent          │  │                │ │
│  │ Autonomy: HIGH   │  │ Autonomy: MEDIUM  │  │ Autonomy: LOW  │ │
│  │ (auto-close FPs) │  │ (investigate,     │  │ (propose hunts,│ │
│  │                  │  │  recommend)       │  │  human approves)│ │
│  │ Handles:         │  │ Handles:          │  │ Handles:       │ │
│  │ - Alert triage   │  │ - Scope analysis  │  │ - Threat hunts │ │
│  │ - IOC enrichment │  │ - Timeline build  │  │ - Rule creation│ │
│  │ - FP filtering   │  │ - ATT&CK mapping  │  │ - Posture      │ │
│  │ - Escalation     │  │ - Containment rec │  │   improvement  │ │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬────────┘ │
│           │                      │                     │          │
│           ▼                      ▼                     ▼          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Agent Orchestrator                       │  │
│  │                                                            │  │
│  │  - Routes alerts to appropriate agent level                │  │
│  │  - Manages agent state and context                         │  │
│  │  - Enforces autonomy boundaries                            │  │
│  │  - Escalates to human when confidence < threshold          │  │
│  │  - Records all agent actions for audit trail               │  │
│  └────────────────────────┬───────────────────────────────────┘  │
│                           │                                       │
│  ┌────────────────────────┼───────────────────────────────────┐  │
│  │                    Tool Layer                               │  │
│  │                                                            │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │  │
│  │  │ClickHouse│ │ MISP     │ │ Recorded │ │ Asset        │ │  │
│  │  │ Query    │ │ Lookup   │ │ Future   │ │ Service      │ │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘ │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │  │
│  │  │AbuseIPDB │ │MalwareBaz│ │ URLhaus  │ │ Alert/Case   │ │  │
│  │  │ Lookup   │ │ Lookup   │ │ Lookup   │ │ Service      │ │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘ │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │  │
│  │  │Kubernetes│ │ FIM      │ │ Baseline │ │ Notification │ │  │
│  │  │ API      │ │ Service  │ │ Service  │ │ Service      │ │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘ │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### Agent Implementation — Claude Agent SDK

Use the [Anthropic Claude Agent SDK](https://github.com/anthropics/claude-code) or direct
Claude API with tool use for building the agents. Each agent is a Claude conversation with
a system prompt defining its role and a set of tools it can call.

**L1 Triage Agent — System Prompt:**

```
You are an L1 SOC analyst at SkieSecure, a managed security service provider.
Your job is to triage security alerts for tenant environments.

For each alert, follow this exact workflow:
1. READ the alert details (type, severity, tenant, host/pod, timestamp)
2. CONTEXTUALISE using asset-service and alert history
3. ENRICH IOCs using threat intel tools (MISP, AbuseIPDB, MalwareBazaar, URLhaus)
4. VERDICT: classify as false positive or true positive

AUTONOMY RULES:
- You MAY auto-close alerts as false positive if confidence > 95%
- You MAY create cases for true positives
- You MUST escalate to L2 if severity is critical or if you are unsure
- You MUST NOT take containment actions (isolate hosts, kill pods)
- You MUST document your reasoning in the case notes

TENANT ISOLATION:
- You can only query data for the tenant specified in the alert
- Never cross-reference data between tenants
```

**L1 Agent Tools (Claude Tool Use):**

```json
[
  {
    "name": "query_clickhouse",
    "description": "Query ClickHouse for security events. Use for timeline analysis, related alerts, and historical context.",
    "input_schema": {
      "type": "object",
      "properties": {
        "query": { "type": "string", "description": "SQL query against siem.events or siem.fim_events. Must include tenant_id filter." },
        "tenant_id": { "type": "string" }
      },
      "required": ["query", "tenant_id"]
    }
  },
  {
    "name": "lookup_ip_reputation",
    "description": "Check IP address against threat intel sources (AbuseIPDB, MISP, AlienVault OTX).",
    "input_schema": {
      "type": "object",
      "properties": {
        "ip": { "type": "string" },
        "sources": { "type": "array", "items": { "type": "string", "enum": ["abuseipdb", "misp", "otx", "recorded_future"] } }
      },
      "required": ["ip"]
    }
  },
  {
    "name": "lookup_hash_reputation",
    "description": "Check file hash against threat intel sources (MalwareBazaar, MISP, VirusTotal).",
    "input_schema": {
      "type": "object",
      "properties": {
        "hash": { "type": "string" },
        "hash_type": { "type": "string", "enum": ["md5", "sha1", "sha256"] }
      },
      "required": ["hash"]
    }
  },
  {
    "name": "lookup_domain_reputation",
    "description": "Check domain against threat intel sources (URLhaus, MISP, Recorded Future).",
    "input_schema": {
      "type": "object",
      "properties": {
        "domain": { "type": "string" }
      },
      "required": ["domain"]
    }
  },
  {
    "name": "get_asset_context",
    "description": "Get context about a host or container from the asset service.",
    "input_schema": {
      "type": "object",
      "properties": {
        "tenant_id": { "type": "string" },
        "asset_id": { "type": "string", "description": "Hostname, IP, or container ID" }
      },
      "required": ["tenant_id", "asset_id"]
    }
  },
  {
    "name": "get_alert_history",
    "description": "Get previous alerts for the same host/rule/tenant.",
    "input_schema": {
      "type": "object",
      "properties": {
        "tenant_id": { "type": "string" },
        "filter": { "type": "object", "description": "Filter by host, rule_id, severity, time_range" }
      },
      "required": ["tenant_id"]
    }
  },
  {
    "name": "get_fim_baseline",
    "description": "Get the FIM baseline for a host role or container image.",
    "input_schema": {
      "type": "object",
      "properties": {
        "tenant_id": { "type": "string" },
        "target_type": { "type": "string", "enum": ["host_role", "container_image"] },
        "target_id": { "type": "string" }
      },
      "required": ["tenant_id", "target_type", "target_id"]
    }
  },
  {
    "name": "update_alert",
    "description": "Update alert status (close as FP, escalate to L2, create case).",
    "input_schema": {
      "type": "object",
      "properties": {
        "alert_id": { "type": "string" },
        "action": { "type": "string", "enum": ["close_fp", "escalate_l2", "create_case"] },
        "verdict": { "type": "string", "enum": ["false_positive", "true_positive", "needs_investigation"] },
        "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
        "reasoning": { "type": "string", "description": "Detailed reasoning for the verdict" },
        "enrichment_summary": { "type": "string", "description": "Summary of enrichment findings" }
      },
      "required": ["alert_id", "action", "verdict", "confidence", "reasoning"]
    }
  }
]
```

---

## Agent Service Implementation

### New Service: agent-service (NestJS + Claude API)

```
services/agent-service/
├── src/
│   ├── app.module.ts
│   ├── main.ts
│   ├── orchestrator/
│   │   ├── orchestrator.module.ts
│   │   ├── orchestrator.service.ts     # Routes alerts to appropriate agent
│   │   └── escalation.service.ts       # Manages human escalation
│   ├── agents/
│   │   ├── agents.module.ts
│   │   ├── l1-triage.agent.ts          # L1 agent (Claude + tools)
│   │   ├── l2-investigation.agent.ts   # L2 agent (Claude + tools)
│   │   └── l3-hunt.agent.ts            # L3 agent (Claude + tools)
│   ├── tools/
│   │   ├── tools.module.ts
│   │   ├── clickhouse.tool.ts          # Query ClickHouse
│   │   ├── misp.tool.ts                # MISP API lookup
│   │   ├── recorded-future.tool.ts     # RF API lookup (optional paid)
│   │   ├── abuseipdb.tool.ts           # AbuseIPDB lookup
│   │   ├── malwarebazaar.tool.ts       # MalwareBazaar hash lookup
│   │   ├── urlhaus.tool.ts             # URLhaus domain lookup
│   │   ├── otx.tool.ts                 # AlienVault OTX lookup
│   │   ├── asset.tool.ts              # asset-service client
│   │   ├── alert.tool.ts              # alert-case-service client
│   │   ├── fim.tool.ts                # fim-service client
│   │   └── kubernetes.tool.ts          # K8s API queries (for container context)
│   ├── training/
│   │   ├── training.module.ts
│   │   ├── feedback.service.ts         # Captures analyst corrections to agent verdicts
│   │   ├── workflow-recorder.ts        # Records human analyst workflows as training examples
│   │   └── few-shot.service.ts         # Manages few-shot examples for agent prompts
│   ├── audit/
│   │   ├── audit.module.ts
│   │   └── agent-audit.service.ts      # Logs every agent action for compliance
│   ├── consumer/
│   │   └── alert-consumer.ts           # Redpanda: consumes alerts.lifecycle
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

### Core Orchestrator Logic

```typescript
// orchestrator.service.ts (pseudocode)
class OrchestratorService {

  async processAlert(alert: Alert): Promise<void> {
    // 1. Determine which agent level handles this alert
    const level = this.routeAlert(alert);

    // 2. Check if human analyst is available
    const humanAvailable = await this.isHumanOnShift(alert.tenant_id);

    // 3. If human is available AND it's business hours, route to human
    if (humanAvailable && level !== 'l1') {
      await this.routeToHuman(alert, level);
      return;
    }

    // 4. Otherwise, route to AI agent
    const agent = this.getAgent(level);
    const result = await agent.investigate(alert);

    // 5. Check confidence threshold
    if (result.confidence < this.getThreshold(level)) {
      // Below confidence — escalate to human
      await this.escalateToHuman(alert, result, level);
      return;
    }

    // 6. Execute the agent's verdict
    await this.executeVerdict(alert, result);

    // 7. Record for training
    await this.recordAgentAction(alert, result);
  }

  private routeAlert(alert: Alert): 'l1' | 'l2' | 'l3' {
    // Simple routing rules (will be refined by ML over time)
    if (alert.severity <= 'medium') return 'l1';
    if (alert.severity === 'high') return 'l2';
    if (alert.severity === 'critical') return 'l2'; // L3 is hunt-only
    return 'l1';
  }

  private getThreshold(level: string): number {
    // Confidence thresholds for autonomous action
    // Start conservative, loosen as model proves itself
    return {
      'l1': 0.90,  // 90% confidence to auto-close FP
      'l2': 0.95,  // 95% confidence to auto-recommend containment
      'l3': 0.99,  // 99% — L3 almost always needs human approval
    }[level] ?? 0.99;
  }
}
```

---

## Enrichment Pipeline

### Threat Intel Sources (All Open Source or Free Tier)

```
┌─────────────────────────────────────────────────────────────┐
│                  Enrichment Pipeline                          │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Feed Ingestion (Scheduled)                   │ │
│  │                                                           │ │
│  │  Every 15 min:                                            │ │
│  │  ├── abuse.ch feeds (URLhaus, MalwareBazaar, Feodo)      │ │
│  │  ├── AlienVault OTX pulse subscriptions                   │ │
│  │  └── MISP feed sync (CIRCL, community feeds)             │ │
│  │                                                           │ │
│  │  Every 1 hour:                                            │ │
│  │  ├── CISA Known Exploited Vulnerabilities (KEV)          │ │
│  │  └── NVD CVE updates                                      │ │
│  │                                                           │ │
│  │  → All IOCs stored in Redis (key: ioc:{type}:{value})    │ │
│  │  → TTL: 24 hours (re-ingested on next cycle)             │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Real-Time Lookup (On-Demand)                 │ │
│  │                                                           │ │
│  │  When AI agent requests enrichment:                       │ │
│  │                                                           │ │
│  │  1. Check Redis cache (< 1ms)                            │ │
│  │     └── HIT: return cached result                         │ │
│  │     └── MISS: continue to step 2                          │ │
│  │                                                           │ │
│  │  2. Query free APIs (< 500ms)                            │ │
│  │     ├── AbuseIPDB (1000 checks/day free)                 │ │
│  │     ├── AlienVault OTX (unlimited, free)                 │ │
│  │     └── abuse.ch API (unlimited, free)                   │ │
│  │                                                           │ │
│  │  3. Query MISP instance (< 200ms)                        │ │
│  │     └── Self-hosted, unlimited queries                    │ │
│  │                                                           │ │
│  │  4. Query paid APIs (optional, if configured)            │ │
│  │     ├── Recorded Future (if tenant has licence)          │ │
│  │     ├── VirusTotal (if tenant has API key)               │ │
│  │     └── Shodan (if tenant has API key)                   │ │
│  │                                                           │ │
│  │  → Cache result in Redis (TTL: 1 hour)                   │ │
│  │  → Return enrichment to agent                             │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### MISP Integration

Deploy a SkieSecure-internal MISP instance for IOC management:

```yaml
# platform/misp/values.yaml
image:
  repository: ghcr.io/misp/misp-docker/misp-core
  tag: "latest"

service:
  port: 443

database:
  host: platform-postgres-postgresql.platform.svc.cluster.local
  name: misp_db

redis:
  host: platform-redis-master.platform.svc.cluster.local

# Feed subscriptions (auto-sync)
feeds:
  - name: "CIRCL OSINT Feed"
    url: "https://www.circl.lu/doc/misp/feed-osint"
    enabled: true
  - name: "abuse.ch URLhaus"
    url: "https://urlhaus.abuse.ch/downloads/misp"
    enabled: true
  - name: "abuse.ch MalwareBazaar"
    url: "https://bazaar.abuse.ch/export/misp"
    enabled: true
  - name: "Botvrij.eu"
    url: "https://www.botvrij.eu/data/feed-osint"
    enabled: true
```

### Recorded Future Integration (Optional Paid Add-On)

For tenants with Recorded Future licences, the enrichment pipeline can query RF:

```typescript
// tools/recorded-future.tool.ts
class RecordedFutureTool {
  // Only available if tenant has RF_API_KEY configured
  async lookupIP(ip: string, tenantId: string): Promise<RFResult | null> {
    const apiKey = await this.getTenantConfig(tenantId, 'RF_API_KEY');
    if (!apiKey) return null; // Tenant doesn't have RF

    const response = await fetch(
      `https://api.recordedfuture.com/v2/ip/${ip}`,
      { headers: { 'X-RFToken': apiKey } }
    );
    return response.json();
  }
}
```

---

## Training Strategy: How Agents Learn Over Time

### Phase 1: Rule-Based (Weeks 1-4)

Agents follow hardcoded playbooks. No learning. This is the baseline.

```
Alert → Playbook lookup → Execute steps → Verdict
```

**Playbooks are Sigma rules + enrichment steps + decision trees.** Written by humans.

### Phase 2: Few-Shot Learning from Human Analysts (Weeks 5-12)

Every human analyst action is recorded:

```typescript
// training/workflow-recorder.ts
interface AnalystAction {
  alert_id: string;
  analyst_id: string;
  analyst_level: 'l1' | 'l2' | 'l3';
  timestamp: string;

  // What the analyst did
  action_type: 'query' | 'enrich' | 'verdict' | 'escalate' | 'note';
  action_detail: {
    // For 'query': the ClickHouse SQL they ran
    // For 'enrich': the IOC they looked up and source
    // For 'verdict': their classification and reasoning
    // For 'escalate': who they escalated to and why
    // For 'note': free-text investigation notes
  };

  // Context at the time of action
  alert_snapshot: Alert;
  enrichment_available: EnrichmentResult[];
  related_alerts: Alert[];
}
```

These recordings are stored in PostgreSQL (`agent_training_db`) and converted to
**few-shot examples** in agent prompts:

```
You are an L1 SOC analyst. Here are examples of how experienced analysts
handled similar alerts:

EXAMPLE 1:
Alert: FIM binary modification in /usr/bin/curl on host prod-web-03
Analyst: Queried ClickHouse for recent deployments on prod-web-03
Result: apt-get upgrade ran 2 minutes before the FIM alert
Analyst: Checked deployment calendar — scheduled patching window
Verdict: FALSE POSITIVE (confidence: 0.98)
Reasoning: File change coincides with scheduled package upgrade

EXAMPLE 2:
Alert: FIM binary modification in /usr/bin/wget on host prod-db-01
Analyst: Queried ClickHouse — no deployments in past 24 hours
Analyst: Checked parent process — spawned by /tmp/shell.sh
Analyst: Looked up hash of new wget binary — not in MalwareBazaar
Analyst: Checked /tmp/shell.sh — downloaded from 45.33.x.x
Analyst: Looked up 45.33.x.x — AbuseIPDB confidence 97% (C2 server)
Verdict: TRUE POSITIVE (confidence: 0.99)
Reasoning: Binary replacement via script downloaded from known C2

Now investigate this alert:
[current alert details]
```

### Phase 3: Supervised Autonomy (Months 3-6)

AI agents triage alerts autonomously but every verdict is **reviewed by a human
within 24 hours**. Human corrections feed back:

```
AI Agent Verdict → Alert Queue (auto-processed)
                 → Review Queue (human checks within 24h)
                 → If human disagrees → Correction recorded
                 → Correction → Updates few-shot examples
                 → Tightens/loosens confidence thresholds
```

**Metrics tracked:**
- Agent accuracy (% of verdicts matching human review)
- False negative rate (agent closed as FP, human disagrees)
- False positive rate (agent escalated unnecessarily)
- Mean time to triage (agent) vs mean time to triage (human)
- Enrichment coverage (% of alerts with full enrichment)

### Phase 4: Progressive Autonomy (Months 6-12)

As agent accuracy improves, autonomy boundaries widen:

| Metric | Autonomy Level | Action |
|---|---|---|
| Agent accuracy > 90% | Level 1 | Auto-close low-severity FPs |
| Agent accuracy > 95% | Level 2 | Auto-close medium-severity FPs, auto-create cases for TPs |
| Agent accuracy > 98% | Level 3 | Auto-recommend containment actions (human approves) |
| Agent accuracy > 99% | Level 4 | Auto-execute containment for known patterns (kill pod, block IP) |

**Guardrails that never loosen:**
- Agent can never delete data
- Agent can never modify detection rules without human approval
- Agent can never access data outside the alert's tenant
- Agent can never take destructive actions on customer infrastructure
- All agent actions are logged in audit trail (immutable in ClickHouse)

### Phase 5: Continuous Improvement (Ongoing)

```
┌─────────────┐     ┌───────────────┐     ┌──────────────────┐
│ New Alert    │────▶│ AI Agent      │────▶│ Verdict          │
│ (from Kafka) │     │ investigates  │     │ (auto or human)  │
└─────────────┘     └───────────────┘     └────────┬─────────┘
                                                    │
                                                    ▼
                                          ┌──────────────────┐
                                          │ Human Review      │
                                          │ (within 24h)      │
                                          └────────┬─────────┘
                                                    │
                              ┌──────────────────────┼─────────────────────┐
                              │                      │                      │
                              ▼                      ▼                      ▼
                    ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
                    │ AGREE        │      │ DISAGREE     │      │ ENHANCED     │
                    │              │      │              │      │              │
                    │ Agent was    │      │ Correction   │      │ Human added  │
                    │ correct.     │      │ recorded.    │      │ steps agent  │
                    │ Reinforce.   │      │ Update few-  │      │ didn't take. │
                    │              │      │ shot examples│      │ Record as    │
                    │              │      │ + thresholds │      │ new workflow. │
                    └──────────────┘      └──────────────┘      └──────────────┘
                              │                      │                      │
                              └──────────────────────┼─────────────────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────┐
                                          │ Agent Improved    │
                                          │ (next iteration)  │
                                          └──────────────────┘
```

---

## Data Model: Agent Training Store

```sql
-- In agent_training_db (PostgreSQL)

-- Every analyst action (human or AI) on an alert
CREATE TABLE analyst_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id UUID NOT NULL,
  tenant_id UUID NOT NULL,
  actor_type VARCHAR(10) NOT NULL,           -- 'human' or 'ai_agent'
  actor_id VARCHAR(255) NOT NULL,            -- analyst email or agent name
  actor_level VARCHAR(5) NOT NULL,           -- 'l1', 'l2', 'l3'
  action_type VARCHAR(50) NOT NULL,          -- 'query', 'enrich', 'verdict', 'escalate', 'note', 'contain'
  action_detail JSONB NOT NULL,              -- full action context
  alert_snapshot JSONB NOT NULL,             -- alert state at time of action
  enrichment_context JSONB,                  -- available enrichment at time of action
  confidence FLOAT,                          -- agent's confidence (null for human)
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_actions_alert ON analyst_actions(alert_id);
CREATE INDEX idx_actions_tenant ON analyst_actions(tenant_id);
CREATE INDEX idx_actions_actor ON analyst_actions(actor_type, actor_id);

-- Human corrections to AI agent verdicts
CREATE TABLE agent_corrections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id UUID NOT NULL,
  tenant_id UUID NOT NULL,
  agent_verdict VARCHAR(50) NOT NULL,        -- what agent said
  agent_confidence FLOAT NOT NULL,
  agent_reasoning TEXT NOT NULL,
  human_verdict VARCHAR(50) NOT NULL,        -- what human said
  human_reasoning TEXT NOT NULL,
  correction_type VARCHAR(50) NOT NULL,      -- 'wrong_verdict', 'missed_enrichment', 'wrong_severity', 'incomplete_investigation'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_by VARCHAR(255) NOT NULL          -- analyst who corrected
);

CREATE INDEX idx_corrections_type ON agent_corrections(correction_type);

-- Curated few-shot examples (selected from best analyst actions)
CREATE TABLE few_shot_examples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_level VARCHAR(5) NOT NULL,           -- 'l1', 'l2', 'l3'
  alert_type VARCHAR(100) NOT NULL,          -- 'fim_binary_tamper', 'brute_force', 'lateral_movement'
  example_quality FLOAT NOT NULL,            -- curator score (0-1)
  alert_context JSONB NOT NULL,              -- anonymised alert details
  investigation_steps JSONB NOT NULL,        -- ordered list of steps taken
  verdict JSONB NOT NULL,                    -- classification + reasoning
  is_active BOOLEAN DEFAULT true,
  created_from_action_id UUID REFERENCES analyst_actions(id),
  curated_by VARCHAR(255),                   -- who approved this as an example
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_examples_type ON few_shot_examples(agent_level, alert_type);
```

---

## Redpanda Topics (Agent-Specific)

```bash
rpk topic create agent.tasks --partitions 6 --replicas 1        # Alerts assigned to agents
rpk topic create agent.actions --partitions 12 --replicas 1     # Agent actions (audit trail)
rpk topic create agent.verdicts --partitions 6 --replicas 1     # Agent verdicts (for review queue)
rpk topic create agent.corrections --partitions 3 --replicas 1  # Human corrections to agents
```

---

## Kong Route

```yaml
- name: agent-service
  url: http://agent-service.apps.svc.cluster.local:3000
  routes:
    - name: agent-service-route
      paths:
        - /api/agents
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

## Frontend Extensions

### analyst-portal — AI Agent Dashboard

```
app/agents/page.tsx                    # Agent overview dashboard
├── Active agents and their current tasks
├── Agent accuracy metrics (rolling 7/30 day)
├── Alerts processed (human vs AI breakdown)
├── Agent autonomy level per tenant
└── Recent corrections (what agents got wrong)

app/agents/review/page.tsx             # Human review queue
├── Agent verdicts pending human review
├── Agree/Disagree buttons with reasoning field
├── Side-by-side: agent investigation vs human investigation
└── "Promote to few-shot example" button

app/agents/training/page.tsx           # Training management
├── Few-shot example library (by alert type, agent level)
├── Example quality scores
├── Add/edit/deactivate examples
└── Agent prompt preview (see what the agent sees)

app/agents/audit/page.tsx              # Agent audit trail
├── Every action every agent took, with timestamps
├── Full investigation transcript per alert
├── Exportable for compliance (SOC 2 CC7.2)
└── Filter by tenant, agent level, verdict
```

### customer-portal — AI Transparency

```
app/alerts/[id]/page.tsx               # Alert detail (existing, extended)
├── NEW: "Investigated by AI" badge (when agent handled the alert)
├── NEW: AI investigation transcript (read-only)
├── NEW: Enrichment sources used
├── NEW: Confidence score
└── NEW: "Request human review" button (escalate if customer disagrees)
```

---

## Cost Model: AI Agents vs Human Analysts

| | Human-Only SOC (24/7) | AI-Augmented SOC (SkieSecure) |
|---|---|---|
| L1 analysts needed (24/7 coverage) | 5 FTEs (3 shifts + coverage) | 1 FTE (business hours review) |
| L1 analyst cost | $400K/year (5 x $80K) | $80K/year |
| Claude API cost (L1 agent) | $0 | ~$2K/month ($0.01-0.05 per alert at ~2000 alerts/day) |
| L2 analysts needed | 2 FTEs | 1 FTE (complex cases + review) |
| L2 analyst cost | $220K/year (2 x $110K) | $110K/year |
| Claude API cost (L2 agent) | $0 | ~$1K/month ($0.10-0.50 per investigation) |
| **Total annual cost** | **$620K** | **$226K** |
| **Alerts per day capacity** | ~500 (human bottleneck) | ~10,000+ (AI handles volume) |
| **Off-hours coverage** | Yes (expensive) | Yes (AI agents, $3K/month) |

**At 50 tenants:** $620K/50 = $12.4K/tenant/year for human SOC vs $226K/50 = $4.5K/tenant/year
for AI-augmented SOC. This is why the $2-4K/month pricing works.

---

## Implementation Roadmap

### Sprint 1: Foundation (Weeks 1-2)
- [ ] Create agent-service from NestJS template
- [ ] Implement tool layer (ClickHouse query, alert-case-service client)
- [ ] Implement L1 triage agent with Claude API (hardcoded playbook prompts)
- [ ] Wire to alerts.lifecycle Redpanda topic
- [ ] Agent audit trail (log every action to ClickHouse)

### Sprint 2: Enrichment (Weeks 3-4)
- [ ] Deploy MISP instance (platform/misp Helm chart)
- [ ] Implement abuse.ch feed ingestion (URLhaus, MalwareBazaar, Feodo)
- [ ] Implement AbuseIPDB, AlienVault OTX lookup tools
- [ ] Redis-based IOC cache with TTL
- [ ] Recorded Future tool (optional, per-tenant config)

### Sprint 3: Workflow Recording (Weeks 5-6)
- [ ] Implement analyst_actions table and recording middleware
- [ ] Instrument alert-case-service to record every human action
- [ ] Instrument agent-service to record every AI action
- [ ] Build review queue in analyst-portal (agree/disagree on agent verdicts)

### Sprint 4: Few-Shot Learning (Weeks 7-8)
- [ ] Implement few_shot_examples table and curation workflow
- [ ] Build training management UI in analyst-portal
- [ ] Inject few-shot examples into agent prompts dynamically
- [ ] Implement confidence threshold adjustment based on accuracy metrics

### Sprint 5: L2 Agent + Progressive Autonomy (Weeks 9-12)
- [ ] Implement L2 investigation agent (deeper tools, ATT&CK mapping)
- [ ] Implement progressive autonomy (accuracy → wider boundaries)
- [ ] Agent accuracy dashboard in analyst-portal
- [ ] Customer transparency (AI badge, transcript, escalation button)

### Sprint 6: L3 Hunt Agent (Weeks 13-16)
- [ ] Implement L3 hunt agent (hypothesis generation, fleet-wide queries)
- [ ] Threat intel advisory → automated hunt workflow
- [ ] New Sigma rule proposal from hunt findings
- [ ] Human approval workflow for L3 agent recommendations

---

## Sources

- [AI-Augmented SOC: A Survey of LLMs and Agents for Security Automation (MDPI 2025)](https://www.mdpi.com/2624-800X/5/4/95)
- [LLMs in the SOC: An Empirical Study of Human-AI Collaboration in SOCs (arXiv)](https://arxiv.org/html/2508.18947v1)
- [AgenticCyOps: Securing Multi-Agentic AI Integration in Enterprise Cyber Operations (arXiv)](https://arxiv.org/html/2603.09134v1)
- [AI in the SOC: Benchmarking LLMs for Autonomous Alert Triage (Simbian)](https://simbian.ai/blog/the-first-ai-soc-llm-benchmark)
- [Dropzone AI — Autonomous AI SOC Analyst](https://www.dropzone.ai/ai-soc-analyst)
- [MISP Open Source Threat Intelligence Platform](https://www.misp-project.org/)
- [Recorded Future + MISP Integration](https://www.recordedfuture.com/blog/misp-integration-overview)
- [How AI Agents Are Transforming Alert Triage in SOCs (Vooban 2026)](https://vooban.com/en/articles/2026/02/how-ai-agents-are-transforming-alert-triage-in-security-operations-centers)
