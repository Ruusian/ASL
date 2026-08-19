#!/bin/bash
# ASL: Remote Access Bridge (Serveo, Ngrok Multi-Token, Tailscale & LAN SSH)

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

CONFIG_DIR="$HOME/.asl"
mkdir -p "$CONFIG_DIR" "$HOME/.ssh" 2>/dev/null || true
chmod 700 "$CONFIG_DIR" "$HOME/.ssh" 2>/dev/null || true
# Fix ownership if created by root
if [ -d "$CONFIG_DIR" ] && [ ! -w "$CONFIG_DIR" ]; then
    su -c "chown $(id -u):$(id -g) '$CONFIG_DIR'" 2>/dev/null || true
fi

PASS_FILE="$CONFIG_DIR/remote_password"

get_password() {
    if [ -f "$PASS_FILE" ]; then
        cat "$PASS_FILE" 2>/dev/null
    fi
}

set_password() {
    local new_pass="${1:-}"
    if [ -z "$new_pass" ] || [[ "$new_pass" == *$'\n'* || "$new_pass" == *$'\r'* ]]; then
        echo "Error: Password cannot be empty or contain newlines."
        return 1
    fi
    if ! printf '%s\n%s\n' "$new_pass" "$new_pass" | passwd >/dev/null 2>&1; then
        echo "Error: Could not update the host password."
        return 1
    fi
    if is_mounted; then
        local pass_b64
        pass_b64=$(printf '%s' "$new_pass" | base64 | tr -d '\n')
        if ! asl_exec "pass=\$(printf '%s' '$pass_b64' | base64 -d); printf '%s\n%s\n' \"\$pass\" \"\$pass\" | passwd >/dev/null 2>&1"; then
            echo "Error: Host password changed, but the chroot password update failed."
            return 1
        fi
    fi
    # Store only a non-reversible hash so the "configured" status survives
    # without keeping the cleartext password on disk (chroot OS passwd is the
    # real credential store).
    printf '%s' "$new_pass" | sha256sum 2>/dev/null | cut -d' ' -f1 > "$PASS_FILE" || : > "$PASS_FILE"
    chmod 600 "$PASS_FILE"
    echo "[✓] ASL Remote SSH password updated."
}

ensure_host_sshd() {
    mkdir -p "$PREFIX/etc/ssh"
    if [ ! -f "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]; then
        ssh-keygen -A >/dev/null 2>&1 || return 1
    fi
    local pass_opts="-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no"
    if [ -s "$PASS_FILE" ]; then
        pass_opts="-o PasswordAuthentication=yes -o KbdInteractiveAuthentication=yes"
    fi
    if ! pgrep -f "sshd -p 8022" >/dev/null 2>&1 && ! su -c "pgrep -f 'sshd -p 8022'" >/dev/null 2>&1; then
        echo "[*] Starting Termux host SSH daemon on port 8022..."
        sshd -p 8022 $pass_opts 2>/dev/null || return 1
    fi
    pgrep -f "sshd -p 8022" >/dev/null 2>&1 || su -c "pgrep -f 'sshd -p 8022'" >/dev/null 2>&1 || return 1
}

# --- 1. Fixed Password Management -------------------------------------------
password_control() {
    local action="${1:-show}"
    case "$action" in
        set|change)
            local new_p="${2:-}"
            if [ -z "$new_p" ]; then
                echo "Usage: asl remote password set <new_password>"
                return 1
            fi
            set_password "$new_p"
            ;;
        show|*)
            if [ -n "$(get_password)" ]; then
                echo "A remote password is configured."
            else
                echo "No remote password is configured; key-based access is required."
            fi
            echo "Set a password using: asl remote password set <new_password>"
            ;;
    esac
}

# --- 2. LAN SSH Control -----------------------------------------------------
lan_host_ip() {
    local ip
    ip=$(ip -o -4 addr show 2>/dev/null | awk '$2 != "lo" {sub(/\/.*/, "", $4); print $4; exit}')
    [ -n "$ip" ] || ip=$(ifconfig 2>/dev/null | awk '/inet / && !/127.0.0.1/ {sub(/addr:/, ""); print $2; exit}')
    printf '%s' "${ip:-127.0.0.1}"
}

