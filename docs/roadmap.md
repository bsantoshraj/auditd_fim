# Auditd FIM Roadmap

Phased improvement plan for robustness, efficiency, and scale.

---

## Phase 1: Deployment Safety (implement before expanding to more nodes)

These address real risks when deploying to production fleets.

### 1.1 Test cleanup on exit
Tests leave artifacts on endpoints (`/tmp/auditd_suid_test`, `/tmp/auditd_exec_test`,
leftover test users from failed runs). Add `trap` cleanup to each test so endpoints
stay clean even on failure.

### 1.2 Log rotation config
Rules are deployed but not `auditd.conf` or log rotation settings. A node with
aggressive logging and no rotation will fill disk. Ship a tuned `auditd.conf`
alongside `prod.rules` with settings for `max_log_file`, `num_logs`,
`space_left_action`, `disk_full_action`.

### 1.3 Idempotent deployment
`deploy-fim.sh` doesn't check if rules are already loaded or if the version changed.
Add a version stamp (sha256 of `prod.rules`) to `/etc/auditd-fim-version`. Skip
reload if unchanged. At scale, reloading 10,000 nodes unnecessarily is wasteful and
can cause brief event gaps during rule reload.

### 1.4 Rollback action
Package a `rollback-fim.sh` that removes rules, reloads auditd, and clears the role
tag. Ready to deploy immediately if something goes wrong in production. Currently
only documented as manual steps in the RUNBOOK cleanup section.

### 1.5 Dry-run mode for deploy
`deploy-fim.sh --dry-run` that shows what it would do without making changes. Useful
for change management approval workflows and pre-deployment review.

---

## Phase 2: Monitoring & Observability (implement during/after bake period)

These give visibility into auditd health across the fleet.

### 2.1 Tanium health sensor
A lightweight always-on sensor (separate from sizing) that reports auditd status:
`enabled`, `lost` count, `backlog`, `backlog_limit`, active rule count, disk usage
of `/var/log/audit/`. Monitor fleet-wide in Tanium Interact, not just during sizing.

### 2.2 Alerting thresholds in sizing report
The noise flag is hardcoded at 1000 events/day. Make it configurable and add tiered
warnings:
- `>1000` events/day = INFO
- `>10000` events/day = WARNING — review for exclusions
- `>50000` events/day = CRITICAL — rule is too broad for this role

Output a recommended action for each tier.

### 2.3 Audit backlog tuning
Track backlog high-water-mark in the health sensor. The buffer is 8192 but busy nodes
can spike. If backlog consistently exceeds 50% of `backlog_limit`, recommend increasing
the buffer or adding exclusions.

---

## Phase 3: Scale & Multi-Role Support (implement before broad production rollout)

These support deploying to a diverse fleet with different node roles.

### 3.1 Per-role rule variants
The framework assumes one `prod.rules` for all roles. After sizing, some roles will
need trimmed rules (e.g. CI runners don't need `exec.priv_esc`, databases don't need
`fim.usrbin`). Support a `prod.rules.d/` directory with role-based overlays. Have
`deploy-fim.sh` pick the right variant based on the role parameter, falling back to
the base `prod.rules` if no variant exists.

### 3.2 Diff-based rule updates
When pushing rule updates to a fleet with `-e 2` lock active, a reboot is required.
Track this: if rules file changed, set a flag (`/etc/auditd-fim-reboot-pending`)
that the health sensor reports. Operations team can then schedule reboots in
maintenance windows rather than discovering stale rules.

### 3.3 Fleet-wide test dashboard
The aggregator handles sizing data. Build a similar aggregator for test results — a
single view of pass/fail/skip across all nodes by role. Enables spotting OS-specific
failures at a glance when deploying to a mixed fleet (Ubuntu/RHEL/CentOS/Amazon Linux).

---

## Phase 4: End-to-End Validation (implement after production deployment)

These validate the full pipeline from auditd to SIEM.

### 4.1 Chronicle/SIEM forwarding validation
Validate that events not only generate in auditd but actually reach Chronicle. Add a
test that writes a canary event with a unique key and timestamp, then provides the key
so the operator can search Chronicle to confirm end-to-end delivery. Helps catch
syslog forwarding, network, or parser issues.

### 4.2 Package integrity check
Before loading rules, verify the `prod.rules` file hash against a known-good value
shipped in the package. Prevents tampered or corrupted rules from being loaded.
Important for compliance and tamper-resistance posture.

---

## Phase 5: Quality of Life (implement as time permits)

These improve developer/operator experience but are not blocking.

### 5.1 Structured test output (TAP format)
Tests currently output freeform text. Switch to TAP format
(`ok 1 - description` / `not ok 2 - description`) for machine-parseable results.
Tanium sensor could then report pass/fail/skip counts as structured columns.

### 5.2 Test timing
Add elapsed time per test to the output. Slow tests on specific nodes may indicate
auditd performance issues or kernel contention.

### 5.3 Verbose deploy logging
Add `--verbose` flag to `deploy-fim.sh` that logs each step with timestamps, package
versions, OS details, kernel version, and existing rule state before changes. Useful
for post-incident forensics.

---

## Status Tracker

| Item | Phase | Status |
|---|---|---|
| 1.1 Test cleanup | 1 | Not started |
| 1.2 Log rotation config | 1 | Not started |
| 1.3 Idempotent deployment | 1 | Not started |
| 1.4 Rollback action | 1 | Not started |
| 1.5 Dry-run mode | 1 | Not started |
| 2.1 Health sensor | 2 | Not started |
| 2.2 Alerting thresholds | 2 | Not started |
| 2.3 Backlog tuning | 2 | Not started |
| 3.1 Per-role rule variants | 3 | Not started |
| 3.2 Diff-based rule updates | 3 | Not started |
| 3.3 Fleet test dashboard | 3 | Not started |
| 4.1 SIEM forwarding validation | 4 | Not started |
| 4.2 Package integrity check | 4 | Not started |
| 5.1 TAP format output | 5 | Not started |
| 5.2 Test timing | 5 | Not started |
| 5.3 Verbose deploy logging | 5 | Not started |
