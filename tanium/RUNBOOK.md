# Tanium FIM Sizing Runbook

Step-by-step guide to deploy auditd FIM rules to test machines via Tanium, collect sizing data, and produce volume estimates.

---

## Prerequisites

- Tanium console access with Package, Sensor, and Action permissions
- Target endpoints in a **Computer Group** (e.g. `FIM-Sizing-Test`)
- Target endpoints running Linux with Tanium Client installed

---

## Step 1: Create the Tanium Package

1. **Tanium Console** → Administration → Packages → Create Package
2. Package settings:
   - **Name:** `auditd-fim-deploy`
   - **Display Name:** `Auditd FIM Deploy (Sizing)`
   - **Command:** `bash deploy-fim.sh $1`
   - **Parameter 1:** `role` (string) — e.g. `webserver`, `database`, `bastion`, `cirunner`, `containerhost`
   - **Process group:** `fim-deploy`
   - **Expire after:** 1 hour
3. Upload these files to the package:
   - `deploy-fim.sh`
   - `prod.rules` (from repo root `../prod.rules`)
   - `sizing-sensor.sh`
4. Save the package.

---

## Step 2: Create Computer Groups by Role

For each node role, create a Computer Group or use an existing one:

| Computer Group       | Example filter                                    |
|----------------------|---------------------------------------------------|
| FIM-Test-Webservers  | `Computer Name contains web-test`                 |
| FIM-Test-Databases   | `Computer Name contains db-test`                  |
| FIM-Test-Bastions    | `Computer Name contains bastion-test`             |

If using a single test machine, create one group (e.g. `FIM-Sizing-Test`).

---

## Step 3: Deploy Rules via Action

Run one Action per role so nodes get tagged correctly:

1. **Tanium Console** → Actions → Deploy Action
2. **Package:** `auditd-fim-deploy`
3. **Parameter `role`:** set to the node's role (e.g. `webserver`)
4. **Target:** the appropriate Computer Group
5. **Schedule:** Run once (immediate)
6. Verify:
   - Action status shows "Completed" on all targets
   - Ask the question: `Get Tanium Action Log from all machines with...`
   - Look for `[auditd-fim] Deployment complete` in results

**Repeat for each role** with the correct role parameter.

---

## Step 3b: Validate Rules via Test Suite

Run the test suite on deployed endpoints to confirm all rules are firing correctly.

1. **Create package** `auditd-fim-tests`:
   - **Name:** `auditd-fim-tests`
   - **Command:** `bash run-tests.sh`
   - **Expire after:** 10 minutes
   - Upload these files:
     - `run-tests.sh`
     - `testsuite.tar.gz` (bundled test suite — rebuild with `tar czf tanium/testsuite.tar.gz testsuite/`)

2. **Deploy Action:**
   - **Package:** `auditd-fim-tests`
   - **Target:** your FIM Computer Group
   - **Schedule:** Run once

3. **Verify results:**
   - Action status should show Exit Code **0** on all targets
   - Check action logs for `[auditd-fim-test] ALL TESTS PASSED`
   - If any tests fail, review the action log for `[FAIL]` lines — the test name indicates which rule key is not firing

4. **Troubleshooting failures:**

   | Test | Expected in Tanium | Likely cause if unexpected |
   |---|---|---|
   | `01_fim_tmp` (fim.delete) | PASS | Rules not loaded or `never,exit` excluding the test user |
   | `02_suid` (fim.perm) | **SKIP** (no login session) | Will show `[SKIP]` — auid is unset in Tanium service context, rule requires auid>=1000. This is expected. |
   | `03_exec_tmp` (exec.tmp) | PASS | execve rule not loaded for /tmp |
   | `04_priv_esc` (exec.priv_esc) | **SKIP** (no login session) | Will show `[SKIP]` — same auid issue as 02. Validates only from interactive SSH sessions. |
   | `05_identity` (fim.identity) | PASS | /etc/passwd watch not loaded. Uses `wheel` on RHEL, `sudo` on Debian. |
   | `06_bin_tamper` (fim.usrbin) | PASS | /usr/bin watch not loaded |
   | `07_sbin_tamper` (fim.usrsbin) | PASS | /usr/sbin watch not loaded |

   > **Note:** Tests 02 and 04 rely on `auid` (audit login UID) which is only set during
   > interactive SSH/console login. Tanium actions run as a root service with no PAM session,
   > so `auid` remains unset (4294967295). These tests skip automatically in that context.
   > To fully validate these rules, run the test suite interactively via SSH: `sudo bash testsuite/run_all.sh`

5. **OS variance issues caught by the test suite:**

   The test suite doubles as a smoke test for cross-platform compatibility. When deploying
   across a mixed fleet, run tests on **at least one node per OS/distro** to catch issues like:

   | OS variance | Symptom | Fix applied |
   |---|---|---|
   | `/bin` → `/usr/bin` symlink (Ubuntu 20.04+, Fedora 33+) | Watch on `/bin` fires under `fim.usrbin` key instead of `fim.bin` | Removed redundant `/bin`, `/sbin` watches |
   | `sudo` group missing (RHEL/CentOS) | `usermod -aG sudo` fails | Test auto-detects `wheel` vs `sudo` |
   | `auditd` not installed | deploy-fim.sh fails | Script auto-installs via apt/yum/dnf |
   | SELinux context differences | Rules may behave differently | Check `subj_type` in noise exclusions |
   | Older kernels (< 3.x) | Some syscall filters unsupported | Verify `auditctl -l` shows all rules loaded |
   | Missing `/etc/audit/rules.d/` | Rule deployment fails | deploy-fim.sh creates the directory |

   If a test fails on a specific OS but passes on others, investigate before proceeding
   to the bake period. Fix the rule or test, rebuild `testsuite.tar.gz`, and re-run.

