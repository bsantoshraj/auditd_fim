#!/bin/bash

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/context.sh"
ensure_context "$@"

echo "[+] Running audit detection test suite (user: $SUDO_USER)"

PASS=0
FAIL=0

for test in "$SCRIPT_DIR"/tests/*.sh; do
    echo "--------------------------------------"
    echo "[+] Running $(basename "$test")"
    echo "--------------------------------------"

    if bash "$test"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

echo "======================================"
echo "RESULT SUMMARY"
echo "======================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"

exit $FAIL
