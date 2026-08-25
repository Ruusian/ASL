#!/bin/bash
# ASL Persistent Tunnel Manager - manages configured Oracle / VPS reverse tunnels

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "$SCRIPT_DIR/desktop/remote/oracle.sh" ]; then
    source "$SCRIPT_DIR/desktop/remote/oracle.sh"
else
    echo "Error: Oracle remote module not found."
    exit 1
fi

case "${1:-status}" in
    start)
        oracle_control start
        ;;
    stop)
        oracle_control stop
        ;;
    status)
        oracle_control status
        ;;
    *)
        oracle_control "$@"
        ;;
esac
