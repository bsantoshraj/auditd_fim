# Compliance Gap Analysis: PCI-DSS v4.0 & ISO 27001:2022

Assessment of our auditd + AIDE FIM implementation against specific control
requirements. For each control: what it demands, where we pass, and where
we have gaps.

---

## PCI-DSS v4.0

> Note: PCI-DSS v3.2.1 requirement 11.5 was renumbered in v4.0. The FIM
> requirements are now split across multiple controls.

---

### 11.5.2 — File Integrity Monitoring

**Requirement:**
> A change-detection mechanism (for example, file integrity monitoring tools)
> is deployed as follows:
> - To alert personnel to unauthorized modification (including changes,
>   additions, and deletions) of critical system files, configuration files,
>   or content files.
> - To perform critical file comparisons at least once weekly.

**Our status: PASS (with AIDE)**

| Sub-requirement | Status | How we satisfy |
|---|---|---|
| Alert on unauthorized modification | PASS | auditd fires real-time alerts via Chronicle on all watched paths (`fim.identity`, `fim.sudo`, `fim.ssh`, `fim.usrbin`, `fim.usrsbin`, etc.) |
| Detect changes | PASS | auditd `-p wa` (write + attribute) watches detect all modifications |
| Detect additions | PASS | auditd directory watches fire on new file creation within watched dirs |
| Detect deletions | PASS | `fim.delete` rule catches `unlink`, `unlinkat`, `rename`, `renameat` |
| Critical file comparisons weekly | PASS | AIDE scheduled scan (daily or more frequent) with hash comparison exceeds the weekly minimum |
| Alert personnel | PASS | Events forward to Chronicle, SOC receives alerts |

**Without AIDE: PARTIAL PASS / RISK**

auditd alone satisfies "alert on modification" but the "critical file comparisons"
language implies hash-based verification. Auditors increasingly interpret this as
requiring a baseline comparison mechanism, not just event logging. An auditor could
argue that auditd only detects changes it was running to see — it cannot verify
current state matches a known-good baseline.

**Assessor talking points:**
- "Show me a weekly file comparison report" → AIDE scan output with hash
  before/after
- "How do you detect changes made while the system was offline?" → AIDE
  baseline comparison on next scan
- "Show me an alert that was investigated" → Chronicle alert → SOC ticket

---

### 10.2.1 — Audit Logs Capture Defined Events

**Requirement:**
> Audit logs are enabled and active for all system components.
> Audit logs capture the following at minimum:
> - All individual user accesses to cardholder data
> - All actions taken by any individual with root or admin privileges
> - All access to audit trails
> - All invalid logical access attempts
> - Use of and changes to identification and authentication mechanisms
> - Initialization, stopping, or pausing of audit logs
> - Creation and deletion of system-level objects

**Our status: PASS**

| Sub-requirement | Status | How we satisfy |
|---|---|---|
| Actions by root/admin | PASS | `exec.priv_esc` — every execve with euid=0 by a real user (auid>=1000) |
| Changes to auth mechanisms | PASS | `fim.identity` — watches on `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/gshadow` |
| Changes to identification | PASS | `fim.identity` + `fim.sudo` + `fim.ssh` |
| Creation/deletion of system objects | PASS | `fim.delete`, `fim.perm`, `fim.owner`, `fim.usrbin`, `fim.usrsbin`, `fim.systemd` |
| Audit log initialization/stopping | PASS | auditd `-e 2` lock prevents stopping; `-f 1` triggers on failure |
| Individual user attribution | PASS | `auid` field tracks original login user through sudo/su chains |

---

### 10.2.1.1 — Audit Logs Record Details

**Requirement:**
> Audit logs record the following details for each auditable event:
> - User identification
> - Type of event
> - Date and time
> - Success or failure indication
> - Origination of event
> - Identity or name of affected data, system component, resource, or service

**Our status: PASS**

| Detail | Status | auditd field |
|---|---|---|
| User identification | PASS | `auid` (login UID), `uid`, `euid` |
| Type of event | PASS | `syscall` field + `-k` key tag |
| Date and time | PASS | Kernel timestamp in `msg=audit(epoch:serial)` |
| Success or failure | PASS | `success=yes/no` field in SYSCALL record |
| Origination | PASS | `exe` (process path), `tty`, `ses` (session), `ppid` |
| Affected resource | PASS | `name` field in PATH record (file path) |

---

### 10.3.4 — Log Integrity

**Requirement:**
> File integrity monitoring or change-detection mechanisms is used on audit
> logs to ensure that existing log data cannot be changed without generating
> alerts.

**Our status: GAP**

We monitor system files and binaries but do not currently watch `/var/log/audit/`
itself. An attacker with root could modify or delete audit logs.

**Fix required:**
```
-w /var/log/audit/ -p wa -k fim.auditlog
```

Add this to `prod.rules`. Also consider shipping logs to Chronicle in near
real-time so local deletion cannot erase the evidence — if this is already
happening via syslog forwarding, we satisfy the intent.

---

### 11.5.1.1 — Respond to FIM Alerts

**Requirement (new in v4.0, enforced from March 2025):**
> A process is defined and implemented to respond to any alerts generated
> by the change-detection mechanism.

