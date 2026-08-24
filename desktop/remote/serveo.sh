#!/bin/bash
# ASL Remote Access - Serveo Tunnel

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"

SERVEO_KEY="$HOME/.ssh/id_serveo_asl"
SERVEO_LOG="$PREFIX/tmp/serveo.log"
SERVEO_STATE="$PREFIX/tmp/asl-serveo.state"
SERVEO_ALIAS_FILE="$CONFIG_DIR/serveo_alias.txt"

get_serveo_alias() {
    if [ -f "$PREFIX/tmp/asl-serveo-active.alias" ] && [ -s "$PREFIX/tmp/asl-serveo-active.alias" ] && pgrep -f "serveo.net" >/dev/null 2>&1; then
        cat "$PREFIX/tmp/asl-serveo-active.alias" 2>/dev/null
    elif [ -f "$SERVEO_ALIAS_FILE" ] && [ -s "$SERVEO_ALIAS_FILE" ]; then
        cat "$SERVEO_ALIAS_FILE" 2>/dev/null
    elif [ -n "${ASL_SERVEO_ALIAS:-}" ]; then
        echo "$ASL_SERVEO_ALIAS"
    else
        echo "asl-termux-8022"
    fi
}

ensure_serveo_key() {
    if [ ! -f "$SERVEO_KEY" ]; then
        echo "[*] Generating fixed SSH key for Serveo persistent tunnel..."
        ssh-keygen -t ed25519 -f "$SERVEO_KEY" -N "" -C "asl-serveo" >/dev/null 2>&1
        chmod 600 "$SERVEO_KEY"
    fi
}

serveo_running() {
    if [ -f "$SERVEO_LOG" ] && [ "$(wc -c < "$SERVEO_LOG" 2>/dev/null || echo 0)" -gt 102400 ]; then
        tail -n 200 "$SERVEO_LOG" > "$SERVEO_LOG.tmp" 2>/dev/null && mv "$SERVEO_LOG.tmp" "$SERVEO_LOG" 2>/dev/null || true
    fi
    if [ -f "$SERVEO_STATE" ] && pgrep -f "serveo.net" >/dev/null 2>&1; then
        if tail -n 10 "$SERVEO_LOG" 2>/dev/null | grep -qE "remote port forwarding failed|Permission denied|Connection closed|Host key verification failed|Timeout, server|broken pipe|No route to host|Network is unreachable|Software caused connection abort|Connection reset"; then
            pkill -9 -f "serveo.net" 2>/dev/null || true
            return 1
        fi
        return 0
    fi
    return 1
}

serveo_control() {
    local action="${1:-status}"
    case "$action" in
        alias|set-alias)
            local new_alias="${2:-}"
            if [ -z "$new_alias" ] || [[ ! "$new_alias" =~ ^[A-Za-z0-9_-]+$ ]]; then
                echo "Usage: asl remote serveo alias <custom_alias>"
                return 1
            fi
            echo "$new_alias" > "$SERVEO_ALIAS_FILE"
            chmod 600 "$SERVEO_ALIAS_FILE"
            echo "[✓] Custom Serveo alias set to: $new_alias"
            ;;
        start)
            ensure_host_sshd
            ensure_serveo_key
            touch "$SERVEO_STATE"
            if serveo_running; then
                echo "[*] Serveo tunnel is already running."
            else
                pkill -f "serveo.net" 2>/dev/null || true
                sleep 1
                local serveo_alias
                serveo_alias=$(get_serveo_alias)
                echo "[*] Launching Serveo persistent SSH tunnel on port 8022 (alias: ${serveo_alias})..."
                rm -f "$SERVEO_LOG"
                nohup ssh -i "$SERVEO_KEY" -T -N \
                    -o StrictHostKeyChecking=accept-new \
                    -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
                    -o ServerAliveInterval=10 \
                    -o ServerAliveCountMax=3 \
                    -o ExitOnForwardFailure=yes \
                    -o ConnectTimeout=10 \
                    -R "${serveo_alias}:22:127.0.0.1:8022" serveo.net > "$SERVEO_LOG" 2>&1 &
                echo $! > "$SERVEO_STATE"
                sleep 4
                echo "$serveo_alias" > "$PREFIX/tmp/asl-serveo-active.alias" 2>/dev/null || true
                if ! serveo_running; then
                    if grep -qE "remote port forwarding failed|alias" "$SERVEO_LOG" 2>/dev/null; then
                        local dev_suffix
                        dev_suffix=$(sha256sum /proc/sys/kernel/random/boot_id 2>/dev/null | cut -c1-4 || echo "$RANDOM")
                        serveo_alias="${serveo_alias}-${dev_suffix}"
                        echo "[!] Primary alias in use. Retrying with device fallback alias: ${serveo_alias}..."
                        pkill -f "serveo.net" 2>/dev/null || true
                        rm -f "$SERVEO_LOG"
                        nohup ssh -i "$SERVEO_KEY" -T -N \
                            -o StrictHostKeyChecking=accept-new \
                            -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
                            -o ServerAliveInterval=10 \
                            -o ServerAliveCountMax=3 \
                            -o ExitOnForwardFailure=yes \
                            -o ConnectTimeout=10 \
                            -R "${serveo_alias}:22:127.0.0.1:8022" serveo.net > "$SERVEO_LOG" 2>&1 &
                        echo $! > "$SERVEO_STATE"
                        echo "$serveo_alias" > "$PREFIX/tmp/asl-serveo-active.alias" 2>/dev/null || true
                        sleep 4
                    fi
                fi
                if ! serveo_running; then
                    echo "Error: Serveo tunnel failed to connect. Log output:"
                    cat "$SERVEO_LOG" 2>/dev/null
                    return 1
                fi
            fi
            serveo_status
            ;;
        stop)
            if serveo_running; then
                local pid
                pid=$(cat "$SERVEO_STATE" 2>/dev/null)
                [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || pkill -f "serveo.net" 2>/dev/null || true
                rm -f "$SERVEO_STATE" "$SERVEO_LOG"
                echo "[✓] Serveo tunnel stopped."
            else
                rm -f "$SERVEO_STATE"
                echo "[*] Serveo tunnel is not running."
            fi
            ;;
        status|"")
            serveo_status
            ;;
    esac
}

serveo_status() {
    if serveo_running; then
        echo "Serveo Tunnel: RUNNING (Persistent Fixed Key)"
        local s_alias user
        user=$(whoami 2>/dev/null || echo "user")
        if [ -f "$PREFIX/tmp/asl-serveo-active.alias" ] && [ -s "$PREFIX/tmp/asl-serveo-active.alias" ]; then
            s_alias=$(cat "$PREFIX/tmp/asl-serveo-active.alias" 2>/dev/null)
        else
            s_alias=$(get_serveo_alias)
        fi
        echo "    Connect:  ssh -J serveo.net ${user}@${s_alias}"
        echo "    Authentication: SSH key or configured remote credential"
    else
        echo "Serveo Tunnel: STOPPED"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    serveo_control "$@"
fi
