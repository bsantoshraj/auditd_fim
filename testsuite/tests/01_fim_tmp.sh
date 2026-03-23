#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

TMP_FILE="/tmp/auditd_test_file"

run_test "FIM /tmp delete (user-origin)" "fim.delete" "sudo -u $SUDO_USER bash -c 'echo test > $TMP_FILE && rm -f $TMP_FILE'"