lan_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            ensure_host_sshd || { echo "Error: Failed to start host SSH in key-only mode."; return 1; }
            local host
            host=$(lan_host_ip)
            echo "[✓] LAN SSH Server active on port 8022."
            echo "    Connect command: ssh -p 8022 $(whoami)@$host"
            echo "    Authentication:  SSH key only"
            ;;
        stop)
            pkill -f "sshd -p 8022" 2>/dev/null || true
            echo "[✓] LAN SSH Server stopped."
            ;;
        status|"")
            if pgrep -f "sshd -p 8022" >/dev/null 2>&1 || su -c "pgrep -f 'sshd -p 8022'" >/dev/null 2>&1; then
                echo "LAN SSH:      RUNNING (port 8022)"
                echo "    Connect:  ssh -p 8022 $(whoami)@$(lan_host_ip)"
                echo "    Authentication: SSH key only"
            else
                echo "LAN SSH:      STOPPED"
            fi
            ;;
    esac
}

# --- 3. Serveo Tunnel (Fixed SSH Key) ---------------------------------------
SERVEO_KEY="$HOME/.ssh/id_serveo_asl"
SERVEO_LOG="$PREFIX/tmp/serveo.log"
SERVEO_STATE="$PREFIX/tmp/asl-serveo.state"
SERVEO_ALIAS_FILE="$CONFIG_DIR/serveo_alias.txt"

get_serveo_alias() {
    if [ -f "$SERVEO_ALIAS_FILE" ] && [ -s "$SERVEO_ALIAS_FILE" ]; then
        cat "$SERVEO_ALIAS_FILE" 2>/dev/null
    elif [ -n "${ASL_SERVEO_ALIAS:-}" ]; then
        echo "$ASL_SERVEO_ALIAS"
    else
        echo "asl-$(whoami 2>/dev/null || echo user)"
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
    [ -f "$SERVEO_STATE" ] && pgrep -f "serveo.net" >/dev/null 2>&1 && \
        ! grep -qE "remote port forwarding failed|Permission denied|Connection closed|Connection refused|Host key verification failed|kex_exchange_identification" "$SERVEO_LOG" 2>/dev/null
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
                nohup ssh -i "$SERVEO_KEY" -T -N -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o ConnectTimeout=15 -R "${serveo_alias}:22:localhost:8022" serveo.net > "$SERVEO_LOG" 2>&1 &
                echo $! > "$SERVEO_STATE"
                sleep 4
                if ! serveo_running; then
                    if grep -q "remote port forwarding failed" "$SERVEO_LOG" 2>/dev/null; then
                        local dev_suffix
                        dev_suffix=$(sha256sum /proc/sys/kernel/random/boot_id 2>/dev/null | cut -c1-4 || echo "$RANDOM")
                        serveo_alias="${serveo_alias}-${dev_suffix}"
                        echo "[!] Primary alias in use. Retrying with device fallback alias: ${serveo_alias}..."
                        pkill -f "serveo.net" 2>/dev/null || true
                        rm -f "$SERVEO_LOG"
                        nohup ssh -i "$SERVEO_KEY" -T -N -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o ConnectTimeout=15 -R "${serveo_alias}:22:localhost:8022" serveo.net > "$SERVEO_LOG" 2>&1 &
                        echo $! > "$SERVEO_STATE"
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
        s_alias=$(get_serveo_alias)
        echo "    Connect:  ssh -J serveo.net ${user}@${s_alias}"
        echo "    Authentication: SSH key or configured remote credential"
    else
        echo "Serveo Tunnel: STOPPED"
    fi
}

# --- 4. Ngrok Tunnel (Multi-Token Pool, Quota Auto-Rotation & Serveo Backup) ---
NGROK_TOKENS_FILE="$CONFIG_DIR/ngrok_tokens.txt"
NGROK_EXHAUSTED_FILE="$CONFIG_DIR/ngrok_exhausted.txt"
NGROK_LOG="$PREFIX/tmp/ngrok.log"
NGROK_STATE="$PREFIX/tmp/asl-ngrok.state"
NGROK_CURR_TOKEN="$PREFIX/tmp/asl-ngrok-current.token"

