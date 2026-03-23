#!/bin/bash
#############################################
# Tanium Action: Lock FIM Rules
#
# Run this AFTER sizing is approved to
# enable the -e 2 immutable lock.
# Requires reboot to take effect.
#############################################

set -euo pipefail

RULES_FILE="/etc/audit/rules.d/90-fim.rules"

if [[ ! -f "$RULES_FILE" ]]; then
    echo "[auditd-fim] ERROR: rules not deployed"
    exit 1
fi

# Add lock if not present
if ! grep -q '^-e 2' "$RULES_FILE"; then
    echo "-e 2" >> "$RULES_FILE"
    echo "[auditd-fim] Lock added to $RULES_FILE"
    echo "[auditd-fim] Reboot required to activate immutable ruleset"
else
    echo "[auditd-fim] Lock already present"
fi
