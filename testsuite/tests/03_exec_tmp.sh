#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

SUID_FILE="/tmp/auditd_exec_test"

run_test "Execution from /tmp" "exec.tmp" "cp /bin/bash $SUID_FILE && chmod +x $SUID_FILE && $SUID_FILE -c 'id'"