ngrok_running() {
    [ -f "$NGROK_STATE" ] || return 1
    pgrep -f "ngrok.*tcp" >/dev/null 2>&1 || return 1
    if grep -qE "ERR_NGROK|quota|rate limit|too many connections|session closed|authentication failed" "$NGROK_LOG" 2>/dev/null; then
        return 1
    fi
    grep -qE '"public_url"\s*:\s*"tcp://' <(curl -s --max-time 3 http://127.0.0.1:4040/api/tunnels 2>/dev/null)
}

ngrok_wait_registered() {
    local tries=0
    while [ "$tries" -lt 6 ]; do
        if ngrok_running; then return 0; fi
        if grep -qE "ERR_NGROK|authentication failed|quota|rate limit|Error:" "$NGROK_LOG" 2>/dev/null; then return 1; fi
        sleep 1
        tries=$((tries + 1))
    done
    return 1
}

mark_ngrok_token_exhausted() {
    local tok="$1"
    [ -n "$tok" ] || return 0
    mkdir -p "$CONFIG_DIR"
    if ! grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
        echo "$tok" >> "$NGROK_EXHAUSTED_FILE"
        chmod 600 "$NGROK_EXHAUSTED_FILE" 2>/dev/null || true
    fi
}

ngrok_add_token() {
    local token="$1"
    if [ -z "$token" ] || [[ ! "$token" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "Error: Token must be non-empty and contain valid characters (letters, digits, underscores, dashes, dots)."
        return 1
    fi
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    if ! grep -qF "$token" "$NGROK_TOKENS_FILE" 2>/dev/null; then
        echo "$token" >> "$NGROK_TOKENS_FILE"
        chmod 600 "$NGROK_TOKENS_FILE"
        echo "[✓] Added ngrok auth token to token pool."
    else
        echo "[*] Token is already in the token pool."
    fi
}

ngrok_remove_token() {
    local token="$1"
    if [ -z "$token" ]; then
        echo "Usage: asl remote ngrok remove-token <token>"
        return 1
    fi
    if [ -f "$NGROK_TOKENS_FILE" ]; then
        grep -vF "$token" "$NGROK_TOKENS_FILE" > "$NGROK_TOKENS_FILE.tmp" 2>/dev/null || true
        mv "$NGROK_TOKENS_FILE.tmp" "$NGROK_TOKENS_FILE" 2>/dev/null || true
        echo "[✓] Removed ngrok token from pool."
    fi
}

ngrok_list_tokens() {
    echo "=== Registered Ngrok Token Pool ==="
    if [ -f "$NGROK_TOKENS_FILE" ] && [ -s "$NGROK_TOKENS_FILE" ]; then
        local count=0
        while IFS= read -r tok || [ -n "$tok" ]; do
            [ -n "$tok" ] || continue
            count=$((count + 1))
            local status="ACTIVE"
            if grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                status="EXHAUSTED / RATE-LIMITED"
            fi
            local len=${#tok}
            local masked="$tok"
            if [ "$len" -gt 10 ]; then
                masked="${tok:0:6}...${tok: -4}"
            fi
            echo "  $count. $masked  [$status]"
        done < "$NGROK_TOKENS_FILE"
    else
        echo "(No ngrok auth tokens registered yet. Add using 'asl remote ngrok add-token <token>')"
    fi
}

ngrok_control() {
    local action="${1:-status}"
    case "$action" in
        add-token|token|add)
            ngrok_add_token "${2:-}"
            ;;
        remove-token|rm-token|remove)
            ngrok_remove_token "${2:-}"
            ;;
        list-tokens|tokens|list)
            ngrok_list_tokens
            ;;
        clear-tokens|clear)
            rm -f "$NGROK_TOKENS_FILE" "$NGROK_EXHAUSTED_FILE"
            echo "[✓] Cleared ngrok token pool."
            ;;
        reset-exhausted|reset)
            rm -f "$NGROK_EXHAUSTED_FILE"
            echo "[✓] Reset quota-exhausted status for all Ngrok tokens."
            ;;
        rotate)
            echo "[*] Rotating Ngrok auth token..."
            pkill -f "ngrok.*tcp" 2>/dev/null || true
            rm -f "$NGROK_STATE" "$NGROK_LOG"
            local curr_tok
            curr_tok=$(cat "$NGROK_CURR_TOKEN" 2>/dev/null || true)
            if [ -n "$curr_tok" ]; then
                mark_ngrok_token_exhausted "$curr_tok"
            fi
            ngrok_control start
            ;;
        start)
            ensure_host_sshd
            if ! command -v ngrok >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/ngrok" ]; then
                echo "Error: ngrok is not installed in Termux."
                echo "Install ngrok: pkg install ngrok  (or download binary to $PREFIX/bin/ngrok)"
                return 1
            fi
            touch "$NGROK_STATE"
            if ngrok_running; then
                echo "[*] Ngrok tunnel is already running."
            else
                pkill -f "ngrok.*tcp" 2>/dev/null || true
                local tokens=()
                if [ -f "$NGROK_TOKENS_FILE" ]; then
                    mapfile -t tokens < "$NGROK_TOKENS_FILE"
                fi

                local started=false
                if [ ${#tokens[@]} -eq 0 ]; then
                    rm -f "$NGROK_LOG"
                    nohup ngrok tcp 8022 --log=stdout > "$NGROK_LOG" 2>&1 &
                    echo $! > "$NGROK_STATE"
                    if ngrok_wait_registered; then started=true; fi
                else
                    local unexhausted_count=0
                    for tok in "${tokens[@]}"; do
                        [ -n "$tok" ] || continue
                        if ! grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                            unexhausted_count=$((unexhausted_count + 1))
                        fi
                    done
                    if [ "$unexhausted_count" -eq 0 ]; then
                        echo "[!] All tokens in pool were marked quota-exhausted; resetting pool exhaustion log for fresh attempt..."
                        rm -f "$NGROK_EXHAUSTED_FILE"
                    fi

                    for tok in "${tokens[@]}"; do
                        [ -n "$tok" ] || continue
                        if grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                            echo "[*] Skipping quota-exhausted token ${tok:0:6}..."
                            continue
                        fi
                        echo "[*] Trying ngrok auth token: ${tok:0:6}..."
                        echo "$tok" > "$NGROK_CURR_TOKEN"
                        ngrok config add-authtoken "$tok" >/dev/null 2>&1 || true
                        rm -f "$NGROK_LOG"
                        nohup ngrok tcp 8022 --log=stdout > "$NGROK_LOG" 2>&1 &
                        echo $! > "$NGROK_STATE"
                        if ngrok_wait_registered; then
                            echo "[✓] Successfully connected using token ${tok:0:6}..."
                            started=true
                            break
                        else
                            echo "[!] Token ${tok:0:6}... failed or reached quota limit. Marking exhausted and trying next token..."
                            mark_ngrok_token_exhausted "$tok"
                            pkill -f "ngrok.*tcp" 2>/dev/null || true
                        fi
                    done
                fi

                if [ "$started" = false ]; then
                    echo "Error: All ngrok tokens failed or quota reached."
                    echo "Add a new token with: asl remote ngrok add-token <token>"
                    rm -f "$NGROK_STATE"
                    return 1
                fi
            fi
            ngrok_status
            ;;
        stop)
            if ngrok_running; then
                local pid
                pid=$(cat "$NGROK_STATE" 2>/dev/null)
                [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || pkill -f "ngrok.*tcp" 2>/dev/null || true
                rm -f "$NGROK_STATE" "$NGROK_LOG" "$NGROK_CURR_TOKEN"
                echo "[✓] Ngrok tunnel stopped."
            else
                rm -f "$NGROK_STATE" "$NGROK_CURR_TOKEN"
                echo "[*] Ngrok tunnel is not running."
            fi
            ;;
        status|"")
            ngrok_status
            ;;
    esac
}

