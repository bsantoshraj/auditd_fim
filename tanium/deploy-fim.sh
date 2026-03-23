#!/bin/bash
#############################################
# Tanium Package: Deploy Auditd FIM Rules
#
# This script is run by Tanium Action on
# target endpoints. It:
#   1. Installs auditd if missing
#   2. Tags the node role
#   3. Deploys prod.rules
#   4. Loads rules (without -e 2 lock for
#      sizing phase)
#   5. Deploys the sizing sensor script
#
# Arguments:
#   $1 = node role (webserver, database, etc.)
#
# Files expected in Tanium package:
#   - deploy-fim.sh     (this script)
#   - prod.rules        (audit rules)
#   - sizing-sensor.sh  (sensor script)
#############################################

set -euo pipefail

ROLE="${1:-untagged}"
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[auditd-fim] $1"; }

# --- 0. Detect Tanium client directory ---

TANIUM_DIR=""
for d in /opt/Tanium/TaniumClient /opt/tanium /opt/Tanium /var/opt/Tanium /usr/local/tanium /usr/local/Tanium; do
    if [[ -d "$d" ]]; then
        TANIUM_DIR="$d"
        break
    fi
done

if [[ -z "$TANIUM_DIR" ]]; then
    # Try finding TaniumClient process working dir
    TANIUM_PID=$(pgrep -f TaniumClient 2>/dev/null | head -1)
    if [[ -n "$TANIUM_PID" ]]; then
        TANIUM_DIR=$(readlink -f "/proc/$TANIUM_PID/cwd" 2>/dev/null || true)
    fi
fi

if [[ -z "$TANIUM_DIR" || ! -d "$TANIUM_DIR" ]]; then
    log "ERROR: Cannot locate Tanium client directory"
    exit 1
fi

log "Tanium directory: $TANIUM_DIR"

# --- 1. Ensure auditd is installed ---

if ! command -v auditctl &>/dev/null; then
    log "Installing auditd..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq auditd audispd-plugins
    elif command -v yum &>/dev/null; then
        yum install -y -q audit
    elif command -v dnf &>/dev/null; then
        dnf install -y -q audit
    else
        log "ERROR: No supported package manager found"
        exit 1
    fi
fi

# --- 2. Tag node role ---

echo "$ROLE" > /etc/auditd-fim-role
log "Tagged role: $ROLE"

# --- 3. Deploy rules (sizing mode — no lock) ---

mkdir -p /etc/audit/rules.d

# Remove any previous FIM rules
rm -f /etc/audit/rules.d/prod.rules
rm -f /etc/audit/rules.d/50-fim.rules

# Copy rules, strip the lock for sizing phase
grep -v '^-e 2' "$PACKAGE_DIR/prod.rules" > /etc/audit/rules.d/90-fim.rules
log "Deployed rules to /etc/audit/rules.d/90-fim.rules (no lock)"

# --- 4. Load rules ---

if augenrules --load 2>&1; then
    log "Rules loaded successfully"
else
    log "WARNING: augenrules failed, attempting auditctl direct load"
    auditctl -R /etc/audit/rules.d/90-fim.rules 2>&1 || true
fi

# --- 5. Deploy sensor script ---

cp "$PACKAGE_DIR/sizing-sensor.sh" "$TANIUM_DIR/sizing-sensor.sh"
chmod 755 "$TANIUM_DIR/sizing-sensor.sh"
log "Sensor deployed to $TANIUM_DIR/sizing-sensor.sh"

# --- 6. Verify ---

RULE_COUNT=$(auditctl -l 2>/dev/null | wc -l)
log "Active rules: $RULE_COUNT"
log "Deployment complete. Allow 24-48h bake time before collecting sizing data."
