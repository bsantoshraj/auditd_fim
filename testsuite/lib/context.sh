#!/bin/bash
ensure_context() {
    if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
    fi

    if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" ]]; then
        echo "[-] Run via sudo from a non-root user"
        exit 1
    fi
}
