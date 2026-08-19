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
    if ! pgrep -f "sshd -p 8022" >/dev/null 2>&1 && ! su -c "pgrep -f 'sshd -p 8022'" >/dev/null 2>&1; then
        echo "[*] Starting Termux host SSH daemon on port 8022..."
        sshd -p 8022 -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no 2>/dev/null || return 1
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
                serveo_alias="asl-$(whoami)"
                echo "[*] Launching Serveo persistent SSH tunnel on port 8022 (alias: ${serveo_alias})..."
                rm -f "$SERVEO_LOG"
                nohup ssh -i "$SERVEO_KEY" -T -N -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o ConnectTimeout=15 -R "${serveo_alias}:22:localhost:8022" serveo.net > "$SERVEO_LOG" 2>&1 &
                echo $! > "$SERVEO_STATE"
                sleep 4
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
        s_alias="asl-${user}"
        echo "    Connect:  ssh -J serveo.net ${user}@${s_alias}"
        echo "    Authentication: SSH key or configured remote credential"
    else
        echo "Serveo Tunnel: STOPPED"
    fi
}

# --- 4. Ngrok Tunnel (Multi-Token Pool & Fallback) ---------------------------
NGROK_TOKENS_FILE="$CONFIG_DIR/ngrok_tokens.txt"
NGROK_LOG="$PREFIX/tmp/ngrok.log"
NGROK_STATE="$PREFIX/tmp/asl-ngrok.state"

