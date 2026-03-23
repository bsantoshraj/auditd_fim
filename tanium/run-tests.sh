#!/bin/bash
#############################################
# Tanium Action: Run FIM Test Suite
#
# Executes the auditd FIM test suite on the
# endpoint and reports results.
#
# Files expected in Tanium package:
#   - run-tests.sh        (this script)
#   - testsuite.tar.gz    (bundled test suite)
#############################################

set -uo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$PACKAGE_DIR/testsuite"

log() { echo "[auditd-fim-test] $1"; }

if [[ $EUID -ne 0 ]]; then
    log "ERROR: must run as root"
    exit 1
fi

# Extract test suite from archive
if [[ ! -d "$SUITE_DIR" ]]; then
    if [[ -f "$PACKAGE_DIR/testsuite.tar.gz" ]]; then
        tar xzf "$PACKAGE_DIR/testsuite.tar.gz" -C "$PACKAGE_DIR"
        log "Extracted testsuite.tar.gz"
    else
        log "ERROR: testsuite.tar.gz not found in package"
        exit 1
    fi
fi

# Ensure scripts are executable
chmod +x "$SUITE_DIR"/run_all.sh
chmod +x "$SUITE_DIR"/tests/*.sh

# Verify auditd is running and rules are loaded
RULE_COUNT=$(auditctl -l 2>/dev/null | wc -l)
if [[ "$RULE_COUNT" -lt 1 ]]; then
    log "ERROR: no audit rules loaded ($RULE_COUNT rules)"
    exit 1
fi
log "Audit rules active: $RULE_COUNT"

# Need SUDO_USER set for tests that run commands as a non-root user
# Find a real user on the system
if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" ]]; then
    SUDO_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /nologin|false/ {print $1; exit}' /etc/passwd)
    if [[ -z "$SUDO_USER" ]]; then
        log "ERROR: no non-root user found for test context"
        exit 1
    fi
    export SUDO_USER
fi

log "Running tests as context user: $SUDO_USER"
log "Host: $(hostname)"
log "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# Run the suite — don't use set -e, we want all tests to run
PASS=0
FAIL=0

for test in "$SUITE_DIR"/tests/*.sh; do
    TEST_NAME=$(basename "$test")
    echo "--------------------------------------"
    echo "[+] Running $TEST_NAME"
    echo "--------------------------------------"

    if bash "$test"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "======================================"
echo "RESULT SUMMARY"
echo "======================================"
echo "Host:   $(hostname)"
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "======================================"

if [[ $FAIL -gt 0 ]]; then
    log "FAILED — $FAIL test(s) did not pass"
    exit 1
else
    log "ALL TESTS PASSED"
    exit 0
fi
