#!/bin/bash
# ASL: Remote Access Bridge (SSH, VNC & Public Internet SSH)

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_mounted() {
    if ! is_mounted; then
        bash "$SCRIPT_DIR/core/mount-chroot.sh" || exit 1
    fi
}

# Kill only processes whose /proc/<pid>/root resolves to the chroot path.
# A bare `pkill -f` inside the chroot sees the host's /proc bind mount and
# can kill unrelated host processes with a matching cmdline.
kill_chroot() {
    local sig="$1" pat="$2"
    asl_exec "
        for pid in /proc/[0-9]*; do
            [ -d \"\$pid\" ] || continue
            [ \"\$(readlink \"\$pid/root\" 2>/dev/null)\" = \"$DEBIANPATH\" ] || continue
            grep -qE \"$pat\" \"\$pid/comm\" \"\$pid/cmdline\" 2>/dev/null || continue
            kill $sig \"\${pid#/proc/}\" 2>/dev/null || true
        done
    " 2>/dev/null || true
}

# Kill only processes whose /proc/<pid>/root resolves to "/" (the host root,
# i.e. Termux/Android), never processes living inside the chroot. Used to
# stop the Termux host sshd without touching the chroot's sshd (port 2222).
#
# Match on comm ONLY, not cmdline: the su wrapper's cmdline contains the
# literal pattern (it is passed as an argument), so a cmdline match TERMs our
# own wrapper shell before it ever reaches the daemon (observed: "Terminated"
# + the sshd surviving). The chroot killer can use cmdline safely because its
# $DEBIANPATH root guard filters out every host-side wrapper.
kill_host() {
    local sig="$1" pat="$2"
    asl_exec "
        for pid in /proc/[0-9]*; do
            [ -d \"\$pid\" ] || continue
            [ \"\$(readlink \"\$pid/root\" 2>/dev/null)\" = \"/\" ] || continue
            grep -qE \"$pat\" \"\$pid/comm\" 2>/dev/null || continue
            kill $sig \"\${pid#/proc/}\" 2>/dev/null || true
        done
    " 2>/dev/null || true
}

ssh_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            ensure_mounted
            echo "[*] Checking SSH server installation..."
            if ! asl_chroot_exec "/usr/bin/test -x /usr/sbin/sshd" 2>/dev/null; then
                echo "[*] Installing openssh-server inside Debian chroot..."
                asl_chroot_exec "/usr/bin/apt-get update && /usr/bin/apt-get install -y openssh-server" || return 1
            fi
            asl_chroot_exec "/usr/bin/ssh-keygen -A" 2>/dev/null || true
            asl_chroot_exec "chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true" 2>/dev/null || true
            asl_chroot_exec "/bin/mkdir -p /var/run/sshd" 2>/dev/null || true
            # SSH hardening: root login allowed only via public key
            # (prohibit-password); password auth is disabled. Passwords over
            # the network are crackable — use an authorized_keys entry instead.
            asl_chroot_exec "if grep -qE \"^[#]?PermitRootLogin\" /etc/ssh/sshd_config; then sed -i \"s/^[#]*PermitRootLogin.*/PermitRootLogin prohibit-password/\" /etc/ssh/sshd_config; else echo \"PermitRootLogin prohibit-password\" >> /etc/ssh/sshd_config; fi; if grep -qE \"^[#]?PasswordAuthentication\" /etc/ssh/sshd_config; then sed -i \"s/^[#]*PasswordAuthentication.*/PasswordAuthentication no/\" /etc/ssh/sshd_config; else echo \"PasswordAuthentication no\" >> /etc/ssh/sshd_config; fi; if grep -qE \"^[#]?PubkeyAuthentication\" /etc/ssh/sshd_config; then sed -i \"s/^[#]*PubkeyAuthentication.*/PubkeyAuthentication yes/\" /etc/ssh/sshd_config; else echo \"PubkeyAuthentication yes\" >> /etc/ssh/sshd_config; fi" 2>/dev/null || true
            if asl_chroot_exec "pgrep -x sshd" >/dev/null 2>&1; then
                echo "[*] SSH server is already running."
            else
                echo "[*] Starting SSH daemon on port 2222..."
                asl_chroot_exec "if command -v setpriv >/dev/null 2>&1; then /usr/bin/setpriv --reuid=0 --regid=0 --init-groups /usr/sbin/sshd -p 2222; else /usr/sbin/sshd -p 2222; fi" || return 1
                echo "[✓] SSH server active. Connect via: ssh root@127.0.0.1 -p 2222"
                echo "    Note: Password auth is DISABLED; root requires a public key."
                echo "          Add one with: asl exec sh -c 'mkdir -p ~/.ssh && echo YOUR_PUBKEY >> ~/.ssh/authorized_keys'"
                echo "    Warning: sshd listens on ALL interfaces, not just localhost."
                echo "             Only use this on a trusted network (or tunnel it via ssh -L)."
            fi
            ;;
        stop)
            if is_mounted && asl_chroot_exec "pgrep -x sshd" >/dev/null 2>&1; then
                kill_chroot TERM 'sshd'
                echo "[✓] SSH daemon stopped."
            else
                echo "[*] SSH server is not running."
            fi
            ;;
        status|"")
            if is_mounted && asl_chroot_exec "pgrep -x sshd" >/dev/null 2>&1; then
                echo "SSH Server: RUNNING (port 2222)"
            else
                echo "SSH Server: STOPPED"
            fi
            ;;
    esac
}

vnc_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            ensure_mounted
            if ! asl_chroot_exec "/usr/bin/test -x /usr/bin/x11vnc" 2>/dev/null; then
                echo "[*] Installing x11vnc inside Debian chroot..."
                asl_chroot_exec "/usr/bin/apt-get update && /usr/bin/apt-get install -y x11vnc" || return 1
            fi
            # Clean stale VNC locks before checking process
            asl_chroot_exec "rm -rf /tmp/.X11-vnc /tmp/.vnc/*.pid" 2>/dev/null || true
            if asl_chroot_exec "pgrep -x x11vnc" >/dev/null 2>&1; then
                echo "[*] VNC server is already running."
            else
                PWFILE="/root/.asl-vncpasswd"
                if ! asl_chroot_exec "test -s '$PWFILE'" 2>/dev/null; then
                    VNCPW=$(asl_chroot_exec "tr -dc A-Za-z0-9 < /dev/urandom | head -c 12" 2>/dev/null)
                    [ -n "$VNCPW" ] || VNCPW="asl$(date +%s)"
                    asl_chroot_exec "/usr/bin/x11vnc -storepasswd \"$VNCPW\" \"$PWFILE\" >/dev/null 2>&1 && chmod 600 \"$PWFILE\"" || return 1
                    echo "    VNC password set to: $VNCPW (stored at $PWFILE in chroot)"
                fi
                local bind_host="127.0.0.1"
                if [ "${2:-}" = "--public" ] || [ "${2:-}" = "public" ]; then
                    bind_host="0.0.0.0"
                    echo "[!] Warning: Binding VNC server to public network interface (0.0.0.0). Enforcing password authentication."
                fi
                echo "[*] Starting optimized low-latency x11vnc server on $bind_host:5900..."
                asl_chroot_exec "export DISPLAY=:0; if command -v setpriv >/dev/null 2>&1; then /usr/bin/setpriv --reuid=0 --regid=0 --init-groups /usr/bin/x11vnc -noshm -noxdamage -ncache 10 -ncache_cr -defer 3 -wait 3 -cursor arrow -repeat -nap -noxrecord -noxdamage -display :0 -listen $bind_host -forever -shared -rfbauth $PWFILE -rfbport 5900 -bg >/dev/null 2>&1; else /usr/bin/x11vnc -noshm -noxdamage -ncache 10 -ncache_cr -defer 3 -wait 3 -cursor arrow -repeat -nap -noxrecord -noxdamage -display :0 -listen $bind_host -forever -shared -rfbauth $PWFILE -rfbport 5900 -bg >/dev/null 2>&1; fi" || return 1
                echo "[✓] VNC server active (low-latency near-native mode). Connect to $bind_host:5900."
                echo "    To reset the password, run: asl remote vnc clean reset-auth"
            fi
            ;;
        stop)
            if is_mounted && asl_chroot_exec "pgrep -x x11vnc" >/dev/null 2>&1; then
                kill_chroot TERM 'x11vnc'
                sleep 1
                if asl_chroot_exec "pgrep -x x11vnc" >/dev/null 2>&1; then
                    kill_chroot 9 'x11vnc'
                fi
                asl_chroot_exec "rm -rf /tmp/.X11-vnc /tmp/.vnc/*.pid" 2>/dev/null || true
                echo "[✓] VNC server stopped and locks cleaned."
            else
                asl_chroot_exec "rm -rf /tmp/.X11-vnc /tmp/.vnc/*.pid" 2>/dev/null || true
                echo "[*] VNC server is not running."
            fi
            ;;
        clean|reset)
            echo "[*] Cleaning VNC server state and force-terminating any lingering processes..."
            if is_mounted; then
                kill_chroot TERM 'x11vnc'
                sleep 1
                kill_chroot 9 'x11vnc'
                asl_chroot_exec "rm -rf /tmp/.X11-vnc /tmp/.vnc /tmp/.X11-unix/X5900" 2>/dev/null || true
                if [ "${2:-}" = "reset-auth" ]; then
                    asl_chroot_exec "rm -f /root/.asl-vncpasswd" 2>/dev/null || true
                    echo "[✓] VNC authentication credentials reset."
                fi
            fi
            echo "[✓] VNC server state cleaned successfully."
            ;;
        status|"")
            if is_mounted && asl_chroot_exec "pgrep -x x11vnc" >/dev/null 2>&1; then
                echo "VNC Server: RUNNING (port 5900, low-latency near-native)"
            else
                echo "VNC Server: STOPPED"
            fi
            ;;
    esac
}

