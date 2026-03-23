#!/bin/bash
#############################################
# Tanium Action: Collect Sizing Data
#
# Run this as a Tanium Action after the
# 24-48h bake period. It runs the sensor
# and writes results to a known path for
# Tanium to retrieve.
#
# Arguments:
#   $1 = sample hours (default: 24)
#############################################

SAMPLE_HOURS="${1:-24}"
OUTPUT="/opt/tanium/sizing-results.csv"

if [[ ! -x /opt/tanium/sizing-sensor.sh ]]; then
    echo "[auditd-fim] ERROR: sensor not deployed"
    exit 1
fi

bash /opt/tanium/sizing-sensor.sh "$SAMPLE_HOURS" > "$OUTPUT"

echo "[auditd-fim] Results written to $OUTPUT"
echo "[auditd-fim] Lines: $(wc -l < "$OUTPUT")"
