# File Integrity Monitoring — Use Case & Justification

## The Problem with Compliance-Only FIM

Most FIM deployments in the industry are checkbox exercises. Organizations deploy
Tripwire or a commercial FIM agent, configure it to watch `/etc/passwd` and a few
critical files, generate a monthly report, hand it to the auditor, and call it done.

This approach satisfies PCI-DSS 11.5 on paper but provides **zero security value**:

- Reports are reviewed days or weeks after the fact
- No one investigates the alerts because they are drowned in false positives
  from legitimate patching and config management
- There is no attribution — the report says "file changed" but not who, how, or why
- There is no real-time detection — an attacker can compromise a system, exfiltrate
  data, and clean up before the next weekly scan
- The tool becomes shelfware that costs money and headcount to maintain but catches
  nothing

**Our approach is different.** We combine real-time syscall-level detection (auditd)
with hash-based integrity verification (AIDE), tuned for low noise and high signal,
deployed and managed through existing infrastructure (Tanium), and forwarded to a
modern SIEM (Chronicle) for correlation and alerting.

---

## Why FIM is Indispensable (Not Optional)

### 1. It is the last line of defense against persistent compromise

Once an attacker gains access to a Linux host, their immediate objectives are:

| Objective | How they do it | What FIM catches |
|---|---|---|
| Maintain access | Add SSH key to `authorized_keys`, create backdoor user, install cron reverse shell | `fim.identity`, `fim.ssh`, `fim.cron` — real-time alert |
| Escalate privileges | Drop SUID binary in `/tmp`, modify `/etc/sudoers` | `fim.perm`, `fim.sudo` — real-time alert |
| Replace binaries | Trojanize `sshd`, `sudo`, `cron` to capture credentials | `fim.usrbin`, `fim.usrsbin` — real-time alert + AIDE hash mismatch |
| Persist through reboot | Install malicious systemd service, modify init scripts | `fim.systemd`, `fim.boot` — real-time alert |
| Cover tracks | Delete logs, rename/unlink evidence files | `fim.delete` — real-time alert |
| Stage tools | Download exploit kit to `/tmp` or `/dev/shm`, execute it | `exec.tmp`, `exec.shm` — real-time alert |

Every one of these techniques modifies files. FIM is the control that catches them.
EDR tools may detect the behavior, but FIM provides an independent, kernel-level
evidence stream that is harder to evade and simpler to reason about.

### 2. It detects what other controls miss

| Scenario | Firewall | IDS/IPS | EDR | Antivirus | FIM |
|---|---|---|---|---|---|
| Insider adds backdoor user | — | — | Maybe | — | **Yes** |
| Attacker replaces `/usr/bin/sudo` with trojanized version | — | — | Maybe | Maybe (if signature exists) | **Yes** |
| Supply chain compromise delivers malicious package update | — | — | — | Maybe | **Yes** (AIDE hash mismatch) |
| Admin accidentally changes `/etc/sudoers` syntax, breaks sudo | — | — | — | — | **Yes** |
| Rescue mode boot, attacker modifies `/etc/shadow` | — | — | — | — | **Yes** (AIDE on next boot) |
| Ransomware encrypts files in `/etc` | — | Maybe | Maybe | Maybe | **Yes** |

FIM is the only control that reliably detects **all file-level persistence and
tampering**, regardless of the attack vector.

### 3. It provides attribution that no other FIM tool gives

Most FIM products tell you *what* changed. Our auditd-based approach tells you:

- **Who**: the original login user (auid survives sudo/su chains)
- **What process**: the executable that made the change (exe field)
- **How**: the exact syscall (write, rename, unlink, chmod, chown)
- **When**: kernel-level timestamp, not scan-interval approximation
- **From where**: terminal (tty), session ID, parent process chain

