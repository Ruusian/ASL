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
# Fix ownership if created by root
if [ -d "$CONFIG_DIR" ] && [ ! -w "$CONFIG_DIR" ]; then
    su -c "chown $(id -u):$(id -g) '$CONFIG_DIR'" 2>/dev/null || true
fi

PASS_FILE="$CONFIG_DIR/remote_password"
DEFAULT_PASS="1011"

get_password() {
    if [ -f "$PASS_FILE" ]; then
        cat "$PASS_FILE" 2>/dev/null
    else
        printf '%s' "$DEFAULT_PASS"
    fi
}

set_password() {
    local new_pass="${1:-$DEFAULT_PASS}"
    if [ -z "$new_pass" ]; then
        echo "Error: Password cannot be empty."
        return 1
    fi
    printf '%s\n%s\n' "$new_pass" "$new_pass" | passwd >/dev/null 2>&1 || true
    if is_mounted; then
        asl_exec "printf '%s\n%s\n' '$new_pass' '$new_pass' | passwd >/dev/null 2>&1" || true
    fi
    printf '%s' "$new_pass" > "$PASS_FILE"
    chmod 600 "$PASS_FILE"
    echo "[✓] ASL Remote SSH password successfully updated to: $new_pass"
}

ensure_host_sshd() {
    local pass
    pass=$(get_password)
    # Ensure password set
    printf '%s\n%s\n' "$pass" "$pass" | passwd >/dev/null 2>&1 || true

    mkdir -p "$PREFIX/etc/ssh"
    if [ ! -f "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]; then
        ssh-keygen -A >/dev/null 2>&1 || true
    fi
    if ! pgrep -f "sshd.*8022\|sshd" >/dev/null 2>&1; then
        echo "[*] Starting Termux host SSH daemon on port 8022..."
        sshd -p 8022 2>/dev/null || sshd 2>/dev/null || true
    fi
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
            echo "Current SSH Remote Password: $(get_password)"
            echo "Change password using: asl remote password set <new_password>"
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
            ensure_host_sshd
            local host pass
            host=$(lan_host_ip)
            pass=$(get_password)
            echo "[✓] LAN SSH Server active on port 8022."
            echo "    Connect command: ssh -p 8022 $(whoami)@$host"
            echo "    Password:        $pass"
            ;;
        stop)
            pkill -f "sshd" 2>/dev/null || true
            echo "[✓] LAN SSH Server stopped."
            ;;
        status|"")
            if pgrep -f "sshd" >/dev/null 2>&1; then
                echo "LAN SSH:      RUNNING (port 8022)"
                echo "    Connect:  ssh -p 8022 $(whoami)@$(lan_host_ip)"
                echo "    Password: $(get_password)"
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
    [ -f "$SERVEO_STATE" ] && pgrep -f "serveo.net" >/dev/null 2>&1
}

serveo_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            ensure_host_sshd
            ensure_serveo_key
            if serveo_running; then
                echo "[*] Serveo tunnel is already running."
            else
                local serveo_alias="asl-$(whoami)"
                echo "[*] Launching Serveo persistent SSH tunnel on port 8022 (alias: ${serveo_alias})..."
                rm -f "$SERVEO_LOG"
                nohup ssh -i "$SERVEO_KEY" -T -N -o StrictHostKeyChecking=no -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -R "${serveo_alias}:22:localhost:8022" serveo.net > "$SERVEO_LOG" 2>&1 &
                echo $! > "$SERVEO_STATE"
                sleep 4
                if ! serveo_running; then
                    echo "Error: Serveo tunnel failed to connect. Log output:"
                    cat "$SERVEO_LOG" 2>/dev/null
                    rm -f "$SERVEO_STATE"
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
        echo "    Password: $(get_password)"
    else
        echo "Serveo Tunnel: STOPPED"
    fi
}

# --- 4. Ngrok Tunnel (Multi-Token Pool & Fallback) ---------------------------
NGROK_TOKENS_FILE="$CONFIG_DIR/ngrok_tokens.txt"
NGROK_LOG="$PREFIX/tmp/ngrok.log"
NGROK_STATE="$PREFIX/tmp/asl-ngrok.state"

ngrok_running() {
    [ -f "$NGROK_STATE" ] && pgrep -f "ngrok.*tcp" >/dev/null 2>&1
}

