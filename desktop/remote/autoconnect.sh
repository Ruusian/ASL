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
    ensure_host_dns
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || \
    ping -c 1 -W 2 9.9.9.9 >/dev/null 2>&1 || \
    curl -s --connect-timeout 2 -I https://1.1.1.1 >/dev/null 2>&1
}

autoconnect_daemon() {
    echo $$ > "$AUTOCONNECT_PID" 2>/dev/null || true
    termux-wake-lock 2>/dev/null || true

    # Protect autoconnect daemon from OOM eviction
    if [ -w "/proc/$$/oom_score_adj" ]; then
        echo "-1000" > "/proc/$$/oom_score_adj" 2>/dev/null || true
    elif command -v su >/dev/null 2>&1; then
        su -c "echo -1000 > /proc/$$/oom_score_adj" 2>/dev/null || true
    fi

    local script_path="$SCRIPT_DIR/desktop/remote.sh"
    local prev_ip=""
    local curr_ip=""

    while [ -f "$AUTOCONNECT_STATE" ]; do
        ensure_host_sshd
        termux-wake-lock 2>/dev/null || true
        curr_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' || ip -o -4 addr show 2>/dev/null | awk '$2 != "lo" {sub(/\/.*/, "", $4); print $4; exit}')

        # Detect network interface IP handoff (Wi-Fi <-> Cellular) & instantly clear stale SSH sockets
        if [ -n "$prev_ip" ] && [ -n "$curr_ip" ] && [ "$prev_ip" != "$curr_ip" ]; then
            echo "[Autoconnect $(date +%H:%M:%S)] Network IP changed ($prev_ip -> $curr_ip). Evicting stale SSH tunnel sockets..." >> "$AUTOCONNECT_LOG"
            load_oracle_config 2>/dev/null || true
            pkill -9 -f "ssh.*${ORACLE_HOST:-130.210.19.7}" 2>/dev/null || true
            pkill -9 -f "serveo.net" 2>/dev/null || true
            pkill -9 -f "ngrok.*tcp" 2>/dev/null || true
        fi
        [ -n "$curr_ip" ] && prev_ip="$curr_ip"

        if is_online; then
            if [ -f "$ORACLE_KEY" ] && ! oracle_running; then
                echo "[Autoconnect $(date +%H:%M:%S)] Oracle VPS tunnels offline or unresponsive. Re-establishing..." >> "$AUTOCONNECT_LOG"
                bash "$script_path" oracle start >> "$AUTOCONNECT_LOG" 2>&1 || true
            fi

            if ! serveo_running; then
                echo "[Autoconnect $(date +%H:%M:%S)] Serveo tunnel offline. Re-establishing..." >> "$AUTOCONNECT_LOG"
                bash "$script_path" serveo start >> "$AUTOCONNECT_LOG" 2>&1 || true
            fi

            if [ -f "$PREFIX/tmp/asl-ngrok.state" ] && ! pgrep -f "ngrok.*tcp" >/dev/null 2>&1; then
                echo "[Autoconnect $(date +%H:%M:%S)] Ngrok tunnel offline. Re-establishing..." >> "$AUTOCONNECT_LOG"
                bash "$script_path" ngrok start >> "$AUTOCONNECT_LOG" 2>&1 || true
            fi
        fi

        if [ -f "$AUTOCONNECT_LOG" ] && [ "$(wc -c < "$AUTOCONNECT_LOG" 2>/dev/null || echo 0)" -gt 102400 ]; then
            tail -n 200 "$AUTOCONNECT_LOG" > "$AUTOCONNECT_LOG.tmp" 2>/dev/null && mv "$AUTOCONNECT_LOG.tmp" "$AUTOCONNECT_LOG" 2>/dev/null || true
        fi

        sleep 15
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
        rm -f "$AUTOCONNECT_PID" 2>/dev/null || true
    fi
    if pgrep -f "remote.sh autoconnect-daemon" >/dev/null 2>&1; then
        return 0
    fi
    return 1
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