ngrok_status() {
    if ngrok_running; then
        echo "Ngrok Tunnel: RUNNING (Multi-Token Pool & Auto-Rotation)"
        local url
        url=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -oE 'tcp://[^"]+' | head -1)
        if [ -n "$url" ]; then
            local host port
            host=$(echo "$url" | sed -E 's|tcp://([^:]+):.*|\1|')
            port=$(echo "$url" | sed -E 's|tcp://[^:]+:([0-9]+)|\1|')
            echo "    URL:      $url"
            echo "    Connect:  ssh -p $port $(whoami)@$host"
            echo "    Authentication: configured remote credential"
        else
            echo "    (Fetching connection info... run 'asl remote ngrok status')"
        fi
    else
        echo "Ngrok Tunnel: STOPPED"
    fi
}

# --- 5. SSH Public Key Authorization Management -----------------------------
key_control() {
    local action="${1:-list}"
    local key_file="$HOME/.ssh/authorized_keys"
    case "$action" in
        add)
            local key="${2:-}"
            if [ -z "$key" ] || ! printf '%s\n' "$key" | grep -qE '^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2-)[[:space:]]+[A-Za-z0-9+/]+=*([[:space:]]+[^[:space:]]+)?$'; then
                echo "Usage: asl remote keys add \"<ssh-pubkey-string>\""
                return 1
            fi
            mkdir -p "$HOME/.ssh"
            echo "$key" >> "$key_file"
            chmod 600 "$key_file"
            echo "[✓] SSH Public Key added successfully to host."
            ;;
        import-github|github)
            local gh_user="$2"
            if [ -z "$gh_user" ] || [[ ! "$gh_user" =~ ^[A-Za-z0-9-]+$ ]]; then
                echo "Usage: asl remote keys import-github <github_username>"
                return 1
            fi
            echo "[*] Fetching SSH public keys for GitHub user '$gh_user'..."
            local fetched_keys valid_keys invalid_count
            fetched_keys=$(curl -fsSL --max-time 20 --connect-timeout 10 "https://github.com/${gh_user}.keys" 2>/dev/null || true)
            if [ -n "$fetched_keys" ] && [ "${#fetched_keys}" -le 65536 ]; then
                valid_keys=""
                invalid_count=0
                while IFS= read -r line; do
                    if printf '%s\n' "$line" | grep -qE '^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2-)[[:space:]]+[A-Za-z0-9+/]+=*([[:space:]]+[^[:space:]]+)?$'; then
                        valid_keys="${valid_keys}${line}"$'\n'
                    else
                        invalid_count=$((invalid_count + 1))
                    fi
                done <<< "$fetched_keys"
                if [ -z "$valid_keys" ]; then
                    echo "Error: No valid SSH keys found for GitHub user '$gh_user'."
                    return 1
                fi
                if [ "$invalid_count" -gt 0 ]; then
                    echo "[!] Skipped $invalid_count invalid line(s) from the fetched key list."
                fi
                mkdir -p "$HOME/.ssh"
                chmod 700 "$HOME/.ssh"
                printf '%s' "$valid_keys" >> "$key_file"
                chmod 600 "$key_file"
                echo "[✓] Successfully imported SSH key(s) from GitHub user '$gh_user'."
            else
                echo "Error: Could not fetch SSH keys for GitHub user '$gh_user' (empty, timed out, or oversized response)."
                return 1
            fi
            ;;
        list|show)
            echo "=== Authorized SSH Public Keys ==="
            if [ -f "$key_file" ] && [ -s "$key_file" ]; then
                cat "$key_file"
            else
                echo "(No public keys authorized yet. Add using 'asl remote keys add' or 'asl remote keys import-github <user>')"
            fi
            ;;
        clear|purge)
            rm -f "$key_file"
            echo "[✓] Authorized SSH keys cleared."
            ;;
        *)
            echo "Usage: asl remote keys [list|add <key>|import-github <username>|clear]"
            ;;
    esac
}