# --- Public Internet Remote Access (Pinggy tunnel) -------------------------
SSH_PORT=8022

host_sshd_running() {
    asl_exec "
        for pid in /proc/[0-9]*; do
            [ -d \"\$pid\" ] || continue
            [ \"\$(readlink \"\$pid/root\" 2>/dev/null)\" = \"/\" ] || continue
            grep -q '^sshd\$' \"\$pid/comm\" 2>/dev/null && exit 0
        done
        exit 1
    " 2>/dev/null
}

ensure_host_sshd() {
    if host_sshd_running; then
        return 0
    fi
    echo "[*] Starting Termux host sshd on port $SSH_PORT..."
    sshd || { echo "Error: sshd failed to start."; return 1; }
}

# --- Public Internet Remote Access (Zero-Client Setup) ---------------------
PUBLIC_LOG="$PREFIX/tmp/pinggy.log"
PUBLIC_STATE="$PREFIX/tmp/asl-pinggy.state"

process_start_time() {
    [ -r "/proc/$1/stat" ] || return 1
    awk '{print $22}' "/proc/$1/stat" 2>/dev/null
}

public_process_matches() {
    local pid="$1" expected_start="$2" current_start cmdline
    [ -n "$pid" ] && [ -n "$expected_start" ] || return 1
    current_start=$(process_start_time "$pid") || return 1
    [ "$current_start" = "$expected_start" ] || return 1
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
    [[ "$cmdline" == *"ssh"* && "$cmdline" == *"tcp@a.pinggy.io"* && "$cmdline" == *"-R 0:localhost:$SSH_PORT"* ]]
}

public_tunnel_running() {
    local pid start
    [ -r "$PUBLIC_STATE" ] || return 1
    read -r pid start < "$PUBLIC_STATE" || return 1
    if public_process_matches "$pid" "$start"; then
        return 0
    fi
    rm -f "$PUBLIC_STATE"
    return 1
}

public_start() {
    local pid start
    ensure_host_sshd || return 1
    if public_tunnel_running; then
        echo "[*] Public SSH tunnel is already running."
    else
        echo "[*] Starting zero-config Public Internet SSH Tunnel..."
        rm -f "$PUBLIC_LOG" "$PUBLIC_STATE"
        nohup ssh -p 443 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -R "0:localhost:$SSH_PORT" tcp@a.pinggy.io > "$PUBLIC_LOG" 2>&1 &
        pid=$!
        start=$(process_start_time "$pid")
        if [ -z "$start" ]; then
            echo "Error: Public tunnel failed to start. Log output:"
            cat "$PUBLIC_LOG" 2>/dev/null
            return 1
        fi
        printf '%s %s\n' "$pid" "$start" > "$PUBLIC_STATE" || { kill -TERM "$pid" 2>/dev/null || true; return 1; }
        sleep 3
        if ! public_tunnel_running; then
            echo "Error: Public tunnel failed to start. Log output:"
            cat "$PUBLIC_LOG" 2>/dev/null
            rm -f "$PUBLIC_STATE"
            return 1
        fi
    fi

    local user link port host
    user=$(whoami)
    link=$(grep -oE 'tcp://[^[:space:]]+' "$PUBLIC_LOG" 2>/dev/null | tail -1)
    if [ -n "$link" ]; then
        host=$(echo "$link" | sed -E 's|tcp://([^:]+):.*|\1|')
        port=$(echo "$link" | sed -E 's|tcp://[^:]+:([0-9]+)|\1|')
        echo "[✓] Public Internet SSH active!"
        echo "    Connect from ANY computer or phone (no app install needed):"
        echo "        ssh -p $port ${user}@${host}"
        echo "    Password: Your Termux user password (set via 'passwd')"
    else
        echo "[*] Tunnel starting... Run 'asl remote public status' in a moment for connection link."
    fi
}

public_stop() {
    local pid start
    if public_tunnel_running; then
        read -r pid start < "$PUBLIC_STATE"
        if ! kill -TERM "$pid" 2>/dev/null; then
            echo "[!] Failed to stop the ASL-owned public tunnel."
            return 1
        fi
        rm -f "$PUBLIC_STATE" "$PUBLIC_LOG"
        echo "[✓] Public Internet SSH tunnel stopped."
    else
        echo "[*] Public tunnel is not running."
    fi
}

public_status() {
    if public_tunnel_running; then
        local user link port host
        user=$(whoami)
        link=$(grep -oE 'tcp://[^[:space:]]+' "$PUBLIC_LOG" 2>/dev/null | tail -1)
        echo "Public SSH:   RUNNING"
        if [ -n "$link" ]; then
            host=$(echo "$link" | sed -E 's|tcp://([^:]+):.*|\1|')
            port=$(echo "$link" | sed -E 's|tcp://[^:]+:([0-9]+)|\1|')
            echo "    Command:  ssh -p $port ${user}@${host}"
            echo "    Password: Your Termux user password (set via 'passwd')"
        fi
    else
        echo "Public SSH:   STOPPED"
    fi
}

public_control() {
    local action="${1:-status}"
    case "$action" in
        start)  public_start ;;
        stop)   public_stop ;;
        status|"") public_status ;;
        *) echo "Usage: asl remote public [start|stop|status]"; return 1 ;;
    esac
}

TARGET="${1:-status}"
shift || true

case "$TARGET" in
    ssh) ssh_control "$@" ;;
    vnc) vnc_control "$@" ;;
    public) public_control "$@" ;;
    status|"")
        ssh_control status
        vnc_control status
        public_control status
        ;;
    *)
        echo "Usage: asl remote [ssh|vnc|public] [start|stop|status]"
        exit 1
        ;;
esac
