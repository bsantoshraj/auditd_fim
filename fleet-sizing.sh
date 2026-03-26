#!/bin/bash
#############################################
# Fleet Sizing Collector
#
# Deploys sizing-report.sh to remote hosts,
# runs it, and collects results locally.
#
# Usage:
#   ./fleet-sizing.sh [inventory_file] [sample_hours]
#
# Requires: ssh key-based access with sudo
#############################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${1:-$SCRIPT_DIR/fleet-inventory.conf}"
SAMPLE_HOURS="${2:-24}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
COLLECT_DIR="$SCRIPT_DIR/sizing-data/${TIMESTAMP}"

if [[ ! -f "$INVENTORY" ]]; then
    echo "[-] Inventory file not found: $INVENTORY"
    exit 1
fi

mkdir -p "$COLLECT_DIR"

echo "============================================="
echo " Fleet Sizing Collector"
echo "============================================="
echo "Inventory:     $INVENTORY"
echo "Sample window: ${SAMPLE_HOURS}h"
echo "Output dir:    $COLLECT_DIR"
echo "============================================="
echo ""

TOTAL=0
SUCCESS=0
FAILED=0

while IFS=' ' read -r host role ssh_user ssh_port; do
    # Skip comments and blank lines
    [[ -z "$host" || "$host" == \#* ]] && continue

    ssh_user="${ssh_user:-ubuntu}"
    ssh_port="${ssh_port:-22}"
    TOTAL=$((TOTAL + 1))

    OUTFILE="${COLLECT_DIR}/${role}_${host}.txt"

    echo "[+] ${host} (role=${role}, user=${ssh_user})"

    # Deploy sizing-report.sh
    if ! scp -P "$ssh_port" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        "$SCRIPT_DIR/sizing-report.sh" "${ssh_user}@${host}:/tmp/sizing-report.sh" 2>/dev/null; then
        echo "    [-] SCP failed — skipping"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Run remotely, capture output
    if ssh -p "$ssh_port" -o ConnectTimeout=10 "${ssh_user}@${host}" \
        "sudo bash /tmp/sizing-report.sh ${SAMPLE_HOURS}" > "$OUTFILE" 2>&1; then
        echo "    [+] Collected -> $(basename "$OUTFILE")"
        # Tag the file with role metadata
        sed -i "1i# ROLE: ${role}" "$OUTFILE"
        sed -i "2i# HOST: ${host}" "$OUTFILE"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "    [-] Remote execution failed (see $OUTFILE)"
        FAILED=$((FAILED + 1))
    fi

    # Cleanup remote
    ssh -p "$ssh_port" -o ConnectTimeout=5 "${ssh_user}@${host}" \
        "rm -f /tmp/sizing-report.sh" 2>/dev/null || true

done < "$INVENTORY"

echo ""
echo "============================================="
echo " Collection Summary"
echo "============================================="
echo "Total hosts: $TOTAL"
echo "Succeeded:   $SUCCESS"
echo "Failed:      $FAILED"
echo "Data dir:    $COLLECT_DIR"
echo ""

if [[ $SUCCESS -gt 0 ]]; then
    echo "[+] Run the aggregator next:"
    echo "    bash $SCRIPT_DIR/fleet-aggregate.sh $COLLECT_DIR"
fi
