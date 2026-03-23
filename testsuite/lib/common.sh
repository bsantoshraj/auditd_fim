#!/bin/bash

WAIT_TIME=2

log()  { echo "[+] $1"; }
pass() { echo "[PASS] $1"; return 0; }
fail() { echo "[FAIL] $1"; return 1; }

get_count() {
    local key="$1"
    ausearch -k "$key" | wc -l
}

wait_for_logs() {
    sleep "$WAIT_TIME"
}

run_test() {
    local desc="$1"
    local key="$2"
    local cmd="$3"

    log "$desc"

    local BEFORE AFTER
    BEFORE=$(get_count "$key")

    if ! eval "$cmd"; then
        fail "$desc (command failed)"
        return 1
    fi

    wait_for_logs

    AFTER=$(get_count "$key")

    if (( AFTER > BEFORE )); then
        pass "$desc ($key detected)"
        return 0
    else
        fail "$desc (no new audit event)"
        return 1
    fi
}
