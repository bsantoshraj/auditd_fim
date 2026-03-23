#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# exec.priv_esc requires auid>=1000. When running from Tanium (root service,
# auid unset), the rule won't fire.
CURRENT_AUID=$(cat /proc/self/loginuid 2>/dev/null || echo "4294967295")

if [[ "$CURRENT_AUID" != "4294967295" ]]; then
    run_test "Privilege escalation (sudo)" "exec.priv_esc" "sudo id"
else
    echo "[SKIP] Privilege escalation — no login session (auid unset, Tanium context)"
fi
