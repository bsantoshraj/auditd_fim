#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

run_test "Privilege escalation (sudo)" "exec.priv_esc" "sudo id"