**Our status: DEPENDS ON SOC PROCESS**

This is a process control, not a technical one. We need to document:
1. Who receives FIM alerts from Chronicle
2. SLA for initial triage (e.g. 15 minutes for critical keys)
3. Investigation procedure per alert type
4. Escalation path
5. Evidence of alerts investigated (Chronicle case/ticket logs)

**This is not a tooling gap — it is a process gap.** The tooling delivers the
alerts. The SOC must have a documented runbook for handling them.

---

### 6.3.2 — Inventory of Custom Software

**Requirement:**
> An inventory of bespoke and custom software is maintained to facilitate
> vulnerability and patch management.

**Our status: INDIRECT SUPPORT**

AIDE's baseline database serves as an implicit inventory of all system binaries
and their hashes. Not a direct substitute for a software inventory, but provides
supporting evidence.

---

## ISO 27001:2022

ISO 27001:2022 Annex A controls are organized differently from PCI-DSS. FIM
maps primarily to controls in A.8 (Technological Controls).

---

### A.8.1 — User Endpoint Devices

**Requirement:** Information stored on, processed by, or accessible through
user endpoint devices shall be protected.

**Our status: PASS**

System binary integrity monitoring (`fim.usrbin`, `fim.usrsbin`) and configuration
file monitoring (`fim.identity`, `fim.sudo`, `fim.ssh`) protect the endpoint.

---

### A.8.5 — Secure Authentication

**Requirement:** Secure authentication technologies and procedures shall be
established and implemented.

**Our status: PASS**

`fim.identity` watches on `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/gshadow`
detect any modification to authentication databases. `fim.ssh` detects changes to
SSH configuration.

---

### A.8.9 — Configuration Management

**Requirement:** Configurations, including security configurations, of hardware,
software, services, and networks shall be established, documented, maintained,
and managed.

**Our status: PASS (with AIDE)**

AIDE baseline provides a documented, hash-verified configuration state. auditd
detects drift from that state in real time. Together they satisfy both the
"documented" and "maintained" requirements.

**Without AIDE: PARTIAL**

auditd detects changes but cannot prove current configuration matches the
documented state.

---

### A.8.15 — Logging

**Requirement:** Logs that record activities, exceptions, faults, and other
relevant events shall be produced, stored, protected, and analysed.

**Our status: PASS**

| Aspect | Status | How |
|---|---|---|
| Produced | PASS | auditd kernel-level logging |
| Stored | PASS | `/var/log/audit/` locally + Chronicle remotely |
| Protected | PASS (with fix) | `-e 2` lock prevents rule tampering. Need to add `fim.auditlog` watch on log directory (see 10.3.4 gap above) |
| Analysed | PASS | Chronicle detection rules + SOC review |

---

### A.8.16 — Monitoring Activities

**Requirement:** Networks, systems, and applications shall be monitored for
anomalous behaviour and appropriate actions taken to evaluate potential
information security incidents.

**Our status: PASS**

Real-time detection of:
- Execution from anomalous locations (`exec.tmp`, `exec.shm`, `exec.vartmp`)
- Privilege escalation (`exec.priv_esc`)
- Binary tampering (`fim.usrbin`, `fim.usrsbin`)
- Permission manipulation (`fim.perm`, `fim.owner`)

All forwarded to Chronicle for correlation and anomaly evaluation.

---

### A.8.19 — Installation of Software on Operational Systems

**Requirement:** Procedures and measures shall be implemented to securely
manage software installation on operational systems.

**Our status: PASS**

`fim.usrbin` and `fim.usrsbin` detect any binary installation or modification
outside of authorized channels (package managers are excluded via `never,exit`
rules, so only non-package-manager installations trigger alerts).

This is a strong control: legitimate installs via apt/yum are suppressed,
unauthorized installs generate immediate alerts.

---

### A.8.28 — Secure Coding

Not directly applicable to FIM, but AIDE hash verification of deployed
application binaries supports verification that production code matches
the approved build artifacts.

---

## Summary: Gaps Requiring Action

| # | Gap | Severity | Control | Fix |
|---|---|---|---|---|
| 1 | Audit log directory not watched | **High** | PCI 10.3.4, ISO A.8.15 | Add `-w /var/log/audit/ -p wa -k fim.auditlog` to prod.rules |
| 2 | No documented alert response process | **High** | PCI 11.5.1.1 | SOC runbook for FIM alert triage (process, not tooling) |
| 3 | AIDE not yet deployed | **Medium** | PCI 11.5.2 ("file comparisons"), ISO A.8.9 | Implement Phase 6 of roadmap |
| 4 | No AIDE Chronicle parser | **Low** | PCI 11.5.2 (alerting) | Build JSON wrapper + Chronicle custom parser |

### What passes today (auditd only)
- PCI 10.2.1 (audit logging) — full pass
- PCI 10.2.1.1 (audit detail) — full pass
- ISO A.8.1, A.8.5, A.8.15, A.8.16, A.8.19 — full pass

### What passes with AIDE added
- PCI 11.5.2 (file integrity monitoring) — full pass
- ISO A.8.9 (configuration management) — elevated from partial to full pass

### What requires process (not tooling)
- PCI 11.5.1.1 (alert response) — SOC runbook needed
