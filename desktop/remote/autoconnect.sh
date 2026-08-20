#!/bin/bash
# ASL Remote Access - Seamless Auto-Connect Daemon & Fallback Engine

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"
source "$SCRIPT_DIR/desktop/remote/oracle.sh"
source "$SCRIPT_DIR/desktop/remote/serveo.sh"

AUTOCONNECT_STATE="$PREFIX/tmp/asl-autoconnect.state"
AUTOCONNECT_LOG="$PREFIX/tmp/asl-autoconnect.log"
AUTOCONNECT_PID="$PREFIX/tmp/asl-autoconnect.pid"

is_online() {
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || \
    ping -c 1 -W 2 9.9.9.9 >/dev/null 2>&1 || \
    curl -s --connect-timeout 2 -I https://1.1.1.1 >/dev/null 2>&1
}

autoconnect_daemon() {
    echo $$ > "$AUTOCONNECT_PID" 2>/dev/null || true
    termux-wake-lock 2>/dev/null || true
    local script_path="$SCRIPT_DIR/desktop/remote.sh"

    while [ -f "$AUTOCONNECT_STATE" ]; do
        ensure_host_sshd

        if is_online; then
            if [ -f "$ORACLE_KEY" ] && ! oracle_running; then
                echo "[Autoconnect $(date +%H:%M:%S)] Oracle VPS tunnel offline. Re-establishing..." >> "$AUTOCONNECT_LOG"
                bash "$script_path" oracle start >> "$AUTOCONNECT_LOG" 2>&1 || true
            fi

            if ! serveo_running; then
                echo "[Autoconnect $(date +%H:%M:%S)] Serveo tunnel offline. Re-establishing..." >> "$AUTOCONNECT_LOG"
                bash "$script_path" serveo start >> "$AUTOCONNECT_LOG" 2>&1 || true
            fi
        fi

        if [ -f "$AUTOCONNECT_LOG" ] && [ "$(wc -c < "$AUTOCONNECT_LOG" 2>/dev/null || echo 0)" -gt 102400 ]; then
            tail -n 200 "$AUTOCONNECT_LOG" > "$AUTOCONNECT_LOG.tmp" 2>/dev/null && mv "$AUTOCONNECT_LOG.tmp" "$AUTOCONNECT_LOG" 2>/dev/null || true
        fi

        sleep 30
    done

    rm -f "$AUTOCONNECT_PID" 2>/dev/null || true
}

is_autoconnect_running() {
    if [ -f "$AUTOCONNECT_PID" ]; then
        local pid
        pid=$(cat "$AUTOCONNECT_PID" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    pgrep -f "remote.sh autoconnect-daemon" >/dev/null 2>&1
}

autoconnect_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            if is_autoconnect_running; then
                echo "[*] Auto-Connect daemon is already running."
            else
                echo "[*] Starting ASL Seamless Remote Auto-Connect Daemon..."
                touch "$AUTOCONNECT_STATE"
                termux-wake-lock 2>/dev/null || true
                nohup bash "$SCRIPT_DIR/desktop/remote.sh" autoconnect-daemon > "$AUTOCONNECT_LOG" 2>&1 &
                echo $! > "$AUTOCONNECT_PID" 2>/dev/null || true
                echo "[✓] Auto-Connect daemon active (Wake-lock engaged)."
            fi
            ;;
        stop)
            rm -f "$AUTOCONNECT_STATE" "$AUTOCONNECT_PID"
            pkill -f "remote.sh autoconnect-daemon" 2>/dev/null || true
            termux-wake-unlock 2>/dev/null || true
            echo "[✓] Auto-Connect daemon stopped."
            ;;
        status|"")
            if is_autoconnect_running; then
                echo "Auto-Connect Daemon: ACTIVE (Monitoring SSH, Serveo & Oracle with Wake-Lock)"
            else
                echo "Auto-Connect Daemon: INACTIVE"
            fi
            ;;
    esac
}
