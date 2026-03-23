#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

SUID_FILE="/tmp/auditd_suid_test"

run_test "SUID creation in /tmp" "fim.perm" "cp /bin/bash $SUID_FILE && chmod +s $SUID_FILE"