# --- 6. Seamless Auto-Connect Daemon & Fallback Engine -----------------------
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
        # 1. Host SSH Server Health Check
        ensure_host_sshd

        # Check network connectivity before attempting remote tunnels
        if is_online; then
            # 2. Serveo Tunnel (Free persistent SSH jump host)
            local serveo_up=false
            if [ -f "$SERVEO_STATE" ]; then
                if serveo_running; then
                    serveo_up=true
                else
                    echo "[Autoconnect $(date +%H:%M:%S)] Serveo tunnel offline. Re-establishing..." >> "$AUTOCONNECT_LOG"
                    bash "$script_path" serveo start >> "$AUTOCONNECT_LOG" 2>&1 || true
                    serveo_running && serveo_up=true
                fi
            fi

            # 3. Ngrok Backup for Serveo (Auto-Rotate on quota exhaust)
            if [ "$serveo_up" = false ] || [ -f "$NGROK_STATE" ] || { [ -f "$NGROK_TOKENS_FILE" ] && [ -s "$NGROK_TOKENS_FILE" ]; }; then
                if ! ngrok_running; then
                    echo "[Autoconnect $(date +%H:%M:%S)] Ngrok tunnel offline (Serveo backup/active). Starting/rotating token pool..." >> "$AUTOCONNECT_LOG"
                    bash "$script_path" ngrok start >> "$AUTOCONNECT_LOG" 2>&1 || true
                fi
            fi
        fi

        # Rotate log file if > 100KB to prevent high disk usage
        if [ -f "$AUTOCONNECT_LOG" ] && [ "$(wc -c < "$AUTOCONNECT_LOG" 2>/dev/null || echo 0)" -gt 102400 ]; then
            tail -n 200 "$AUTOCONNECT_LOG" > "$AUTOCONNECT_LOG.tmp" 2>/dev/null && mv "$AUTOCONNECT_LOG.tmp" "$AUTOCONNECT_LOG" 2>/dev/null || true
        fi

        sleep 15
    done

    rm -f "$AUTOCONNECT_PID" 2>/dev/null || true
}

