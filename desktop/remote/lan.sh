#!/bin/bash
# ASL Remote Access - LAN SSH Control

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"

lan_host_ip() {
    local ip
    ip=$(ip -o -4 addr show 2>/dev/null | awk '$2 != "lo" {sub(/\/.*/, "", $4); print $4; exit}')
    [ -n "$ip" ] || ip=$(ifconfig 2>/dev/null | awk '/inet / && !/127.0.0.1/ {sub(/addr:/, ""); print $2; exit}')
    printf '%s' "${ip:-127.0.0.1}"
}

lan_control() {
    local action="${1:-status}"
    local auth_desc="SSH key only"
    if [ -s "$PASS_FILE" ] || [ -n "$(get_password 2>/dev/null)" ]; then
        auth_desc="SSH key or configured remote password"
    fi

    case "$action" in
        start)
            ensure_host_sshd || { echo "Error: Failed to start host SSH daemon."; return 1; }
            local host
            host=$(lan_host_ip)
            echo "[✓] LAN SSH Server active on port 8022."
            echo "    Connect command: ssh -p 8022 $(whoami)@$host"
            echo "    Authentication:  $auth_desc"
            ;;
        stop)
            pkill -f "sshd" 2>/dev/null || su -c "pkill -f sshd" 2>/dev/null || asl_exec "pkill -f sshd" 2>/dev/null || true
            echo "[✓] LAN SSH Server stopped."
            ;;
        status|"")
            if asl_is_sshd_running; then
                echo "LAN SSH:      RUNNING (port 8022)"
                echo "    Connect:  ssh -p 8022 $(whoami)@$(lan_host_ip)"
                echo "    Authentication: $auth_desc"
            else
                echo "LAN SSH:      STOPPED"
            fi
            ;;
    esac
}