ngrok_add_token() {
    local token="$1"
    if [ -z "$token" ]; then
        echo "Usage: asl remote ngrok add-token <your_authtoken>"
        return 1
    fi
    mkdir -p "$CONFIG_DIR"
    if ! grep -qF "$token" "$NGROK_TOKENS_FILE" 2>/dev/null; then
        echo "$token" >> "$NGROK_TOKENS_FILE"
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
                    sleep 3
                    if ngrok_running; then started=true; fi
                else
                    for tok in "${tokens[@]}"; do
                        [ -n "$tok" ] || continue
                        echo "[*] Trying ngrok auth token: ${tok:0:6}..."
                        ngrok config add-authtoken "$tok" >/dev/null 2>&1 || true
                        rm -f "$NGROK_LOG"
                        nohup ngrok tcp 8022 --log=stdout > "$NGROK_LOG" 2>&1 &
                        echo $! > "$NGROK_STATE"
                        sleep 3
                        if ngrok_running && ! grep -qE "ERR_NGROK_108|ERR_NGROK_4018|authentication failed" "$NGROK_LOG" 2>/dev/null; then
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
            echo "    Password: $(get_password)"
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
TS_LOG="$CONFIG_DIR/ts.log"

ensure_tailscaled() {
    if ! pgrep -f "tailscaled" >/dev/null 2>&1 && ! su -c "pgrep -f tailscaled" >/dev/null 2>&1; then
        echo "[*] Starting tailscaled daemon..."
        rm -f "$TS_SOCKET"
        su -c "PATH=$PREFIX/bin:\$PATH nohup tailscaled --state='$TS_STATE' --socket='$TS_SOCKET' --tun=userspace-networking > '$TS_LOG' 2>&1 &" || true
        sleep 2
    fi
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
            if [[ "$arg" =~ ^tskey- ]]; then
                su -c "PATH=$PREFIX/bin:\$PATH tailscale --socket=$TS_SOCKET up --authkey=$arg --accept-routes --accept-dns=false" || return 1
            else
                su -c "PATH=$PREFIX/bin:\$PATH tailscale --socket=$TS_SOCKET up ${*:2} --accept-routes --accept-dns=false" || return 1
            fi
            echo "[✓] Tailscale active."
            ;;
        stop|down)
            if command -v tailscale >/dev/null 2>&1 || [ -x "$PREFIX/bin/tailscale" ]; then
                su -c "PATH=$PREFIX/bin:\$PATH tailscale --socket=$TS_SOCKET down" 2>/dev/null || true
                pkill -f "tailscaled" 2>/dev/null || true
                echo "[✓] Tailscale disconnected."
            fi
            ;;
        status|"")
            if su -c "pgrep -f tailscaled" >/dev/null 2>&1 || pgrep -f "tailscaled" >/dev/null 2>&1; then
                local ts_ip
                ts_ip=$(su -c "PATH=$PREFIX/bin:\$PATH tailscale --socket=$TS_SOCKET ip -4" 2>/dev/null | tr -d '[:space:]')
                if [ -n "$ts_ip" ]; then
                    echo "Tailscale:    RUNNING"
                    echo "    Connect:  ssh -p 8022 $(whoami)@$ts_ip"
                    echo "    Password: $(get_password)"
                    return 0
                fi
            fi
            echo "Tailscale:    STOPPED / Not Configured"
            ;;
    esac
}

# --- 6. Direct Chroot SSH Server (Port 2222) ----------------------------------
chroot_ssh_running() {
    is_mounted && asl_chroot_exec "pgrep -f 'sshd.*2222|sshd' >/dev/null 2>&1"
}

chroot_ssh_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            if ! is_mounted; then
                echo "Error: Debian chroot is not mounted. Run 'asl start' first."
                return 1
            fi
            echo "[*] Configuring and starting OpenSSH server inside Debian chroot (port 2222)..."
            local pass
            pass=$(get_password)
            asl_chroot_exec "
                export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
                mkdir -p /var/run/sshd /root/.ssh
                chmod 700 /root/.ssh
                if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
                    ssh-keygen -A >/dev/null 2>&1 || true
                fi
                printf '%s\n%s\n' '$pass' '$pass' | passwd root >/dev/null 2>&1 || true
                if grep -qE '^#?PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null; then
                    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
                else
                    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
                fi
                if grep -qE '^#?Port' /etc/ssh/sshd_config 2>/dev/null; then
                    sed -i 's/^#\?Port.*/Port 2222/' /etc/ssh/sshd_config
                else
                    echo 'Port 2222' >> /etc/ssh/sshd_config
                fi
                if ! pgrep -f 'sshd.*2222' >/dev/null 2>&1; then
                    /usr/sbin/sshd -p 2222 2>/dev/null || service ssh start 2>/dev/null || true
                fi
            " 2>/dev/null || true
            echo "[✓] Direct Chroot SSH Server active on port 2222."
            echo "    Connect command: ssh -p 2222 root@$(lan_host_ip)"
            echo "    Password:        $pass"
            ;;
        stop)
            if is_mounted; then
                asl_chroot_exec "pkill -f 'sshd.*2222' 2>/dev/null || true" 2>/dev/null || true
                echo "[✓] Chroot SSH Server stopped."
            fi
            ;;
        status|"")
            if chroot_ssh_running; then
                echo "Chroot SSH:   RUNNING (port 2222)"
                echo "    Connect:  ssh -p 2222 root@$(lan_host_ip)"
                echo "    Password: $(get_password)"
            else
                echo "Chroot SSH:   STOPPED"
            fi
            ;;
    esac
}

