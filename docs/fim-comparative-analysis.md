# File Integrity Monitoring — Comparative Analysis

## Purpose

Evaluate FIM tools to complement our existing auditd deployment. The goal is to close
the hash-based verification gap that auditd alone cannot address, while keeping
deployment and operational cost proportional to the threat model.

---

## The Gap in auditd-only FIM

Our current auditd ruleset provides real-time, attributed change detection (who, what
process, when). However it **cannot**:

- Verify a file is still in its known-good state (no baseline, no hash)
- Detect offline tampering (boot media, rescue mode, disk mount)
- Detect bit-rot or silent storage corruption
- Prove integrity for compliance (PCI-DSS 11.5 increasingly expects hash-based FIM)
- Detect changes that occurred before auditd started or during kernel bypass

A hash-based tool fills these gaps.

---

## Candidates Evaluated

| Tool | Type | License |
|---|---|---|
| AIDE | Hash-based, periodic scan | GPL v2 |
| OSSEC/Wazuh | Hash + inotify, agent-based | GPL v2 |
| Tripwire OSS | Hash-based, periodic scan | GPL v2 |
| Samhain | Hash-based, daemon + optional kernel module | GPL v2 |

---

## Detailed Comparison

### AIDE (Advanced Intrusion Detection Environment)

**How it works:** Single binary, no daemon. Builds a database of cryptographic hashes
(SHA-256/SHA-512), permissions, ownership, timestamps, ACLs, SELinux contexts, and
xattrs. Subsequent runs compare filesystem state against the baseline and report diffs.

**Strengths:**
- Minimal footprint — single binary + config file + database, no daemon between scans
- Simple config format, well-documented
- Available in all major distro repos (`apt install aide`, `yum install aide`)
- Deployable via Tanium with zero additional infrastructure
- Actively maintained, strong community
- Zero resource usage between scans

**Weaknesses:**
- No real-time detection (periodic scan only, typical: daily or 4-6h)
- No attribution (what changed, not who changed it — auditd covers this)
- Baseline management is operationally heavy — must update after every legitimate
  change (patching, config updates) or face false positive floods
- Output is text-based, not structured — needs a wrapper for SIEM ingestion
- No central management (single-host tool)
- Transient changes (modified then reverted between scans) are invisible

**Resource overhead:** I/O burst during scan only (2-10 min depending on scope).
Zero between scans. Mitigable with `nice`/`ionice`.

**Chronicle integration:** Custom parser required. Wrap output in JSON via a script,
forward via syslog. No native Chronicle parser.

**Compliance:** Directly satisfies PCI-DSS 11.5, HIPAA integrity controls, CIS file
integrity benchmarks, SOC2 CC6.1. Auditors generally accept hash-based verification
as stronger evidence than event-only logging.

---

### OSSEC / Wazuh

**How it works:** Agent-based platform. The Wazuh agent runs on each host performing
periodic hash scans AND real-time inotify-based change detection. A central Wazuh
Manager aggregates events from all agents. Also consumes and correlates auditd logs
via its log analysis engine.

**Strengths:**
- Best-of-both-worlds: hash verification + real-time inotify detection
- Centralized management, alerting, and correlation across the fleet
- Built-in compliance dashboards (PCI-DSS, HIPAA, NIST 800-53, CIS, SOC2)
- Structured JSON output, Chronicle parser available
- Automatic baseline management (agent handles updates)
- Additional capabilities beyond FIM: rootkit detection, vulnerability scanning,
  log analysis, active response
- Can consume existing auditd events and enrich them

**Weaknesses:**
- Significant deployment footprint: requires Wazuh Manager cluster (2-4 nodes),
  OpenSearch/Elasticsearch indexer, and agents on every endpoint
- Functional overlap with Tanium — running two endpoint agent platforms creates
  operational and political complexity
- Agent daemon: 50-150 MB RAM, 1-3% CPU continuous overhead
- inotify kernel watch limit (`fs.inotify.max_user_watches`) can conflict with
  applications
- If you only need FIM, Wazuh is dramatically overkill
- Infrastructure cost is non-trivial despite zero license fees

**Resource overhead:** Continuous agent daemon + periodic I/O for hash scans.

**Chronicle integration:** JSON alerts via syslog. Chronicle has a Wazuh parser
(native or community). Cleanest integration of all alternatives. But creates two
FIM event streams (auditd + Wazuh) requiring deduplication decisions.

**Compliance:** Built-in mapping to all major frameworks with pre-tagged control IDs.
Strongest compliance story of all candidates.

---

### Tripwire OSS

**How it works:** Hash-based periodic scan, functionally similar to AIDE. Creates a
signed database of file hashes and metadata using a policy file. Compares on
subsequent runs.

**Strengths:**
- Name recognition with auditors (PCI-DSS 11.5 was practically written with
  Tripwire in mind)
- Signed database adds tamper resistance
- Conceptually simple

**Weaknesses:**
- Open-source version is effectively unmaintained / low development activity
- More complex setup than AIDE: requires site and local key generation
  (passphrase-protected), policy language is less intuitive
- No real-time detection, no attribution
- No central management in OSS version
- Text-based output, no native Chronicle parser
- Smaller community, fewer resources for troubleshooting
- Commercial version (Tripwire Enterprise by Fortra) is a different,
  expensive product

**Resource overhead:** Comparable to AIDE — periodic I/O burst.

**Chronicle integration:** Same challenges as AIDE. Custom wrapper/parser needed.

**Compliance:** Strong name recognition. But the OSS version lacks enterprise
reporting that auditors expect.