This transforms FIM from a "something changed" alert into actionable incident
response data. When the SOC receives a `fim.identity` alert, they immediately know
which user, from which SSH session, using which tool modified `/etc/passwd`. No
forensic investigation needed to establish basic facts.

### 4. It is required for compliance — but done right, it earns its keep

| Framework | Control | What they require | How we satisfy it |
|---|---|---|---|
| **PCI-DSS 11.5** | File integrity monitoring | Alert on unauthorized modification of critical files | auditd real-time alerts + AIDE hash verification |
| **PCI-DSS 10.2** | Audit logging | Log all access to system components | auditd syscall logging with full attribution |
| **HIPAA 164.312(b)** | Audit controls | Monitor access/changes to ePHI systems | auditd watches on config + identity files |
| **HIPAA 164.312(c)(1)** | Integrity controls | Protect ePHI from improper alteration | AIDE hash verification of system binaries |
| **CIS Benchmark** | 4.1.x (Audit), 1.3.x (FIM) | Configure auditing, ensure filesystem integrity | auditd rules aligned to CIS controls |
| **SOC2 CC6.1** | Logical access controls | Monitor changes to infrastructure | auditd + AIDE covers config and binary changes |
| **SOC2 CC7.1** | System monitoring | Detect anomalies and events | Real-time auditd alerts forwarded to Chronicle |
| **NIST 800-53 SI-7** | Software/information integrity | Detect unauthorized changes | AIDE hash baseline + auditd real-time monitoring |
| **NIST 800-53 AU-2** | Audit events | Audit security-relevant events | auditd syscall-level audit trail |

The difference between our approach and a checkbox deployment: **we satisfy the
control AND get security value from it**. The same data that passes the audit is the
data the SOC uses for detection and response.

---

## Why This Architecture (auditd + AIDE + Tanium + Chronicle)

### Design principles

1. **No new agents** — auditd is built into the kernel, AIDE is a single binary
   invoked by cron. No persistent daemons, no agent sprawl.

2. **No new infrastructure** — Tanium (already deployed) handles package deployment,
   configuration, and orchestration. Chronicle (already deployed) handles log
   aggregation and alerting. Nothing new to build, staff, or maintain.

3. **Low noise by design** — auditd rules are scoped with `auid>=1000` filters and
   `never,exit` exclusions for package managers, config management, and container
   runtimes. AIDE baselines are updated post-patch to eliminate false positives.
   Every alert is worth investigating.

4. **Defense in depth** — auditd catches changes in real-time but is blind to
   offline tampering. AIDE catches offline tampering but is blind between scans.
   Together, there are no gaps.

5. **Attribution by default** — every event includes the original login user, the
   process, the syscall, and the timestamp. This is not an add-on or premium
   feature — it is how Linux audit works at the kernel level.

### Cost analysis

| Component | License cost | Infrastructure cost | Operational cost |
|---|---|---|---|
| auditd | Free (kernel built-in) | None | Rule maintenance, noise tuning |
| AIDE | Free (GPL) | None | Baseline updates post-patch |
| Tanium | Already licensed | Already deployed | Package creation (one-time) |
| Chronicle | Already licensed | Already deployed | Parser/detection rules |
| **Total incremental cost** | **$0** | **$0** | **Low** |

Compare this to deploying Wazuh (manager cluster + indexer + agents), Tripwire
Enterprise (per-node license), or CrowdStrike FIM module (per-endpoint license).
The auditd+AIDE approach delivers equivalent or better detection capability at
a fraction of the cost.

---

## Real-World Attack Scenarios

### Scenario 1: Compromised SSH key + backdoor user

**Attack:** Attacker gains access via stolen SSH key. Creates backdoor user
`svc_backup` with UID 0. Adds their SSH public key to the new user's
`authorized_keys`.

**Detection timeline (our approach):**
- T+0s: `fim.identity` fires — `/etc/passwd` modified (auditd, real-time)
- T+0s: `fim.identity` fires — `/etc/shadow` modified (auditd, real-time)
- T+0s: SOC alert in Chronicle with full attribution: user `jdoe`, session 4,
  from IP `10.2.3.4`, executed `/usr/sbin/useradd`