# --- 7. SSH Public Key Authorization Management -----------------------------
key_control() {
    local action="${1:-list}"
    local key_file="$HOME/.ssh/authorized_keys"
    local chroot_key_file="$DEBIANPATH/root/.ssh/authorized_keys"
    case "$action" in
        add)
            local key="$2"
            if [ -z "$key" ]; then
                echo "Usage: asl remote keys add \"<ssh-pubkey-string>\""
                return 1
            fi
            mkdir -p "$HOME/.ssh"
            echo "$key" >> "$key_file"
            chmod 600 "$key_file"
            if is_mounted; then
                asl_chroot_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh" 2>/dev/null || true
                asl_exec "echo '$key' >> '$chroot_key_file' && chmod 600 '$chroot_key_file'" 2>/dev/null || true
            fi
            echo "[✓] SSH Public Key added successfully to host & chroot."
            ;;
        import-github|github)
            local gh_user="$2"
            if [ -z "$gh_user" ]; then
                echo "Usage: asl remote keys import-github <github_username>"
                return 1
            fi
            echo "[*] Fetching SSH public keys for GitHub user '$gh_user'..."
            local fetched_keys
            fetched_keys=$(curl -s "https://github.com/${gh_user}.keys")
            if [ -n "$fetched_keys" ] && ! echo "$fetched_keys" | grep -q "Not Found"; then
                mkdir -p "$HOME/.ssh"
                echo "$fetched_keys" >> "$key_file"
                chmod 600 "$key_file"
                if is_mounted; then
                    asl_chroot_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh" 2>/dev/null || true
                    asl_exec "echo '$fetched_keys' >> '$chroot_key_file' && chmod 600 '$chroot_key_file'" 2>/dev/null || true
                fi
                echo "[✓] Successfully imported SSH key(s) from GitHub user '$gh_user'."
            else
                echo "Error: Could not fetch SSH keys for GitHub user '$gh_user'."
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
            [ -f "$chroot_key_file" ] && asl_exec "rm -f '$chroot_key_file'" 2>/dev/null || true
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
    local script_path="$0"

    while [ -f "$AUTOCONNECT_STATE" ]; do
        # 1. Host SSH Server Health Check
        ensure_host_sshd

        # Check network connectivity before attempting remote tunnels
        if is_online; then
            # 2. Serveo Tunnel (Free persistent SSH jump host)
            if ! serveo_running; then
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
        if [ -f "$AUTOCONNECT_LOG" ] && [ $(wc -c < "$AUTOCONNECT_LOG" 2>/dev/null || echo 0) -gt 102400 ]; then
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
            if [ -f "$AUTOCONNECT_STATE" ] && { pgrep -f "autoconnect_daemon" >/dev/null 2>&1 || [ -f "$AUTOCONNECT_PID" ]; }; then
                echo "[*] Auto-Connect daemon is already running."
            else
                echo "[*] Starting ASL Seamless Remote Auto-Connect Daemon..."
                touch "$AUTOCONNECT_STATE"
                nohup bash -c "source \"$0\"; autoconnect_daemon" > "$AUTOCONNECT_LOG" 2>&1 &
                echo $! > "$AUTOCONNECT_PID" 2>/dev/null || true
                echo "[✓] Auto-Connect daemon active. Free tunnels (Serveo, Tailscale, Ngrok) will auto-restart on network drop."
            fi
            ;;
        stop)
            rm -f "$AUTOCONNECT_STATE" "$AUTOCONNECT_PID"
            pkill -f "autoconnect_daemon" 2>/dev/null || true
            echo "[✓] Auto-Connect daemon stopped."
            ;;
        status|"")
            if [ -f "$AUTOCONNECT_STATE" ] && pgrep -f "autoconnect_daemon" >/dev/null 2>&1; then
                echo "Auto-Connect Daemon: ACTIVE (Monitoring SSH, Serveo, Tailscale & Ngrok)"
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
    if is_mounted; then
        chroot_ssh_control start || true
        echo ""
    fi
    serveo_control start
    echo ""
    ngrok_control start || true
    echo ""
    autoconnect_control start
    echo ""
    echo "[✓] All remote connection bridges initialized!"
}

TARGET="${1:-status}"
shift || true

case "$TARGET" in
    all|start-all) start_all ;;
    password|pass) password_control "$@" ;;
    lan) lan_control "$@" ;;
    chroot) chroot_ssh_control "$@" ;;
    key|keys|pubkey) key_control "$@" ;;
    serveo) serveo_control "$@" ;;
    ngrok) ngrok_control "$@" ;;
    tailscale) tailscale_control "$@" ;;
    autoconnect) autoconnect_control "$@" ;;
    status|"")
        echo "=== ASL Remote Bridge Status ==="
        echo "Remote Password: $(get_password)"
        echo ""
        lan_control status
        echo ""
        chroot_ssh_control status
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
        echo "Usage: asl remote [all|password|lan|chroot|keys|serveo|ngrok|tailscale|autoconnect] [start|stop|status]"
        exit 1
        ;;
esac
