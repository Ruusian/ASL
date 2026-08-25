#!/bin/bash
# ASL Remote Access - Oracle Cloud VPS Dedicated Reverse Tunnel

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"

ORACLE_CONF="$CONFIG_DIR/oracle_vps.conf"
ORACLE_LOG="$PREFIX/tmp/oracle-vps.log"
ORACLE_STATE="$PREFIX/tmp/asl-oracle.state"

load_oracle_config() {
    ORACLE_KEY="$HOME/.ssh/oracle_vps.key"
    ORACLE_HOST=""
    ORACLE_USER="ubuntu"
    ORACLE_PORT="2222"

    if [ -f "$ORACLE_CONF" ]; then
        local key_val host_val user_val port_val
        key_val=$(grep -E '^ORACLE_KEY=' "$ORACLE_CONF" 2>/dev/null | cut -d'=' -f2-)
        host_val=$(grep -E '^ORACLE_HOST=' "$ORACLE_CONF" 2>/dev/null | cut -d'=' -f2-)
        user_val=$(grep -E '^ORACLE_USER=' "$ORACLE_CONF" 2>/dev/null | cut -d'=' -f2-)
        port_val=$(grep -E '^ORACLE_PORT=' "$ORACLE_CONF" 2>/dev/null | cut -d'=' -f2-)

        [ -n "$key_val" ] && ORACLE_KEY="$key_val"
        [ -n "$host_val" ] && ORACLE_HOST="$host_val"
        [ -n "$user_val" ] && ORACLE_USER="$user_val"
        [ -n "$port_val" ] && ORACLE_PORT="$port_val"
    fi

    # Environment variables override config file
    [ -n "${ASL_ORACLE_KEY:-}" ] && ORACLE_KEY="$ASL_ORACLE_KEY"
    [ -n "${ASL_ORACLE_HOST:-}" ] && ORACLE_HOST="$ASL_ORACLE_HOST"
    [ -n "${ASL_ORACLE_USER:-}" ] && ORACLE_USER="$ASL_ORACLE_USER"
    [ -n "${ASL_ORACLE_PORT:-}" ] && ORACLE_PORT="$ASL_ORACLE_PORT"
}

save_oracle_config() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    cat <<EOF > "$ORACLE_CONF"
ORACLE_HOST=${ORACLE_HOST}
ORACLE_USER=${ORACLE_USER}
ORACLE_PORT=${ORACLE_PORT}
ORACLE_KEY=${ORACLE_KEY}
EOF
    chmod 600 "$ORACLE_CONF"
}