---

## Step 4: Wait for Bake Period

Once the test suite confirms all rules are firing (Exit Code 0, `ALL TESTS PASSED`),
leave the rules active and let the endpoints generate real-world audit data.

**Required bake time: 24-48 hours**

- The goal is to capture a representative sample of normal operations so the sizing
  data reflects actual production workloads, not just test events
- Do NOT proceed to Step 5 until the bake period has elapsed

**Guidelines:**

- Do NOT start the bake during a maintenance/patching window (unless you specifically
  want to measure patch noise — this is useful but should be a separate measurement)
- Ideally cover a full business day cycle (user logins, cron jobs, deployments, backups)
- If the environment has weekly batch jobs or scheduled tasks, consider extending to 72h
  to capture those patterns
- Monitor `auditctl -s` on a sample node during the bake to ensure no events are being
  dropped (`lost` counter should stay at 0; if it climbs, increase `-b` buffer size)

**What to watch for during the bake:**

| Indicator | How to check | Action if abnormal |
|---|---|---|
| Event drops | `auditctl -s` → `lost` field | Increase `-b` buffer in prod.rules |
| Disk usage | `du -sh /var/log/audit/` | If growing fast, identify noisy key early |
| Backlog | `auditctl -s` → `backlog` field | Should stay well below `backlog_limit` (8192) |
| auditd health | `systemctl status auditd` | Should be active (running) throughout |

**Quick health check via Tanium** (optional, run during bake):

Ask the question:
```
Get Online from all machines in <FIM Computer Group>
```
Then verify all endpoints are still reporting in. If any went offline, check whether
auditd caused a stability issue (unlikely but worth confirming).

---

## Step 5: Create the Sizing Sensor

1. **Tanium Console** → Administration → Sensors → Create Sensor
2. Sensor settings:
   - **Name:** `Auditd FIM Sizing`
   - **Platform:** Linux
   - **Script type:** Shell
   - **Script:**
     ```bash
     #!/bin/bash
     SENSOR=""
     for d in /opt/Tanium/TaniumClient /opt/tanium /opt/Tanium \
              /var/opt/Tanium /usr/local/tanium /usr/local/Tanium; do
         if [[ -x "$d/sizing-sensor.sh" ]]; then
             SENSOR="$d/sizing-sensor.sh"
             break
         fi
     done
     if [[ -n "$SENSOR" ]]; then
         bash "$SENSOR" 24
     else
         echo "SENSOR_NOT_DEPLOYED"
     fi
     ```
   - **Delimiter:** `|`
   - **Columns:** `hostname`, `role`, `key`, `events`, `bytes_per_day`, `sample_hours`
   - **Max age:** 1 hour
3. Save the sensor.

---

## Step 6: Collect Sizing Data

### Option A: Via Sensor (interactive)

1. **Tanium Console** → Ask a Question:
   ```
   Get Auditd FIM Sizing from all machines in the FIM-Sizing-Test group
   ```
2. Results appear as a table with columns: hostname, role, key, events, bytes_per_day
3. **Export** results as CSV from the Tanium console

### Option B: Via Action (batch)

1. Create a one-time package `auditd-fim-collect`:
   - **Command:** `bash collect-sizing.sh 24`
   - Upload `collect-sizing.sh`
2. Deploy to the Computer Group
3. Retrieve results file:
   - Ask: `Get File Contents{filePath=<tanium_dir>/sizing-results.csv} from all machines in FIM-Sizing-Test`
     (where `<tanium_dir>` is the Tanium client path on your endpoints, e.g. `/opt/Tanium/TaniumClient`)
   - Export as CSV

---

## Step 7: Aggregate Results

On your local workstation (or the admin box):

```bash
# If you exported a single merged CSV from Tanium:
bash aggregate-fleet.sh /path/to/tanium-export.csv

# If you have one CSV per host in a directory:
bash aggregate-fleet.sh /path/to/csv-dir/
```

The aggregator outputs per-role stats (min / median / max bytes/day) and fleet-wide projections.

---

## Step 8: Review and Decide

Use the aggregator output to answer:

| Question | Where to look |
|---|---|
| Which role generates the most logs? | Per-role TOTAL (MB/day) |
| Which keys are noisiest? | Per-key MAX column |
| What's total SIEM ingest? | Fleet-wide combined MB/day |
| Do I need role-specific rule variants? | Compare roles — if one is 10x others, consider trimming |

### If a key is too noisy for a role:

1. Add a `never,exit` exclusion for the noisy executable
2. Scope the rule to fewer directories
3. Create a role-specific variant of `prod.rules`
4. Redeploy and re-measure

---

## Step 9: Go Live

Once sizing is approved:

1. Create package `auditd-fim-lock`:
   - Upload `lock-rules.sh`
   - **Command:** `bash lock-rules.sh`
2. Deploy to all target machines
3. Schedule a reboot (the `-e 2` lock requires reboot to activate)
4. Verify post-reboot:
   ```
   Get Auditd FIM Sizing from all machines in <production group>
   ```

---

## Cleanup (optional)

To remove FIM rules from test machines:

```bash
rm -f /etc/audit/rules.d/90-fim.rules
rm -f /etc/auditd-fim-role
rm -f /opt/tanium/sizing-sensor.sh
rm -f /opt/tanium/sizing-results.csv
augenrules --load
```

Package this as `auditd-fim-remove` for Tanium if needed.
