# Auditd FIM Log Sizing Guide

## Rule Noise Profiles

| Rule type | Volume driver | How to estimate |
|---|---|---|
| File watches (`-w`) | Frequency of writes to watched paths | Varies by node role |
| Syscall rules (`-a always,exit`) | System-wide call rate x filter selectivity | `auid>=1000` helps, but delete/chmod/chown are common |
| Exec rules | How often anything runs from `/tmp`, `/dev/shm` | Usually low unless cron/ansible drops scripts there |
| Priv esc (`euid=0`) | Every sudo/su invocation by real users | Depends on automation patterns |

## Node Role Considerations

| Role | High-volume concerns |
|---|---|
| Web/app server | Config mgmt churn in `/etc`, deploys touching `/usr/bin` |
| Build/CI runner | Massive `/tmp` activity, constant installs to `/usr/bin` |
| Database | Low FIM noise, but `chown`/`chmod` from backup scripts |
| Bastion/jump box | High `exec.priv_esc` from legitimate sudo usage |
| Container host | Mostly quiet if dockerd/containerd excluded, but watch for orchestrator churn |

## Per-Event Size Estimates

| Event type | Bytes per event |
|---|---|
| File watch (SYSCALL+PATH) | 300-500 |
| Syscall rule (SYSCALL+PATH+CWD+PROCTITLE) | 400-800 |
| Execve (adds EXECVE args) | 600-1200 |

## Sizing Workflow

1. Deploy rules **without** `-e 2` (lock) to a representative node of each role
2. Let it bake for 24-48h (cover a patch window if possible)
3. Run `sizing-report.sh` to collect per-key event counts and byte estimates
4. If any key exceeds SIEM ingest budget:
   - Add a `never,exit` exclusion for the noisy executable
   - Scope the rule to fewer directories
   - Evaluate if the rule is worth the cost for this role
5. Build per-role rule variants if needed

## Volume Dominators (watch these first)

1. **`fim.delete`** - `unlink`/`rename` from every user process. Usually the noisiest rule. Consider scoping to specific dirs if too loud.
2. **`fim.perm` / `fim.owner`** - every `chmod`/`chown` by uid>=1000. Automation users with real UIDs will trigger this.
3. **`fim.usrbin`** - quiet on stable servers, enormous during patching windows.
4. **`exec.priv_esc`** - every `sudo` by a real user. High on bastions, low on app servers.
