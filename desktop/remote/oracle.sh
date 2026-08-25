#!/bin/bash
# ASL Remote Access - Oracle Cloud VPS Dedicated Reverse Tunnel

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"

ORACLE_KEY="$HOME/.ssh/oracle_vps.key"
ORACLE_LOG="$PREFIX/tmp/oracle-vps.log"
ORACLE_STATE="$PREFIX/tmp/asl-oracle.state"
ORACLE_HOST="${ASL_ORACLE_HOST:-130.210.19.7}"
ORACLE_USER="${ASL_ORACLE_USER:-ubuntu}"
ORACLE_PORT="${ASL_ORACLE_PORT:-2222}"

oracle_running() {
    [ -f "$ORACLE_STATE" ] && pgrep -f "ssh.*-N.*${ORACLE_HOST}" >/dev/null 2>&1 && \
        ! grep -qE "remote port forwarding failed|Permission denied|Connection closed|Connection refused|Host key verification failed|kex_exchange_identification" "$ORACLE_LOG" 2>/dev/null
}

oracle_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            ensure_host_sshd
            touch "$ORACLE_STATE"
            if oracle_running; then
                echo "[*] Oracle VPS dedicated tunnel is already running."
            else
                # Kill only tunnel SSH processes (-N flag), not interactive sessions
                pkill -f "ssh.*-N.*${ORACLE_HOST}" 2>/dev/null || true
                sleep 1
                echo "[*] Clearing stale listeners on Oracle VPS (${ORACLE_HOST}:${ORACLE_PORT})..."
                # Kill all sshd children holding the tunnel port (not the main sshd)
                ssh -i "$ORACLE_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${ORACLE_USER}@${ORACLE_HOST}" "
                    for pid in \$(sudo ss -tulpn | grep ':${ORACLE_PORT} ' | grep -oP 'pid=\K[0-9]+'); do
                        ppid=\$(ps -o ppid= -p \$pid 2>/dev/null | tr -d ' ')
                        [ -n \"\$ppid\" ] && [ \"\$ppid\" != \"1\" ] && sudo kill -9 \$pid \$ppid 2>/dev/null
                    done
                    sleep 2
                    sudo ss -tulpn | grep ':${ORACLE_PORT} ' || echo PORT_CLEARED
                " 2>/dev/null || true
                sleep 1
                echo "[*] Launching Oracle VPS persistent SSH tunnel (${ORACLE_HOST}:${ORACLE_PORT} -> 8022)..."
                rm -f "$ORACLE_LOG"
                nohup ssh -i "$ORACLE_KEY" -T -N -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o ConnectTimeout=15 -R "${ORACLE_PORT}:127.0.0.1:8022" "${ORACLE_USER}@${ORACLE_HOST}" > "$ORACLE_LOG" 2>&1 &
                echo $! > "$ORACLE_STATE"
                sleep 4
                if ! oracle_running; then
                    echo "Error: Oracle VPS tunnel failed to connect. Log output:"
                    cat "$ORACLE_LOG" 2>/dev/null
                    return 1
                fi
            fi
            oracle_status
            ;;
        stop)
            if oracle_running; then
                local pid
                pid=$(cat "$ORACLE_STATE" 2>/dev/null)
                [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || pkill -f "ssh.*-N.*${ORACLE_HOST}" 2>/dev/null || true
                rm -f "$ORACLE_STATE" "$ORACLE_LOG"
                echo "[✓] Oracle VPS tunnel stopped."
            else
                rm -f "$ORACLE_STATE"
                echo "[*] Oracle VPS tunnel is not running."
            fi
            ;;
        status|"")
            oracle_status
            ;;
    esac
}

oracle_status() {
    if oracle_running; then
        echo "Oracle VPS Tunnel: RUNNING (Dedicated Always-On Private Relay)"
        echo "    Host:     ${ORACLE_HOST} (User: ${ORACLE_USER})"
        echo "    Connect:  ssh -J ${ORACLE_USER}@${ORACLE_HOST} -p ${ORACLE_PORT} $(whoami)@127.0.0.1"
        echo "    Authentication: SSH key or configured remote credential"
    else
        echo "Oracle VPS Tunnel: STOPPED"
    fi
}