- T+6h: AIDE scan confirms `/etc/passwd` and `/etc/shadow` hash mismatch

**Detection timeline (compliance-only FIM):**
- T+24h: Daily scan detects `/etc/passwd` changed. Report says "file modified."
  No attribution. Alert lost in noise from legitimate changes. No one investigates
  until the weekly report review.

### Scenario 2: Supply chain — trojanized binary in package update

**Attack:** Compromised upstream repo pushes a trojanized `openssh-server` package.
The `sshd` binary is replaced with a version that logs credentials to `/tmp/.cache`.

**Detection timeline (our approach):**
- T+0s: `fim.usrsbin` fires — `/usr/sbin/sshd` modified (auditd, real-time)
- T+0s: However, the noise exclusion for `apt`/`dpkg` suppresses this during
  normal patching — **this is by design**
- T+0s: Post-patch AIDE baseline update detects the hash does not match the
  expected value from the vendor — **AIDE catches what auditd excluded**
- Alternatively: if the attacker replaced the binary outside of apt/dpkg
  (e.g. direct `cp`), auditd fires immediately with full process attribution

**Detection timeline (compliance-only FIM):**
- T+24h: Daily scan reports "sshd changed." Since every patch cycle changes
  binaries, this alert is indistinguishable from legitimate updates. Ignored.

### Scenario 3: Insider privilege escalation

**Attack:** Developer with legitimate access drops a SUID binary in `/tmp` to
escalate from their user account to root.

**Detection timeline (our approach):**
- T+0s: `fim.perm` fires — `chmod` with SUID bit detected (auditd, real-time)
- T+0s: `exec.tmp` fires — execution from `/tmp` detected (auditd, real-time)
- T+0s: `exec.priv_esc` fires — process running as root with non-root auid
  (auditd, real-time)
- T+0s: SOC receives correlated alert chain in Chronicle: user `devuser`
  copied bash to `/tmp`, set SUID, executed it, now running as root

**Detection timeline (compliance-only FIM):**
- Never detected. `/tmp` is not typically monitored by compliance FIM.
  The binary is deleted after use. No scan ever sees it.

---

## What Happens Without FIM

Organizations that skip FIM or deploy it as checkbox-only face these outcomes:

1. **Extended dwell time** — without real-time file change detection, attackers
   persist for weeks or months. Industry average dwell time is 16 days (Mandiant
   M-Trends 2025). Real-time FIM can reduce this to seconds.

2. **No forensic trail** — after a breach, the first question is "what did they
   change?" Without auditd's attributed logging, the answer requires expensive
   disk forensics that may be inconclusive if the attacker cleaned up.

3. **Compliance failure under scrutiny** — checkbox FIM passes a routine audit
   but fails when an assessor digs deeper: "Show me an alert that was
   investigated. Show me your mean time to detect. Show me attribution." A
   compliance-only deployment cannot answer these questions.

4. **Blind to the most common persistence techniques** — MITRE ATT&CK
   techniques T1098 (Account Manipulation), T1053 (Scheduled Task), T1543
   (Create/Modify System Process), T1548 (Abuse Elevation Control Mechanism)
   all involve file modifications that FIM directly detects.

---

## Summary

FIM is not a compliance checkbox. It is a core detection control that catches
file-level persistence, privilege escalation, binary tampering, and unauthorized
configuration changes — the techniques that every attacker uses and that most
other controls miss.

Our implementation (auditd + AIDE, deployed via Tanium, forwarded to Chronicle)
delivers real security value at zero incremental license and infrastructure cost,
using tools already in our stack. It satisfies every major compliance framework
not because we designed it for compliance, but because compliance frameworks
describe what good security looks like — and this is good security.
