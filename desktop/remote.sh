#!/bin/bash
# ASL: Remote Access Bridge (Serveo, Ngrok Multi-Token, Oracle VPS & LAN SSH)
# Modular dispatcher - sources individual tunnel modules from remote/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"
source "$SCRIPT_DIR/desktop/remote/lan.sh"
source "$SCRIPT_DIR/desktop/remote/serveo.sh"
source "$SCRIPT_DIR/desktop/remote/oracle.sh"
source "$SCRIPT_DIR/desktop/remote/ngrok.sh"
source "$SCRIPT_DIR/desktop/remote/keys.sh"
source "$SCRIPT_DIR/desktop/remote/autoconnect.sh"

gui_control() {
    local s_alias user host
    user=$(whoami 2>/dev/null || echo "user")
    host=$(lan_host_ip)
    s_alias=$(get_serveo_alias)
    echo "=== ASL Remote Desktop (VNC/X11) Tunnel Guide ==="
    echo "To access the ASL graphical desktop remotely over SSH tunnel:"
    echo ""
    echo "1. LAN SSH (Port 8022 + Local VNC Forwarding):"
    echo "   ssh -L 5900:127.0.0.1:5900 -p 8022 ${user}@${host}"
    echo ""
    echo "2. Serveo Remote Jump Host Forwarding:"
    echo "   ssh -L 5900:127.0.0.1:5900 -J serveo.net ${user}@${s_alias}"
    echo ""
    local ng_url ng_host ng_port
    ng_url=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -oE 'tcp://[^"]+' | head -1)
    if [ -n "$ng_url" ]; then
        ng_host=$(echo "$ng_url" | sed -E 's|tcp://([^:]+):.*|\1|')
        ng_port=$(echo "$ng_url" | sed -E 's|tcp://[^:]+:([0-9]+)|\1|')
        echo "3. Ngrok TCP Forwarding:"
        echo "   ssh -L 5900:127.0.0.1:5900 -p ${ng_port} ${user}@${ng_host}"
        echo ""
    fi
    echo "After establishing the SSH tunnel, connect your VNC viewer (RealVNC/TigerVNC) to 'localhost:5900'."
}

start_all() {
    echo "[*] Initializing ASL Remote Bridge Services..."
    lan_control start
    echo ""
    if [ -f "$ORACLE_KEY" ]; then
        oracle_control start || true
        echo ""
    fi
    serveo_control start
    echo ""
    echo ""
    autoconnect_control start
    echo ""
    echo "[✓] All remote connection bridges initialized!"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    TARGET="${1:-status}"
    shift || true

    case "$TARGET" in
        all|start-all) start_all ;;
        password|pass) password_control "$@" ;;
        lan) lan_control "$@" ;;
        key|keys|pubkey) key_control "$@" ;;
        oracle|vps) oracle_control "$@" ;;
        serveo) serveo_control "$@" ;;
        ngrok) ngrok_control "$@" ;;
        gui|desktop-tunnel) gui_control ;;
        autoconnect) autoconnect_control "$@" ;;
        autoconnect-daemon) autoconnect_daemon ;;
        help|-h|--help)
            echo "=== ASL Remote Access Management ==="
            echo "Usage: asl remote <subcommand> [args]"
            echo ""
            echo "Subcommands:"
            echo "  all                  Start LAN SSH, Oracle VPS, Serveo, and Auto-Connect daemon"
            echo "  password set <pass>  Set remote SSH password"
            echo "  password clear       Remove remote SSH password"
            echo "  lan [start|stop]     Control LAN SSH server on port 8022"
            echo "  oracle [start|stop]  Control dedicated Oracle Cloud VPS tunnel (130.210.19.7)"
            echo "  serveo [start|stop]  Control persistent Serveo jump-host tunnel"
            echo "  serveo alias <name>  Set custom Serveo subdomain/alias"
            echo "  ngrok add-token <t>  Add Ngrok authtoken to pool"
            echo "  ngrok list-tokens    List tokens and quota statuses"
            echo "  ngrok rotate         Rotate to next active token in pool"
            echo "  ngrok reset          Reset quota-exhausted status"
            echo "  keys [list|add|import-github <user>] Manage SSH public keys"
            echo "  gui                  Show remote desktop/VNC tunnel forwarding commands"
            echo "  autoconnect          Start 24/7 auto-reconnect daemon (Wake-lock enabled)"
            echo "  status               Display all active remote bridges"
            ;;
        status|"")
            echo "=== ASL Remote Bridge Status ==="
            if [ -n "$(get_password)" ]; then
                echo "Remote password: configured"
            else
                echo "Remote password: not configured"
            fi
            echo ""
            lan_control status
            echo ""
            oracle_control status
            echo ""
            serveo_control status
            echo ""
            ngrok_control status
            echo ""
            autoconnect_control status
            ;;
        *)
            echo "Usage: asl remote [all|password|lan|keys|serveo|ngrok|autoconnect] [start|stop|status]"
            exit 1
            ;;
    esac
fi
