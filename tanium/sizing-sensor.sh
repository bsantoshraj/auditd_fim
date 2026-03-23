#!/bin/bash
#############################################
# Tanium Sensor: Auditd FIM Sizing
#
# Outputs structured CSV for Tanium to parse.
# One row per audit key with event counts
# and byte estimates.
#
# Expected Tanium sensor columns:
#   hostname|role|key|events|bytes_per_day|sample_hours
#
# Role is read from /etc/auditd-fim-role if present,
# otherwise defaults to "untagged".
#############################################

SAMPLE_HOURS="${1:-24}"
CUTOFF_EPOCH=$(date -d "-${SAMPLE_HOURS} hours" '+%s')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# Read role tag
if [[ -f /etc/auditd-fim-role ]]; then
    ROLE=$(cat /etc/auditd-fim-role | tr -d '[:space:]')
else
    ROLE="untagged"
fi

# Byte estimates per event type
declare -A BPE=(
    [fim.identity]=400  [fim.sudo]=400     [fim.ssh]=400
    [fim.auditlog]=400
    [fim.usrbin]=400    [fim.usrsbin]=400
    [fim.cron]=400      [fim.systemd]=400  [fim.boot]=400
    [fim.kernel]=400
    [fim.delete]=600    [fim.perm]=600     [fim.owner]=600
    [exec.tmp]=900      [exec.shm]=900     [exec.vartmp]=900
    [exec.priv_esc]=900
)

KEYS=(
    fim.identity fim.sudo fim.ssh fim.auditlog
    fim.usrbin fim.usrsbin
    fim.cron fim.systemd fim.boot fim.kernel
    fim.delete fim.perm fim.owner
    exec.tmp exec.shm exec.vartmp
    exec.priv_esc
)

# Dump events once, filter by epoch
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

ausearch --raw 2>/dev/null | perl -ne "
    if (/msg=audit\((\d+)\./) { print if \$1 >= $CUTOFF_EPOCH }
" > "$RAW"

# Output CSV
for key in "${KEYS[@]}"; do
    COUNT=$(grep -c "key=\"${key}\"" "$RAW" 2>/dev/null || true)
    COUNT=${COUNT:-0}

    AVG=${BPE[$key]:-500}
    if [[ "$SAMPLE_HOURS" -ne 24 && "$COUNT" -gt 0 ]]; then
        DAILY_BYTES=$(( COUNT * AVG * 24 / SAMPLE_HOURS ))
    else
        DAILY_BYTES=$(( COUNT * AVG ))
    fi

    echo "${HOSTNAME}|${ROLE}|${key}|${COUNT}|${DAILY_BYTES}|${SAMPLE_HOURS}"
done
