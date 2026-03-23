#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

TEST_SBIN="/usr/sbin/auditd_test_sbin"

run_test "Sbin tamper /usr/sbin" "fim.usrsbin" "echo test > $TEST_SBIN && rm -f $TEST_SBIN"
