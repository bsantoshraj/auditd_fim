#!/bin/bash
#############################################
# Fleet Aggregator (local)
#
# Takes a directory of CSV files collected
# from Tanium endpoints (or a single merged
# CSV) and produces per-role statistics:
#   min, median, max, total bytes/day
#
# Input format (pipe-delimited):
#   hostname|role|key|events|bytes_per_day|sample_hours
#
# Usage:
#   ./aggregate-fleet.sh <csv_dir_or_file>
#############################################

set -euo pipefail

INPUT="${1:-}"

if [[ -z "$INPUT" ]]; then
    echo "Usage: $0 <csv-directory-or-file>"
    exit 1
fi

# Merge input into one file
MERGED=$(mktemp)
trap 'rm -f "$MERGED"' EXIT

if [[ -d "$INPUT" ]]; then
    cat "$INPUT"/*.csv > "$MERGED" 2>/dev/null || true
elif [[ -f "$INPUT" ]]; then
    cp "$INPUT" "$MERGED"
else
    echo "[-] Not found: $INPUT"
    exit 1
fi

if [[ ! -s "$MERGED" ]]; then
    echo "[-] No data found"
    exit 1
fi

TOTAL_HOSTS=$(cut -d'|' -f1 "$MERGED" | sort -u | wc -l)
ROLES=$(cut -d'|' -f2 "$MERGED" | sort -u)

echo "============================================="
echo " Fleet Sizing Aggregation"
echo "============================================="
echo "Generated:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "Total hosts: $TOTAL_HOSTS"
echo "Roles:       $(echo $ROLES | tr '\n' ' ')"
echo "============================================="
echo ""

FLEET_TOTAL=0

for role in $ROLES; do
    ROLE_DATA=$(grep "|${role}|" "$MERGED")
    HOST_COUNT=$(echo "$ROLE_DATA" | cut -d'|' -f1 | sort -u | wc -l)

    echo "---------------------------------------------"
    echo " Role: $role  (${HOST_COUNT} host(s))"
    echo "---------------------------------------------"
    echo ""
    printf "%-20s %10s %10s %10s\n" "KEY" "MIN/day" "MEDIAN/day" "MAX/day"
    printf "%-20s %10s %10s %10s\n" "---" "-------" "----------" "-------"

    ROLE_KEYS=$(echo "$ROLE_DATA" | cut -d'|' -f3 | sort -u)

    ROLE_MIN=0
    ROLE_MED=0
    ROLE_MAX=0

    for key in $ROLE_KEYS; do
        VALUES=$(echo "$ROLE_DATA" | awk -F'|' -v k="$key" '$3==k {print $5}' | sort -n)
        COUNT=$(echo "$VALUES" | wc -l)

        MIN=$(echo "$VALUES" | head -1)
        MAX=$(echo "$VALUES" | tail -1)

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

        ROLE_MIN=$((ROLE_MIN + MIN))
        ROLE_MED=$((ROLE_MED + MEDIAN))
        ROLE_MAX=$((ROLE_MAX + MAX))
    done

    echo ""
    printf "%-20s %10d %10d %10d\n" "TOTAL (bytes)" "$ROLE_MIN" "$ROLE_MED" "$ROLE_MAX"

    MIN_MB=$(awk "BEGIN {printf \"%.2f\", $ROLE_MIN / 1048576}")
    MED_MB=$(awk "BEGIN {printf \"%.2f\", $ROLE_MED / 1048576}")
    MAX_MB=$(awk "BEGIN {printf \"%.2f\", $ROLE_MAX / 1048576}")
    printf "%-20s %10s %10s %10s\n" "TOTAL (MB/day)" "$MIN_MB" "$MED_MB" "$MAX_MB"

    MIN_MO=$(awk "BEGIN {printf \"%.2f\", ($ROLE_MIN * 30) / 1073741824}")
    MED_MO=$(awk "BEGIN {printf \"%.2f\", ($ROLE_MED * 30) / 1073741824}")
    MAX_MO=$(awk "BEGIN {printf \"%.2f\", ($ROLE_MAX * 30) / 1073741824}")
    printf "%-20s %10s %10s %10s\n" "TOTAL (GB/month)" "$MIN_MO" "$MED_MO" "$MAX_MO"
    echo ""

    FLEET_TOTAL=$((FLEET_TOTAL + ROLE_MED))
done

echo "============================================="
echo " Fleet-wide (median estimate)"
echo "============================================="
FLEET_MB=$(awk "BEGIN {printf \"%.2f\", $FLEET_TOTAL / 1048576}")
FLEET_GB_MO=$(awk "BEGIN {printf \"%.2f\", ($FLEET_TOTAL * 30) / 1073741824}")
AVG_MB=$(awk "BEGIN {printf \"%.2f\", ($FLEET_TOTAL / $TOTAL_HOSTS) / 1048576}")
echo "Hosts:        $TOTAL_HOSTS"
echo "Combined:     ${FLEET_MB} MB/day"
echo "Monthly:      ${FLEET_GB_MO} GB/month"
echo "Per-host avg: ${AVG_MB} MB/day"
echo ""