autoconnect_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            if [ -f "$AUTOCONNECT_STATE" ] && { pgrep -f "autoconnect-daemon" >/dev/null 2>&1 || pgrep -f "autoconnect_daemon" >/dev/null 2>&1 || [ -f "$AUTOCONNECT_PID" ]; }; then
                echo "[*] Auto-Connect daemon is already running."
            else
                echo "[*] Starting ASL Seamless Remote Auto-Connect Daemon..."
                touch "$AUTOCONNECT_STATE"
                termux-wake-lock 2>/dev/null || true
                nohup bash "$SCRIPT_DIR/desktop/remote.sh" autoconnect-daemon > "$AUTOCONNECT_LOG" 2>&1 &
                echo $! > "$AUTOCONNECT_PID" 2>/dev/null || true
                echo "[✓] Auto-Connect daemon active (Wake-lock engaged). Tunnels (Serveo & Ngrok Backup) will auto-restart on network drop."
            fi
            ;;
        stop)
            rm -f "$AUTOCONNECT_STATE" "$AUTOCONNECT_PID"
            pkill -f "autoconnect-daemon" 2>/dev/null || pkill -f "autoconnect_daemon" 2>/dev/null || true
            termux-wake-unlock 2>/dev/null || true
            echo "[✓] Auto-Connect daemon stopped."
            ;;
        status|"")
            if [ -f "$AUTOCONNECT_STATE" ] && { pgrep -f "autoconnect-daemon" >/dev/null 2>&1 || pgrep -f "autoconnect_daemon" >/dev/null 2>&1; }; then
                echo "Auto-Connect Daemon: ACTIVE (Monitoring SSH, Serveo & Ngrok Backup with Wake-Lock)"
            else
                echo "Auto-Connect Daemon: INACTIVE"
            fi
            ;;
    esac
}

# --- 7. Start All Remote Services ------------------------------------------
start_all() {
    echo "[*] Initializing ASL Remote Bridge Services..."
    lan_control start
    echo ""
    serveo_control start
    echo ""
    ngrok_control start || true
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
        serveo) serveo_control "$@" ;;
        ngrok) ngrok_control "$@" ;;
        autoconnect) autoconnect_control "$@" ;;
        autoconnect-daemon) autoconnect_daemon ;;
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
