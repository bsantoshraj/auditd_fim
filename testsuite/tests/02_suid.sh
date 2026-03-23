#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

SUID_FILE="/tmp/auditd_suid_test"

# fim.perm requires auid>=1000. When running from Tanium (root service,
# auid unset), the rule won't fire. Check if we have a real login session.
CURRENT_AUID=$(cat /proc/self/loginuid 2>/dev/null || echo "4294967295")

if [[ "$CURRENT_AUID" != "4294967295" ]]; then
    run_test "SUID creation in /tmp" "fim.perm" "cp /bin/bash $SUID_FILE && chmod +s $SUID_FILE"
else
    echo "[SKIP] SUID creation in /tmp — no login session (auid unset, Tanium context)"
fi