---

### Samhain

**How it works:** Hash-based with distinctive security features. Runs as a daemon
with configurable check intervals. Optional kernel module to hide its own process.
Client/server architecture: central `yule` log server collects reports. Database
can be stored remotely, hardening against local tampering. Supports PGP-signed
configs and databases.

**Strengths:**
- Tamper resistance: hidden process, remote database, signed config
  (strongest anti-evasion story)
- Client/server model provides central visibility without a full SIEM platform
- Daemon mode is more responsive than AIDE's cron approach
  (configurable interval, e.g. every 600s)
- Syslog output is more structured than AIDE's
- Good fit for high-threat environments where adversaries may target FIM tooling

**Weaknesses:**
- Smallest community of all candidates — fewer tutorials, harder to troubleshoot
- Kernel module may conflict with security tools that flag hidden processes
- Client/server model adds infrastructure (yule server)
- XML configuration is less ergonomic than AIDE's
- Still no real-time detection or attribution
- Another persistent daemon to manage and patch
- Not in all default distro repos

**Resource overhead:** Small daemon (10-30 MB RAM) + periodic I/O.

**Chronicle integration:** Structured syslog output is parseable but requires a
custom Chronicle parser. Better than AIDE, worse than Wazuh.

**Compliance:** Same coverage as AIDE/Tripwire. Tamper-resistance features align
with zero-trust models in newer NIST and SOC2 guidance.

---

## Summary Matrix

| Capability | AIDE | Wazuh | Tripwire OSS | Samhain |
|---|---|---|---|---|
| Hash-based verification | Yes | Yes | Yes | Yes |
| Real-time detection | No | Yes (inotify) | No | No (daemon polls) |
| Attribution | No | Partial | No | No |
| Deployment footprint | Minimal | Large | Minimal | Moderate |
| Additional infrastructure | None | Manager + indexer | None | Central server |
| Baseline management | Manual | Automatic | Manual | Automatic |
| Chronicle integration | Custom parser | JSON parser available | Custom parser | Custom parser |
| Central management | None | Yes | None (OSS) | Yes |
| Compliance dashboards | No | Built-in | No | No |
| Community / maintenance | Strong | Very strong | Weak | Small |
| Tamper resistance | Low | Moderate | Moderate (signed DB) | Strong |
| Resource overhead | Periodic burst | Continuous agent | Periodic burst | Small daemon |
| Operational burden | Moderate (baseline mgmt) | Low (once deployed) | Moderate | Low-moderate |

---

## Evaluation Against Our Environment

### Current stack
- **Endpoint management:** Tanium
- **Real-time FIM:** auditd (deployed via Tanium, forwarding to Chronicle)
- **SIEM:** Chronicle

### Decision criteria

| Criteria | Weight | AIDE | Wazuh | Tripwire OSS | Samhain |
|---|---|---|---|---|---|
| Fills auditd hash gap | Must have | Yes | Yes | Yes | Yes |
| Low deployment cost | High | Best | Poor | Good | Moderate |
| No new infrastructure | High | Yes | No (manager cluster) | Yes | No (yule server) |
| No Tanium overlap | High | N/A | Significant overlap | N/A | N/A |
| Chronicle integration effort | Medium | Moderate | Low | Moderate | Moderate |
| Baseline automation via Tanium | Medium | Feasible | N/A (built-in) | Feasible | Feasible |
| Community / long-term viability | Medium | Strong | Very strong | Weak | Small |
| Compliance strength | Medium | Good | Best | Name only | Good |
| Tamper resistance | Low-medium | Low | Moderate | Moderate | Best |

---

## Recommendation

### Primary: auditd + AIDE

**AIDE is the right complement to our existing auditd deployment.**

Rationale:
- Closes the hash-based verification gap with minimal deployment cost
- No new infrastructure — single binary, config file, and cron job per host
- Deployable and manageable entirely through Tanium (our existing platform)
- No agent overlap — AIDE runs only when called, unlike Wazuh's persistent daemon
- Operationally simple once baseline update automation is in place
- Satisfies compliance requirements that auditd alone cannot

The combination gives us:
- **auditd** → real-time, attributed change detection (who, when, how)
- **AIDE** → periodic, hash-based integrity verification (is the file correct?)

Together they cover each other's blind spots.

### When to reconsider

**Choose Wazuh instead if:**
- You are planning to replace Tanium or need a unified endpoint security platform
- You need built-in compliance dashboards for audit reporting
- You have budget and headcount for the infrastructure (manager cluster, indexer)
- Real-time hash-based detection (not just periodic) is a hard requirement

**Choose Samhain instead if:**
- Your threat model includes adversaries who would specifically target FIM tooling
  on compromised hosts (APT with post-exploitation FIM evasion)
- Tamper-resistant FIM is a compliance or contractual requirement
- You can accept the smaller community trade-off

**Skip Tripwire OSS entirely:**
- AIDE is strictly superior in every dimension. Tripwire OSS is less maintained,
  harder to configure, and offers no advantages. The name recognition is the only
  selling point, and the open-source version does not deliver enterprise features.

---

## Next Steps (if AIDE is approved)

1. Add AIDE integration to the roadmap as a new phase
2. Build `aide.conf` matching our auditd watch paths
3. Create Tanium packages: `aide-deploy`, `aide-baseline-update`, `aide-check`
4. Build Chronicle parser/wrapper for AIDE output
5. Automate post-patch baseline updates as a Tanium post-action
6. Test on the existing FIM Computer Group before fleet rollout
