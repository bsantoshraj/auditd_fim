#!/bin/bash
#############################################
# Auditd FIM Sizing Report
# Collects per-key event counts and
# estimates daily log volume in bytes.
#############################################

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[-] Must run as root (sudo $0)"
    exit 1
fi

# --- Configuration ---

SAMPLE_HOURS="${1:-24}"
OUTPUT_FILE="${2:-}"

declare -A BYTES_PER_EVENT=(
    [fim.identity]=400
    [fim.sudo]=400
    [fim.ssh]=400
    [fim.auditlog]=400
    [fim.usrbin]=400
    [fim.usrsbin]=400
    [fim.cron]=400
    [fim.systemd]=400
    [fim.boot]=400
    [fim.kernel]=400
    [fim.delete]=600
    [fim.perm]=600
    [fim.owner]=600
    [exec.tmp]=900
    [exec.shm]=900
    [exec.vartmp]=900
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

# --- Output handling ---

if [[ -n "$OUTPUT_FILE" ]]; then
    exec > >(tee "$OUTPUT_FILE") 2>&1
    echo "[+] Writing output to: $OUTPUT_FILE"
    echo ""
fi

# --- Compute time window using epoch ---

CUTOFF_EPOCH=$(date -d "-${SAMPLE_HOURS} hours" '+%s')
NOW_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')
START_DISPLAY=$(date -d "-${SAMPLE_HOURS} hours" '+%Y-%m-%d %H:%M:%S')

echo "============================================="
echo " Auditd FIM Sizing Report"
echo "============================================="
echo "Host:          $(hostname)"
echo "Sample window: ${SAMPLE_HOURS}h"
echo "From:          ${START_DISPLAY}"
echo "To:            ${NOW_DISPLAY}"
echo "============================================="
echo ""

# --- Dump all raw events once, filter by epoch ---

TMPDIR_SIZING=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SIZING"' EXIT

# Grab all audit events, keep only lines within our time window
# Filter raw events by epoch cutoff using perl (portable, fast)
ausearch --raw 2>/dev/null | perl -ne "
    if (/msg=audit\((\d+)\./) { print if \$1 >= $CUTOFF_EPOCH }
" > "$TMPDIR_SIZING/all_events.raw"

# --- Collect per-key counts ---

TOTAL_EVENTS=0
TOTAL_BYTES=0
declare -A KEY_COUNTS

printf "%-20s %10s %12s %12s\n" "KEY" "EVENTS" "BYTES" "BYTES/DAY"
printf "%-20s %10s %12s %12s\n" "---" "------" "-----" "---------"

for key in "${KEYS[@]}"; do
    COUNT=$(grep -c "key=\"${key}\"" "$TMPDIR_SIZING/all_events.raw" 2>/dev/null || true)
    COUNT=${COUNT:-0}

    KEY_COUNTS[$key]=$COUNT
    AVG_BYTES=${BYTES_PER_EVENT[$key]:-500}
    RAW_BYTES=$((COUNT * AVG_BYTES))

    if [[ "$SAMPLE_HOURS" -ne 24 && "$COUNT" -gt 0 ]]; then
        DAILY_BYTES=$(( RAW_BYTES * 24 / SAMPLE_HOURS ))
        DAILY_COUNT=$(( COUNT * 24 / SAMPLE_HOURS ))
    else
        DAILY_BYTES=$RAW_BYTES
        DAILY_COUNT=$COUNT
    fi

    KEY_COUNTS["${key}_daily"]=$DAILY_COUNT

    printf "%-20s %10d %12d %12d\n" "$key" "$COUNT" "$RAW_BYTES" "$DAILY_BYTES"

    TOTAL_EVENTS=$((TOTAL_EVENTS + COUNT))
    TOTAL_BYTES=$((TOTAL_BYTES + DAILY_BYTES))
done

echo ""
printf "%-20s %10d %12s %12d\n" "TOTAL" "$TOTAL_EVENTS" "" "$TOTAL_BYTES"
echo ""

# --- Human-readable summary ---

if [[ $TOTAL_BYTES -gt 0 ]]; then
    DAILY_MB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_BYTES / 1048576}")
    DAILY_GB=$(awk "BEGIN {printf \"%.4f\", $TOTAL_BYTES / 1073741824}")
    MONTHLY_GB=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_BYTES * 30) / 1073741824}")

    echo "============================================="
    echo " Estimated Daily Volume"
    echo "============================================="
    echo "  ${DAILY_MB} MB/day  (${DAILY_GB} GB/day)"
    echo "  ${MONTHLY_GB} GB/month (30-day)"
    echo ""

    # --- Flag noisy keys ---
    echo "============================================="
    echo " Noise Flags (>1000 events/day)"
    echo "============================================="

    FOUND_NOISY=0
    for key in "${KEYS[@]}"; do
        DAILY_COUNT=${KEY_COUNTS["${key}_daily"]}
        if [[ $DAILY_COUNT -gt 1000 ]]; then
            echo "  [!] $key: ~${DAILY_COUNT} events/day — review for exclusions"
            FOUND_NOISY=1
        fi
    done

    if [[ $FOUND_NOISY -eq 0 ]]; then
        echo "  None — all keys under 1000 events/day"
    fi
else
    echo "No audit events found in sample window."
    echo "Verify rules are loaded: sudo auditctl -l"
fi

echo ""
echo "============================================="
echo " Top 10 Executables Generating Events"
echo "============================================="
grep -oP 'exe="?\K[^" ]+' "$TMPDIR_SIZING/all_events.raw" 2>/dev/null \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -10 \
    | while read -r count exe; do
        printf "  %8d  %s\n" "$count" "$exe"
    done

echo ""