ngrok_running() {
    [ -f "$NGROK_STATE" ] || return 1
    pgrep -f "ngrok.*tcp" >/dev/null 2>&1 || return 1
    # Verify the tunnel is genuinely registered via ngrok's local API, rather
    # than only trusting that a process is alive (avoids false "running").
    grep -qE '"public_url"\s*:\s*"tcp://' <(curl -s --max-time 3 http://127.0.0.1:4040/api/tunnels 2>/dev/null)
}

ngrok_wait_registered() {
    local tries=0
    while [ "$tries" -lt 6 ]; do
        if ngrok_running; then return 0; fi
        if grep -qE "ERR_NGROK|authentication failed|Error:" "$NGROK_LOG" 2>/dev/null; then return 1; fi
        sleep 1
        tries=$((tries + 1))
    done
    return 1
}

ngrok_add_token() {
    local token="$1"
    if [ -z "$token" ] || [[ "$token" =~ [^A-Za-z0-9_] ]]; then
        echo "Error: Token must be non-empty and contain only letters, digits, or underscores."
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

ngrok_control() {
    local action="${1:-status}"
    case "$action" in
        add-token|token)
            ngrok_add_token "${2:-}"
            ;;
        start)
            ensure_host_sshd
            if ! command -v ngrok >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/ngrok" ]; then
                echo "Error: ngrok is not installed in Termux."
                echo "Install ngrok: pkg install ngrok  (or download binary to $PREFIX/bin/ngrok)"
                return 1
            fi
            if ngrok_running; then
                echo "[*] Ngrok tunnel is already running."
            else
                echo "[*] Starting Ngrok TCP tunnel (checking token pool)..."
                local tokens=()
                if [ -f "$NGROK_TOKENS_FILE" ]; then
                    mapfile -t tokens < "$NGROK_TOKENS_FILE"
                fi

                local started=false
                if [ ${#tokens[@]} -eq 0 ]; then
                    # Try starting without explicitly configured token file
                    rm -f "$NGROK_LOG"
                    nohup ngrok tcp 8022 --log=stdout > "$NGROK_LOG" 2>&1 &
                    echo $! > "$NGROK_STATE"
                    if ngrok_wait_registered; then started=true; fi
                else
                    for tok in "${tokens[@]}"; do
                        [ -n "$tok" ] || continue
                        echo "[*] Trying ngrok auth token: ${tok:0:6}..."
                        ngrok config add-authtoken "$tok" >/dev/null 2>&1 || true
                        rm -f "$NGROK_LOG"
                        nohup ngrok tcp 8022 --log=stdout > "$NGROK_LOG" 2>&1 &
                        echo $! > "$NGROK_STATE"
                        if ngrok_wait_registered; then
                            echo "[✓] Successfully connected using token ${tok:0:6}..."
                            started=true
                            break
                        else
                            echo "[!] Token ${tok:0:6}... failed or reached quota limit. Trying next token in pool..."
                            pkill -f "ngrok.*tcp" 2>/dev/null || true
                            rm -f "$NGROK_STATE"
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
                rm -f "$NGROK_STATE" "$NGROK_LOG"
                echo "[✓] Ngrok tunnel stopped."
            else
                rm -f "$NGROK_STATE"
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
        echo "Ngrok Tunnel: RUNNING (Multi-Token Pool)"
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

# --- 5. Tailscale Support ---------------------------------------------------
TS_SOCKET="$CONFIG_DIR/tailscaled.sock"
TS_STATE="$CONFIG_DIR/tailscaled.state"
TS_STATEDIR="$CONFIG_DIR/tailscaled_state"
TS_LOG="$CONFIG_DIR/ts.log"

ensure_tailscaled() {
    if ! pgrep -f "tailscaled" >/dev/null 2>&1 && ! su -c "pgrep -f tailscaled" >/dev/null 2>&1; then
        echo "[*] Starting tailscaled daemon..."
        rm -f "$TS_SOCKET"
        mkdir -p "$TS_STATEDIR"
        chmod 700 "$TS_STATEDIR" 2>/dev/null || true
        if command -v su >/dev/null 2>&1 && su -c "id" >/dev/null 2>&1; then
            su -c "PATH=$PREFIX/bin:\$PATH nohup tailscaled --statedir='$TS_STATEDIR' --state='$TS_STATE' --socket='$TS_SOCKET' --tun=userspace-networking > '$TS_LOG' 2>&1 &" || true
        else
            nohup tailscaled --statedir="$TS_STATEDIR" --state="$TS_STATE" --socket="$TS_SOCKET" --tun=userspace-networking > "$TS_LOG" 2>&1 &
        fi
        sleep 2
    fi
    [ -S "$TS_SOCKET" ] && (chmod 666 "$TS_SOCKET" 2>/dev/null || su -c "chmod 666 '$TS_SOCKET'" 2>/dev/null || true)
}

tailscale_control() {
    local action="${1:-status}"
    case "$action" in
        start|up)
            if ! command -v tailscale >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/tailscale" ]; then
                echo "Error: tailscale CLI is not installed."
                return 1
            fi
            ensure_tailscaled
            echo "[*] Connecting to Tailscale network..."
            local arg="${2:-}"
            local ts_flags="--reset --accept-routes --accept-dns=false --ssh"
            if [ -n "$arg" ]; then
                if [[ "$arg" =~ ^tskey-[A-Za-z0-9_-]+$ ]]; then
                    ts_flags="--reset --authkey=$arg --accept-routes --accept-dns=false --ssh"
                else
                    echo "Error: Invalid auth key format. Expected 'tskey-...'."
                    return 1
                fi
            fi
            local extra=""
            shift 2 2>/dev/null || true
            for f in "$@"; do
                case "$f" in
                    --accept-routes|--accept-dns|--shields-up|--ssh|--exit-node-allow-lan-access|--snat-subnet-routes)
                        extra="$extra $f"
                        ;;
                    --exit-node=*|--hostname=*|--advertise-routes=*|--advertise-exit-node=*|--login-server=*)
                        local val="${f#*=}"
                        if [[ "$val" =~ ^[A-Za-z0-9.:/_-]+$ ]]; then
                            extra="$extra $f"
                        else
                            echo "Error: Unsafe value in tailscale flag: $f"
                            return 1
                        fi
                        ;;
                    *)
                        echo "Error: Unsupported or unsafe tailscale flag: $f"
                        return 1
                        ;;
                esac
            done
            if command -v su >/dev/null 2>&1 && su -c "id" >/dev/null 2>&1; then
                su -c "PATH=$PREFIX/bin:\$PATH tailscale --socket='$TS_SOCKET' up $ts_flags $extra" || tailscale --socket="$TS_SOCKET" up $ts_flags $extra || return 1
            else
                tailscale --socket="$TS_SOCKET" up $ts_flags $extra || return 1
            fi
            echo "[✓] Tailscale active."
            ;;
        stop|down)
            if command -v tailscale >/dev/null 2>&1 || [ -x "$PREFIX/bin/tailscale" ]; then
                tailscale --socket="$TS_SOCKET" down 2>/dev/null || su -c "PATH=$PREFIX/bin:\$PATH tailscale --socket=$TS_SOCKET down" 2>/dev/null || true
                pkill -f "tailscaled" 2>/dev/null || su -c "pkill -f tailscaled" 2>/dev/null || true
                echo "[✓] Tailscale disconnected."
            fi
            ;;
        status|"")
            if pgrep -f "tailscaled" >/dev/null 2>&1 || su -c "pgrep -f tailscaled" >/dev/null 2>&1; then
                local ts_ip
                ts_ip=$(tailscale --socket="$TS_SOCKET" ip -4 2>/dev/null || su -c "PATH=$PREFIX/bin:\$PATH tailscale --socket=$TS_SOCKET ip -4" 2>/dev/null | tr -d '[:space:]')
                if [ -n "$ts_ip" ]; then
                    echo "Tailscale:    RUNNING"
                    echo "    IP:       $ts_ip"
                    echo "    Connect:  ssh -p 8022 $(whoami)@$ts_ip (Host SSH)"
                    echo "              ssh $(whoami)@$ts_ip (Tailscale SSH)"
                    return 0
                fi
            fi
            echo "Tailscale:    STOPPED / Not Configured"
            ;;
    esac
}

