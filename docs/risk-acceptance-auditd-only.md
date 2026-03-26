# Risk Acceptance Record: auditd-Only FIM

## Date
2026-03-23

## Decision
Directive received to proceed with auditd-only FIM without deploying a
hash-based integrity verification tool (AIDE or equivalent).

## Recommendation Made
Security Engineering recommended deploying AIDE alongside auditd to close
the hash-based verification gap. This recommendation was documented in:
- `docs/fim-comparative-analysis.md` — comparative analysis of FIM tools
- `docs/compliance-gap-analysis.md` — control-by-control gap assessment
- `docs/fim-use-case.md` — security justification and attack scenarios
- `docs/slides-fim-gaps-and-roadmap.md` — executive presentation materials

## Residual Risk Accepted

The following risks remain open under an auditd-only deployment:

### 1. Compliance Risk — PCI-DSS v4.0

**Control 11.5.2** requires "a change-detection mechanism" that performs
"critical file comparisons at least once weekly."

- auditd detects changes in real time but does not perform file comparisons
  (hash-based verification against a known-good baseline)
- Industry interpretation is trending toward requiring hash-based FIM to
  satisfy this control
- An assessor may issue a finding that auditd alone does not meet the
  "file comparisons" requirement
- **Risk level: High** — potential assessment finding, remediation timeline,
  or compensating control requirement

**Control 11.5.1.1** (enforced since March 2025) requires a documented
process to respond to FIM alerts. This is a process gap independent of tooling.

### 2. Compliance Risk — NIST 800-53

**Control SI-7 (Software, Firmware, and Information Integrity)** explicitly
requires "integrity verification tools" to "detect unauthorized changes to
software, firmware, and information."

- auditd is a change-detection tool, not an integrity verification tool
- It cannot verify that a file's current content matches a known-good state
- **This is a clear control failure** — not an interpretation question
- **Risk level: High** — audit finding if NIST 800-53 is in scope

**Control SI-7(1)** requires integrity checks "at startup, at transitional
states, or at defined intervals." auditd only runs while the system is up
and cannot verify state at boot time.

### 3. Compliance Risk — ISO 27001:2022

**Control A.8.9 (Configuration Management)** requires configurations to be
"documented, maintained, and managed."

- auditd detects drift but cannot prove current state matches documented
  baseline
- An assessor may accept auditd as partial evidence but flag the lack of
  state verification
- **Risk level: Medium** — depends on assessor interpretation

### 4. Security Risk — Blind Spots

| Scenario | Detection capability |
|---|---|
| File modified while auditd was not running (reboot, crash, rescue mode) | **None** |
| File modified via direct disk write / debugfs | **None** |
| File modified before auditd rules were loaded | **None** |
| Binary replaced via boot media or physical access | **None** |
| Supply chain compromise via package manager (excluded by noise rules) | **None** — by design, apt/dpkg/yum are excluded |
| Post-incident verification ("are all binaries clean?") | **Cannot verify** — can only confirm no monitored event was seen |
| Silent data corruption / bit-rot | **None** |

These scenarios are low-probability individually but have catastrophic impact.
Hash-based verification (AIDE) detects all of them.

### 5. Incident Response Risk

Without hash-based verification, the IR team cannot definitively confirm
system integrity after a breach. The only option is to re-image affected
systems, which:
- Extends incident recovery time
- Increases cost (downtime, engineering hours)
- May be unnecessary if integrity could be verified via hash comparison

## Impact of This Decision

If a compliance assessment or security incident later reveals that auditd-only
FIM was insufficient, the following will be needed:

1. Emergency deployment of AIDE or equivalent (estimated 10-12 engineering days)
2. Retroactive baseline creation (cannot verify integrity for the gap period)
3. Potential compensating controls negotiation with assessors
4. Possible assessment findings, remediation timelines, or fines

## Record

This risk was identified and escalated by Security Engineering on 2026-03-23.
The recommendation to deploy AIDE was declined. This document serves as the
risk acceptance record.

**Risk accepted by:** [Name / Title — to be filled]

**Date accepted:** [Date — to be filled]

**Review date:** [Recommended: reassess in 90 days or at next audit cycle]