oracle_setup_wizard() {
    echo "=================================================="
    echo "       ASL Oracle / VPS Remote Setup Wizard       "
    echo "=================================================="
    echo "Configure a dedicated remote VPS reverse SSH relay."
    echo ""

    local input_host input_user input_port input_key_choice

    # 1. Host IP / Domain
    while [ -z "$input_host" ]; do
        read -r -p "Enter Oracle / VPS Hostname or IP address: " input_host
        input_host=$(echo "$input_host" | tr -d '[:space:]')
        if [ -z "$input_host" ]; then
            echo "[!] Hostname / IP cannot be empty."
        fi
    done
    ORACLE_HOST="$input_host"

    # 2. SSH User
    read -r -p "Enter VPS SSH Username [default: ubuntu]: " input_user
    input_user=$(echo "$input_user" | tr -d '[:space:]')
    ORACLE_USER="${input_user:-ubuntu}"

    # 3. Remote Port
    read -r -p "Enter Remote SSH Forwarding Port [default: 2222]: " input_port
    input_port=$(echo "$input_port" | tr -d '[:space:]')
    ORACLE_PORT="${input_port:-2222}"

    # 4. SSH Key Management
    echo ""
    echo "SSH Private Key Configuration:"
    echo "  1) Generate a new dedicated ED25519 SSH keypair (Recommended)"
    echo "  2) Specify path to an existing private key file"
    echo "  3) Paste private key contents directly"
    echo "  4) Keep existing key if present ($ORACLE_KEY)"
    read -r -p "Select key setup option [1-4, default: 1]: " input_key_choice
    input_key_choice=$(echo "$input_key_choice" | tr -d '[:space:]')
    input_key_choice="${input_key_choice:-1}"

    case "$input_key_choice" in
        1)
            mkdir -p "$HOME/.ssh" 2>/dev/null || true
            rm -f "$ORACLE_KEY" "$ORACLE_KEY.pub" 2>/dev/null || true
            ssh-keygen -t ed25519 -f "$ORACLE_KEY" -N "" -C "asl-oracle-vps" >/dev/null 2>&1
            chmod 600 "$ORACLE_KEY"
            echo "[✓] Dedicated SSH keypair generated at $ORACLE_KEY"
            if [ -f "$ORACLE_KEY.pub" ]; then
                echo ""
                echo "========================================================"
                echo " IMPORTANT: Add this public key to your VPS authorized_keys:"
                echo " File on VPS: ~/.ssh/authorized_keys"
                echo "--------------------------------------------------------"
                cat "$ORACLE_KEY.pub"
                echo "--------------------------------------------------------"
                echo "========================================================"
                echo ""
            fi
            ;;
        2)
            local key_path=""
            read -r -p "Enter full path to private key file: " key_path
            key_path="${key_path/#\~/$HOME}"
            if [ -f "$key_path" ]; then
                mkdir -p "$HOME/.ssh" 2>/dev/null || true
                cp -f "$key_path" "$ORACLE_KEY"
                chmod 600 "$ORACLE_KEY"
                echo "[✓] Private key imported -> $ORACLE_KEY"
            else
                echo "[!] File not found at '$key_path'. Key configuration aborted."
            fi
            ;;
        3)
            echo "Paste your private key below (end with an empty line or EOF):"
            local key_content="" line=""
            while IFS= read -r line; do
                [ -z "$line" ] && [ -n "$key_content" ] && break
                key_content="${key_content}${line}"$'\n'
            done
            if printf '%s\n' "$key_content" | grep -q "PRIVATE KEY"; then
                mkdir -p "$HOME/.ssh" 2>/dev/null || true
                printf '%s' "$key_content" > "$ORACLE_KEY"
                chmod 600 "$ORACLE_KEY"
                echo "[✓] Private key saved -> $ORACLE_KEY"
            else
                echo "[!] Invalid private key content provided."
            fi
            ;;
        4|*)
            if [ -f "$ORACLE_KEY" ]; then
                echo "[✓] Retained existing key at $ORACLE_KEY"
            else
                echo "[!] Warning: No existing key found at $ORACLE_KEY."
            fi
            ;;
    esac

    save_oracle_config
    echo ""
    echo "[✓] VPS configuration saved successfully to $ORACLE_CONF!"
    echo ""
    oracle_status
}

load_oracle_config

oracle_running() {
    load_oracle_config
    [ -z "$ORACLE_HOST" ] && return 1
    if [ -f "$ORACLE_LOG" ] && [ "$(wc -c < "$ORACLE_LOG" 2>/dev/null || echo 0)" -gt 102400 ]; then
        tail -n 200 "$ORACLE_LOG" > "$ORACLE_LOG.tmp" 2>/dev/null && mv "$ORACLE_LOG.tmp" "$ORACLE_LOG" 2>/dev/null || true
    fi
    if [ -f "$ORACLE_STATE" ] && [ -n "$ORACLE_HOST" ] && pgrep -f "ssh.*${ORACLE_HOST}" >/dev/null 2>&1; then
        if tail -n 10 "$ORACLE_LOG" 2>/dev/null | grep -qE "Permission denied|Connection closed|Connection refused|Host key verification failed|kex_exchange_identification|remote port forwarding failed|Broken pipe|Network is unreachable|Software caused connection abort|Connection reset|Connection timed out"; then
            pkill -9 -f "ssh.*${ORACLE_HOST}" 2>/dev/null || true
            return 1
        fi
        return 0
    fi
    return 1
}