# --- 6. SSH Public Key Authorization Management -----------------------------
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

# --- 8. Seamless Auto-Connect Daemon & Fallback Engine -----------------------
AUTOCONNECT_STATE="$PREFIX/tmp/asl-autoconnect.state"
AUTOCONNECT_LOG="$PREFIX/tmp/asl-autoconnect.log"
AUTOCONNECT_PID="$PREFIX/tmp/asl-autoconnect.pid"

is_online() {
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || curl -s --connect-timeout 2 -I https://1.1.1.1 >/dev/null 2>&1
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
            if [ -f "$SERVEO_STATE" ] && ! serveo_running; then
                echo "[Autoconnect $(date +%H:%M:%S)] Serveo tunnel offline. Re-establishing..." >> "$AUTOCONNECT_LOG"
                bash "$script_path" serveo start >> "$AUTOCONNECT_LOG" 2>&1 || true
            fi

            # 3. Tailscale Daemon & Mesh Network Health
            if [ -f "$TS_STATE" ] && ! pgrep -f "tailscaled" >/dev/null 2>&1 && ! su -c "pgrep -f tailscaled" >/dev/null 2>&1; then
                echo "[Autoconnect $(date +%H:%M:%S)] Tailscale daemon dropped. Restarting..." >> "$AUTOCONNECT_LOG"
                ensure_tailscaled
            fi

            # 4. Ngrok Tunnel (Multi-token pool auto-recovery)
            if [ -f "$NGROK_TOKENS_FILE" ] && [ -s "$NGROK_TOKENS_FILE" ] && ! ngrok_running; then
                echo "[Autoconnect $(date +%H:%M:%S)] Ngrok tunnel offline. Re-establishing from pool..." >> "$AUTOCONNECT_LOG"
                bash "$script_path" ngrok start >> "$AUTOCONNECT_LOG" 2>&1 || true
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
                echo "[✓] Auto-Connect daemon active (Wake-lock engaged). Free tunnels (Serveo, Tailscale, Ngrok) will auto-restart on network drop."
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
                echo "Auto-Connect Daemon: ACTIVE (Monitoring SSH, Serveo, Tailscale & Ngrok with Wake-Lock)"
            else
                echo "Auto-Connect Daemon: INACTIVE"
            fi
            ;;
    esac
}

# --- 9. Start All Remote Services ------------------------------------------
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
        tailscale) tailscale_control "$@" ;;
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
            tailscale_control status
            echo ""
            autoconnect_control status
            ;;
        *)
            echo "Usage: asl remote [all|password|lan|keys|serveo|ngrok|tailscale|autoconnect] [start|stop|status]"
            exit 1
            ;;
    esac
fi
