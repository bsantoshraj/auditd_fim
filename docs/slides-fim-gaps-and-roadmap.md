# FIM: Gaps, Compliance Risk & Path Forward

Slide content for executive/stakeholder presentation.

---

## Slide 1: Title

**File Integrity Monitoring — Where We Are and What's Missing**

Current state: auditd-based FIM deployed via Tanium, forwarding to Chronicle

This deck covers:
- What auditd gives us today
- What it cannot do alone
- Compliance gaps (PCI-DSS v4.0, ISO 27001:2022, NIST 800-53)
- Recommendation and path forward

---

## Slide 2: What We Have Today

**auditd — kernel-level, real-time file change detection**

- Real-time alerts when critical files are modified, created, or deleted
- Full attribution: who (login user), what process, when, how (syscall)
- Covers: identity files, sudo/SSH config, system binaries, cron, systemd,
  boot/kernel, audit logs, permission/ownership changes, execution from
  suspicious locations, privilege escalation
- Low noise: scoped to real users (auid>=1000), package managers excluded
- Deployed via Tanium, forwarded to Chronicle, tamper-protected (-e 2 lock)

**This is strong. Most organizations don't have this level of FIM.**

---

## Slide 3: What auditd Cannot Do

| Capability | auditd | Needed? |
|---|---|---|
| Real-time change detection | Yes | — |
| Who changed the file (attribution) | Yes | — |
| Verify file matches known-good state | **No** | Yes |
| Detect offline/boot-time tampering | **No** | Yes |
| Detect changes made before auditd started | **No** | Yes |
| Prove current integrity (not just "no event seen") | **No** | Yes |
| Detect silent data corruption | **No** | Yes |

**The core gap: auditd sees changes happen but cannot verify current state.**

Absence of an auditd event does not prove a file is intact.

---

## Slide 4: Why This Gap Matters — Real Scenarios

**Scenario 1: Trojanized binary**
- Attacker replaces `/usr/sbin/sshd` via rescue mode boot
- auditd was not running — zero visibility
- Trojanized sshd captures credentials for weeks
- Without hash verification, we never know

**Scenario 2: Supply chain compromise**
- Compromised package update delivers malicious binary
- auditd sees the write but our noise exclusions suppress apt/dpkg events
  (by design — otherwise every patch floods alerts)
- No hash baseline means we cannot verify the update is legitimate

**Scenario 3: Post-incident verification**
- After a breach, IR team asks: "Are all binaries clean?"
- auditd can say "I didn't see anyone modify them"
- Cannot say "they are definitely unmodified" — only a hash check can

---

## Slide 5: Compliance Gaps — PCI-DSS v4.0

| Control | Requirement | auditd Only | auditd + AIDE |
|---|---|---|---|
| **11.5.2** | File integrity monitoring with critical file comparisons at least weekly | **Partial** — no hash comparison capability | **Full pass** |
| **10.3.4** | Integrity monitoring on audit logs themselves | **Fixed** — fim.auditlog watch added | **Pass** |
| **11.5.1.1** | Documented process to respond to FIM alerts (new in v4.0, enforced) | **Process gap** — needs SOC runbook | Same — process gap |
| **10.2.1** | Audit logs capture defined events | **Pass** | Pass |
| **10.2.1.1** | Audit logs record required details | **Pass** | Pass |

**Key risk:** An assessor can argue that auditd's event-based monitoring does
not satisfy the "critical file comparisons" language in 11.5.2. Hash-based
verification is the industry-accepted interpretation.

---

## Slide 6: Compliance Gaps — ISO 27001:2022

| Control | Requirement | auditd Only | auditd + AIDE |
|---|---|---|---|
| **A.8.9** | Configuration management — configs documented, maintained, managed | **Partial** — detects drift but cannot prove current state matches baseline | **Full pass** — AIDE baseline is the documented state |
| **A.8.15** | Logs produced, stored, protected, analysed | **Pass** (with fim.auditlog fix) | Pass |
| **A.8.16** | Monitoring for anomalous behaviour | **Pass** | Pass |
| **A.8.19** | Secure software installation on operational systems | **Pass** | Pass |

**Key risk:** A.8.9 requires demonstrable proof that configurations are in their
intended state. auditd can show change events but not current-state verification.
AIDE's hash baseline closes this.

---

## Slide 7: Compliance Gaps — NIST 800-53

| Control | Requirement | auditd Only | auditd + AIDE |
|---|---|---|---|
| **SI-7** | Software, firmware, and information integrity — detect unauthorized changes using integrity verification tools | **Fail** — no integrity verification mechanism | **Pass** — AIDE provides hash-based verification |
| **SI-7(1)** | Integrity checks at startup, transitional states, or fixed intervals | **Fail** — auditd only runs while the system is up | **Pass** — AIDE runs on schedule, catches offline changes |
| **SI-7(7)** | Detect unauthorized changes and take action | **Partial** — detects runtime changes but not offline | **Pass** |
| **AU-2** | Audit events defined and logged | **Pass** | Pass |
| **AU-3** | Audit record content (who, what, when, where, outcome) | **Pass** | Pass |
| **AU-9** | Protection of audit information | **Pass** (with fim.auditlog) | Pass |

**Key risk:** SI-7 explicitly calls for "integrity verification tools." auditd is
a change-detection tool, not an integrity verification tool. This is a clear
control failure without a hash-based complement.

---

## Slide 8: Gap Summary

