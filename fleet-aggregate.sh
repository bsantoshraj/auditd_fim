#!/bin/bash
#############################################
# Fleet Sizing Aggregator
#
# Parses collected sizing reports and
# produces per-role statistics:
#   min, median, max, total bytes/day
#
# Usage:
#   ./fleet-aggregate.sh [sizing-data-dir]
#############################################

set -euo pipefail

DATA_DIR="${1:-}"

if [[ -z "$DATA_DIR" || ! -d "$DATA_DIR" ]]; then
    echo "Usage: $0 <sizing-data-dir>"
    echo "  e.g. $0 sizing-data/20260323_102600"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="${DATA_DIR}/fleet-summary.txt"

# --- Parse all collected files ---

# Build a TSV of: role host key events bytes_per_day
PARSED=$(mktemp)
trap 'rm -f "$PARSED"' EXIT

for f in "$DATA_DIR"/*.txt; do
    [[ "$(basename "$f")" == "fleet-summary.txt" ]] && continue
    [[ -f "$f" ]] || continue

    role=$(grep '^# ROLE:' "$f" 2>/dev/null | head -1 | awk '{print $3}')
    host=$(grep '^# HOST:' "$f" 2>/dev/null | head -1 | awk '{print $3}')

    [[ -z "$role" || -z "$host" ]] && continue

    # Extract key lines: "fim.identity       136        54400        54400"
    # Skip header/separator lines, TOTAL line
    grep -E '^\S+\s+[0-9]+\s+[0-9]+\s+[0-9]+$' "$f" 2>/dev/null | while read -r key events bytes daily; do
        echo -e "${role}\t${host}\t${key}\t${events}\t${daily}"
    done

done > "$PARSED"

if [[ ! -s "$PARSED" ]]; then
    echo "[-] No parseable data found in $DATA_DIR"
    exit 1
fi

# --- Aggregate ---

{
echo "============================================="
echo " Fleet Sizing Summary"
echo "============================================="
echo "Data source: $DATA_DIR"
echo "Generated:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="
echo ""

# Get unique roles
ROLES=$(cut -f1 "$PARSED" | sort -u)

for role in $ROLES; do
    ROLE_DATA=$(grep "^${role}	" "$PARSED")
    HOST_COUNT=$(echo "$ROLE_DATA" | cut -f2 | sort -u | wc -l)

    echo "---------------------------------------------"
    echo " Role: $role  (${HOST_COUNT} host(s))"
    echo "---------------------------------------------"
    echo ""
    printf "%-20s %10s %10s %10s\n" "KEY" "MIN/day" "MEDIAN/day" "MAX/day"
    printf "%-20s %10s %10s %10s\n" "---" "-------" "----------" "-------"

    # Get unique keys
    ROLE_KEYS=$(echo "$ROLE_DATA" | cut -f3 | sort -u)

    ROLE_TOTAL_MIN=0
    ROLE_TOTAL_MEDIAN=0
    ROLE_TOTAL_MAX=0

    for key in $ROLE_KEYS; do
        # Get all daily byte values for this role+key
        VALUES=$(echo "$ROLE_DATA" | awk -F'\t' -v k="$key" '$3==k {print $5}' | sort -n)
        COUNT=$(echo "$VALUES" | wc -l)

        MIN=$(echo "$VALUES" | head -1)
        MAX=$(echo "$VALUES" | tail -1)

        # Median
        if [[ $((COUNT % 2)) -eq 1 ]]; then
            MID=$(( (COUNT + 1) / 2 ))
            MEDIAN=$(echo "$VALUES" | sed -n "${MID}p")
        else
            MID1=$(( COUNT / 2 ))
            MID2=$(( MID1 + 1 ))
            V1=$(echo "$VALUES" | sed -n "${MID1}p")
            V2=$(echo "$VALUES" | sed -n "${MID2}p")
            MEDIAN=$(( (V1 + V2) / 2 ))
        fi

        printf "%-20s %10d %10d %10d\n" "$key" "$MIN" "$MEDIAN" "$MAX"

        ROLE_TOTAL_MIN=$((ROLE_TOTAL_MIN + MIN))
        ROLE_TOTAL_MEDIAN=$((ROLE_TOTAL_MEDIAN + MEDIAN))
        ROLE_TOTAL_MAX=$((ROLE_TOTAL_MAX + MAX))
    done

    echo ""
    printf "%-20s %10d %10d %10d\n" "TOTAL (bytes)" "$ROLE_TOTAL_MIN" "$ROLE_TOTAL_MEDIAN" "$ROLE_TOTAL_MAX"

    MIN_MB=$(awk "BEGIN {printf \"%.2f\", $ROLE_TOTAL_MIN / 1048576}")
    MED_MB=$(awk "BEGIN {printf \"%.2f\", $ROLE_TOTAL_MEDIAN / 1048576}")
    MAX_MB=$(awk "BEGIN {printf \"%.2f\", $ROLE_TOTAL_MAX / 1048576}")
    printf "%-20s %10s %10s %10s\n" "TOTAL (MB/day)" "$MIN_MB" "$MED_MB" "$MAX_MB"

    MIN_MO=$(awk "BEGIN {printf \"%.2f\", ($ROLE_TOTAL_MIN * 30) / 1073741824}")
    MED_MO=$(awk "BEGIN {printf \"%.2f\", ($ROLE_TOTAL_MEDIAN * 30) / 1073741824}")
    MAX_MO=$(awk "BEGIN {printf \"%.2f\", ($ROLE_TOTAL_MAX * 30) / 1073741824}")
    printf "%-20s %10s %10s %10s\n" "TOTAL (GB/month)" "$MIN_MO" "$MED_MO" "$MAX_MO"
    echo ""

done

# --- Fleet-wide total ---

echo "============================================="
echo " Fleet-wide Projection"
echo "============================================="
echo ""

# Sum all daily bytes across all hosts
FLEET_TOTAL=$(cut -f5 "$PARSED" | paste -sd+ | bc)
FLEET_HOSTS=$(cut -f2 "$PARSED" | sort -u | wc -l)

FLEET_MB=$(awk "BEGIN {printf \"%.2f\", $FLEET_TOTAL / 1048576}")
FLEET_GB_MO=$(awk "BEGIN {printf \"%.2f\", ($FLEET_TOTAL * 30) / 1073741824}")

echo "Total hosts:     $FLEET_HOSTS"
echo "Combined daily:  ${FLEET_MB} MB/day"
echo "Combined monthly: ${FLEET_GB_MO} GB/month (30-day)"
echo ""

# Per-host average
AVG_MB=$(awk "BEGIN {printf \"%.2f\", ($FLEET_TOTAL / $FLEET_HOSTS) / 1048576}")
echo "Average per host: ${AVG_MB} MB/day"
echo ""

} | tee "$REPORT_FILE"

echo "[+] Summary written to: $REPORT_FILE"
