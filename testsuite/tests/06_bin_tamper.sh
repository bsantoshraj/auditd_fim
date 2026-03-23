#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

TEST_BIN="/usr/bin/auditd_test_bin"

run_test "Binary tamper /usr/bin" "fim.usrbin" "echo test > $TEST_BIN && rm -f $TEST_BIN"