oracle_control() {
    load_oracle_config
    local action="${1:-status}"
    shift || true

    case "$action" in
        start)
            ensure_host_sshd
            if [ -z "$ORACLE_HOST" ]; then
                if [ -t 0 ]; then
                    oracle_setup_wizard || return 1
                else
                    echo "Error: Oracle VPS host is not configured."
                    echo "Run 'asl remote oracle setup' or 'asl remote oracle config host <ip>' first."
                    return 1
                fi
            fi
            if [ ! -f "$ORACLE_KEY" ]; then
                if [ -t 0 ]; then
                    echo "[!] Oracle VPS private key missing at $ORACLE_KEY."
                    read -r -p "Generate a new ED25519 keypair now? [Y/n]: " gen_confirm
                    if [[ "$gen_confirm" =~ ^[Nn] ]]; then
                        echo "Run 'asl remote oracle add-key <file>' to provide a key."
                        return 1
                    else
                        oracle_control gen-key
                    fi
                else
                    echo "Error: Oracle VPS private key not found at $ORACLE_KEY"
                    echo "Use 'asl remote oracle add-key <key_file>' or 'asl remote oracle gen-key' to set up a key."
                    return 1
                fi
            fi
            touch "$ORACLE_STATE"
            if oracle_running; then
                echo "[*] Oracle VPS dedicated tunnel (${ORACLE_PORT} -> 8022) is already running."
            else
                # Kill only tunnel SSH processes (-N flag), not interactive sessions
                [ -n "$ORACLE_HOST" ] && pkill -f "ssh.*-N.*${ORACLE_HOST}" 2>/dev/null || true
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
                nohup ssh -i "$ORACLE_KEY" -T -N \
                    -o StrictHostKeyChecking=accept-new \
                    -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
                    -o ServerAliveInterval=10 \
                    -o ServerAliveCountMax=3 \
                    -o ExitOnForwardFailure=yes \
                    -o ConnectTimeout=10 \
                    -R "*:${ORACLE_PORT}:127.0.0.1:8022" \
                    "${ORACLE_USER}@${ORACLE_HOST}" > "$ORACLE_LOG" 2>&1 &
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
                [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || ([ -n "$ORACLE_HOST" ] && pkill -f "ssh.*-N.*${ORACLE_HOST}" 2>/dev/null) || true
                rm -f "$ORACLE_STATE" "$ORACLE_LOG"
                echo "[✓] Oracle VPS tunnel stopped."
            else
                rm -f "$ORACLE_STATE"
                echo "[*] Oracle VPS tunnel is not running."
            fi
            ;;
        setup|init|wizard)
            oracle_setup_wizard
            ;;
        config|set-config|set)
            local subopt="${1:-show}"
            local val="${2:-}"
            case "$subopt" in
                host|set-host)
                    if [ -z "$val" ]; then
                        echo "Usage: asl remote oracle config host <ip_or_domain>"
                        return 1
                    fi
                    ORACLE_HOST="$val"
                    save_oracle_config
                    echo "[✓] Oracle VPS host set to: $ORACLE_HOST"
                    ;;
                user|set-user)
                    if [ -z "$val" ]; then
                        echo "Usage: asl remote oracle config user <username>"
                        return 1
                    fi
                    ORACLE_USER="$val"
                    save_oracle_config
                    echo "[✓] Oracle VPS user set to: $ORACLE_USER"
                    ;;
                port|set-port)
                    if [ -z "$val" ] || [[ ! "$val" =~ ^[0-9]+$ ]]; then
                        echo "Usage: asl remote oracle config port <port_number>"
                        return 1
                    fi
                    ORACLE_PORT="$val"
                    save_oracle_config
                    echo "[✓] Oracle VPS remote port set to: $ORACLE_PORT"
                    ;;
                key-path)
                    if [ -z "$val" ]; then
                        echo "Usage: asl remote oracle config key-path <file_path>"
                        return 1
                    fi
                    ORACLE_KEY="$val"
                    save_oracle_config
                    echo "[✓] Oracle VPS key path set to: $ORACLE_KEY"
                    ;;
                show|*)
                    echo "=== Oracle VPS Configuration ==="
                    echo "  Host:     ${ORACLE_HOST:-<not configured>}"
                    echo "  User:     $ORACLE_USER"
                    echo "  Port:     $ORACLE_PORT"
                    echo "  Key Path: $ORACLE_KEY"
                    if [ -f "$ORACLE_KEY" ]; then
                        echo "  Key File: PRESENT ($(wc -c < "$ORACLE_KEY") bytes)"
                    else
                        echo "  Key File: MISSING"
                    fi
                    ;;
            esac
            ;;
        add-key|set-key|import-key)
            local input_key="${1:-}"
            if [ -z "$input_key" ]; then
                echo "Usage: asl remote oracle add-key <path_to_key_file | \"key_content_string\">"
                return 1
            fi
            mkdir -p "$HOME/.ssh" 2>/dev/null || true
            if [ -f "$input_key" ]; then
                cp -f "$input_key" "$ORACLE_KEY"
                chmod 600 "$ORACLE_KEY"
                echo "[✓] Private key imported from file '$input_key' -> $ORACLE_KEY"
            elif printf '%s\n' "$input_key" | grep -q "PRIVATE KEY"; then
                printf '%s\n' "$input_key" > "$ORACLE_KEY"
                chmod 600 "$ORACLE_KEY"
                echo "[✓] Inline private key content saved -> $ORACLE_KEY"
            else
                echo "Error: Parameter must be an existing file path or a valid SSH private key string containing 'PRIVATE KEY'."
                return 1
            fi
            save_oracle_config
            ;;
        gen-key|create-key)
            mkdir -p "$HOME/.ssh" 2>/dev/null || true
            if [ -f "$ORACLE_KEY" ]; then
                echo "[!] Oracle key file already exists at $ORACLE_KEY."
                echo "    Overwriting will replace your current private key."
            fi
            echo "[*] Generating dedicated ED25519 SSH keypair for Oracle VPS..."
            rm -f "$ORACLE_KEY" "$ORACLE_KEY.pub" 2>/dev/null || true
            ssh-keygen -t ed25519 -f "$ORACLE_KEY" -N "" -C "asl-oracle-vps" >/dev/null 2>&1
            chmod 600 "$ORACLE_KEY"
            save_oracle_config
            echo "[✓] Private key created at: $ORACLE_KEY"
            if [ -f "$ORACLE_KEY.pub" ]; then
                echo ""
                echo "Public key (Add this to your VPS ~/.ssh/authorized_keys):"
                echo "--------------------------------------------------------"
                cat "$ORACLE_KEY.pub"
                echo "--------------------------------------------------------"
            fi
            ;;
        remove-key|clear-key|delete-key)
            [ -n "$ORACLE_HOST" ] && pkill -f "ssh.*${ORACLE_HOST}" 2>/dev/null || true
            rm -f "$ORACLE_STATE" "$ORACLE_LOG" "$ORACLE_KEY" "$ORACLE_KEY.pub"
            echo "[✓] Oracle VPS private key deleted."
            ;;
        show-key|view-key)
            if [ -f "$ORACLE_KEY" ]; then
                echo "=== Oracle VPS Private Key Info ($ORACLE_KEY) ==="
                ssh-keygen -l -f "$ORACLE_KEY" 2>/dev/null || cat "$ORACLE_KEY"
                if [ -f "$ORACLE_KEY.pub" ]; then
                    echo "--- Public Key ---"
                    cat "$ORACLE_KEY.pub"
                fi
            else
                echo "[!] No Oracle VPS private key found at $ORACLE_KEY"
            fi
            ;;
        pubkey|push-pubkey|add-pubkey)
            local key_to_push="${1:-}"
            if [ -z "$ORACLE_HOST" ]; then
                echo "Error: Oracle VPS host not configured. Run 'asl remote oracle config host <ip>' first."
                return 1
            fi
            if [ ! -f "$ORACLE_KEY" ]; then
                echo "Error: Private key missing ($ORACLE_KEY). Add a private key first using 'asl remote oracle add-key'."
                return 1
            fi
            if [ -z "$key_to_push" ]; then
                local host_pub="$HOME/.ssh/id_ed25519.pub"
                [ -f "$host_pub" ] || host_pub="$HOME/.ssh/id_rsa.pub"
                if [ ! -f "$host_pub" ]; then
                    echo "[*] Generating default host SSH keypair..."
                    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "asl-termux-host" >/dev/null 2>&1
                    host_pub="$HOME/.ssh/id_ed25519.pub"
                fi
                key_to_push=$(cat "$host_pub" 2>/dev/null)
            elif [ -f "$key_to_push" ]; then
                key_to_push=$(cat "$key_to_push" 2>/dev/null)
            fi

            if [ -z "$key_to_push" ]; then
                echo "Error: No public key content found to push."
                return 1
            fi

            echo "[*] Pushing SSH public key to Oracle VPS (${ORACLE_USER}@${ORACLE_HOST})..."
            echo "$key_to_push" | ssh -i "$ORACLE_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${ORACLE_USER}@${ORACLE_HOST}" \
                "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "[✓] Public key successfully pushed to Oracle VPS ~/.ssh/authorized_keys"
            else
                echo "Error: Failed to push public key to Oracle VPS."
                return 1
            fi
            ;;
        remove|delete|clear|reset)
            [ -n "$ORACLE_HOST" ] && pkill -f "ssh.*${ORACLE_HOST}" 2>/dev/null || true
            rm -f "$ORACLE_STATE" "$ORACLE_LOG" "$ORACLE_KEY" "$ORACLE_KEY.pub" "$ORACLE_CONF"
            echo "[✓] Oracle VPS configuration and keys completely removed from ASL."
            ;;
        status|"")
            oracle_status
            ;;
        *)
            echo "=== ASL Oracle Remote VPS Management ==="
            echo "Usage: asl remote oracle <action> [args]"
            echo ""
            echo "Setup & Wizard:"
            echo "  setup               Interactive setup wizard for VPS connection"
            echo ""
            echo "Tunnel Control:"
            echo "  start               Start persistent Oracle VPS reverse tunnel"
            echo "  stop                Stop Oracle VPS reverse tunnel"
            echo "  status              Show Oracle VPS tunnel status"
            echo ""
            echo "Configuration:"
            echo "  config              Display current VPS configuration"
            echo "  config host <ip>    Set Oracle VPS host IP or domain"
            echo "  config user <name>  Set Oracle VPS SSH user (default: ubuntu)"
            echo "  config port <port>  Set remote forwarding port (default: 2222)"
            echo ""
            echo "Key Management:"
            echo "  add-key <path|str>  Import SSH private key for Oracle VPS connection"
            echo "  gen-key             Generate a new dedicated SSH keypair"
            echo "  show-key            Display private key info and public key"
            echo "  remove-key          Delete the stored Oracle VPS private key"
            echo "  push-pubkey [key]   Push public key to Oracle VPS authorized_keys"
            echo ""
            echo "Removal:"
            echo "  remove / delete     Completely remove Oracle VPS configuration and keys"
            ;;
    esac
}

oracle_status() {
    load_oracle_config
    if [ -z "$ORACLE_HOST" ]; then
        echo "Oracle VPS Tunnel: NOT CONFIGURED"
        echo "    Run 'asl remote oracle setup' or 'asl remote oracle config host <ip>' to configure."
        return 0
    fi
    if oracle_running; then
        echo "Oracle VPS Tunnel: RUNNING (Dedicated Always-On Private Relay)"
        echo "    Host:           ${ORACLE_HOST} (User: ${ORACLE_USER}, Port: ${ORACLE_PORT})"
        echo "    Connect:        ssh -J ${ORACLE_USER}@${ORACLE_HOST} -p ${ORACLE_PORT} $(whoami)@127.0.0.1"
        echo "    Authentication: SSH key ($ORACLE_KEY)"
    else
        echo "Oracle VPS Tunnel: STOPPED"
        echo "    Host Configured: ${ORACLE_HOST} (${ORACLE_USER}@${ORACLE_HOST}:${ORACLE_PORT})"
        if [ -f "$ORACLE_KEY" ]; then
            echo "    Private Key:     PRESENT ($ORACLE_KEY)"
        else
            echo "    Private Key:     MISSING ($ORACLE_KEY)"
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    oracle_control "$@"
fi
