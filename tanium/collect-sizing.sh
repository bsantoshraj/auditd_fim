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

# Detect Tanium directory
TANIUM_DIR=""
for d in /opt/Tanium/TaniumClient /opt/tanium /opt/Tanium /var/opt/Tanium /usr/local/tanium /usr/local/Tanium; do
    if [[ -d "$d" ]]; then
        TANIUM_DIR="$d"
        break
    fi
done

if [[ -z "$TANIUM_DIR" ]]; then
    TANIUM_PID=$(pgrep -f TaniumClient 2>/dev/null | head -1)
    if [[ -n "$TANIUM_PID" ]]; then
        TANIUM_DIR=$(readlink -f "/proc/$TANIUM_PID/cwd" 2>/dev/null || true)
    fi
fi

if [[ -z "$TANIUM_DIR" || ! -d "$TANIUM_DIR" ]]; then
    echo "[auditd-fim] ERROR: Cannot locate Tanium client directory"
    exit 1
fi

SENSOR="$TANIUM_DIR/sizing-sensor.sh"
OUTPUT="$TANIUM_DIR/sizing-results.csv"

if [[ ! -x "$SENSOR" ]]; then
    echo "[auditd-fim] ERROR: sensor not deployed at $SENSOR"
    exit 1
fi

bash "$SENSOR" "$SAMPLE_HOURS" > "$OUTPUT"

echo "[auditd-fim] Results written to $OUTPUT"
echo "[auditd-fim] Lines: $(wc -l < "$OUTPUT")"
