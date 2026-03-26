#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

TEST_FILE="/var/log/audit/auditd_test_canary"

run_test "Audit log tamper detection" "fim.auditlog" "echo canary > $TEST_FILE && rm -f $TEST_FILE"