| Gap | Affected Controls | Severity | Fix |
|---|---|---|---|
| No hash-based file verification | PCI 11.5.2, ISO A.8.9, NIST SI-7, SI-7(1) | **High** | Deploy AIDE alongside auditd |
| No documented FIM alert response process | PCI 11.5.1.1 | **High** | SOC runbook (process, not tooling) |
| No offline/boot-time tampering detection | NIST SI-7(1) | **Medium** | AIDE scheduled scans |
| No AIDE-to-Chronicle parser | PCI 11.5.2 (alerting requirement) | **Low** | JSON wrapper + custom Chronicle parser |

**Bottom line:** 3 out of 4 gaps are closed by adding AIDE. The 4th is a SOC process.

---

## Slide 9: Why AIDE (Not Alternatives)

| Criteria | AIDE | Wazuh | Tripwire OSS | Samhain |
|---|---|---|---|---|
| Fills the hash gap | Yes | Yes | Yes | Yes |
| New infrastructure needed | **None** | Manager cluster + indexer | None | Central server |
| New agents on endpoints | **None** (cron job) | Persistent daemon | None (cron) | Persistent daemon |
| Overlap with Tanium | **None** | Significant | None | Minimal |
| License cost | **$0** | $0 (but infra cost) | $0 | $0 |
| Community / maintenance | **Strong** | Very strong | Weak | Small |
| Deployment via Tanium | **Simple** | Complex | Simple | Moderate |

**AIDE wins because it closes the gap with zero new infrastructure, zero new
agents, and zero license cost — entirely manageable through Tanium.**

---

## Slide 10: What auditd + AIDE Gives Us Together

| Layer | Tool | Detection Model | Strength |
|---|---|---|---|
| Real-time change detection | auditd | Syscall interception | Who, when, how — instant alert |
| Integrity verification | AIDE | Hash comparison vs baseline | Is the file correct — definitive proof |

**They cover each other's blind spots:**

- auditd is blind to offline tampering → AIDE catches it on next scan
- AIDE is blind between scans → auditd catches changes in real time
- auditd cannot prove integrity → AIDE's hash baseline proves it
- AIDE cannot attribute changes → auditd provides full user/process chain

**Together: no gaps in detection or verification.**

---

## Slide 11: Deployment Plan

| Step | Action | Effort | Owner |
|---|---|---|---|
| 1 | Create Tanium package for AIDE deployment | 1 day | Security Engineering |
| 2 | Build `aide.conf` aligned to auditd watch paths | 1 day | Security Engineering |
| 3 | Deploy to test Computer Group, initialize baseline | 1 day | Security Engineering |
| 4 | Build Chronicle JSON wrapper + parser for AIDE output | 2-3 days | SIEM Engineering |
| 5 | Automate post-patch baseline updates via Tanium | 1 day | Security Engineering |
| 6 | SOC runbook for FIM alert triage (PCI 11.5.1.1) | 2 days | SOC |
| 7 | Fleet rollout via Tanium Computer Groups | 1 day | Security Engineering |
| 8 | Validate with compliance/audit team | 1 day | GRC |

**Total estimated effort: 10-12 working days**

---

## Slide 12: Cost Impact

| Item | Cost |
|---|---|
| AIDE license | $0 (GPL open source) |
| New servers / infrastructure | $0 (runs on existing endpoints) |
| New agents | $0 (AIDE is a cron job, not a daemon) |
| Tanium — already licensed | $0 incremental |
| Chronicle — already licensed | $0 incremental |
| Engineering effort | ~10-12 days one-time |
| Ongoing operational cost | Minimal — baseline updates post-patch (automatable) |

**Compare to alternatives:**
- Wazuh: 2-4 new servers, ongoing infra maintenance, agent management
- Tripwire Enterprise: per-node licensing ($$$$)
- CrowdStrike FIM: per-endpoint add-on license

---

## Slide 13: Risk of Doing Nothing

| Risk | Likelihood | Impact |
|---|---|---|
| PCI 11.5.2 assessment finding (no hash comparison) | **High** — assessor interpretation trending toward requiring hash-based FIM | Remediation timeline imposed, potential fine |
| NIST SI-7 control failure on audit | **High** — control explicitly requires "integrity verification tools" | Audit finding, risk acceptance required from CISO |
| ISO A.8.9 partial compliance | **Medium** — depends on assessor depth | Observation or minor nonconformity |
| Undetected offline binary tampering | **Low probability, catastrophic impact** — rescue mode attack, supply chain compromise | Extended breach, no forensic evidence of initial compromise |
| Post-incident inability to verify system integrity | **Medium** — happens on every incident | Extended IR timeline, potential re-image of entire fleet "just in case" |

---

## Slide 14: Recommendation

**Deploy AIDE alongside our existing auditd FIM within the next quarter.**

- Closes all identified compliance gaps (PCI, ISO, NIST)
- Zero infrastructure cost, zero license cost
- Deployable through our existing Tanium pipeline
- ~10-12 days of engineering effort
- Transforms our FIM from "change detection" to "change detection + integrity verification"
- Provides defensible evidence for auditors: real-time attributed alerts AND
  hash-based proof of file integrity

**Parallel action:** Document the SOC FIM alert response process (PCI 11.5.1.1).
This is a process gap, not a tooling gap, and should be addressed regardless of
the AIDE decision.

---

## Slide 15: Next Steps

1. **Approve** AIDE deployment as Phase 6 of the FIM roadmap
2. **Assign** Security Engineering to build AIDE Tanium packages and aide.conf
3. **Assign** SIEM Engineering to build Chronicle parser for AIDE output
4. **Assign** SOC to draft FIM alert response runbook
5. **Schedule** test deployment on existing FIM Computer Group
6. **Target:** Fleet rollout within 30 days of approval
