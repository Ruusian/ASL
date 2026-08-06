#!/bin/bash
# AndroidLinux-SuperKit: Remote Access Bridge (SSH & VNC)

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

is_mounted() {
    su -c "grep -q -w '$DEBIANPATH/proc' /proc/mounts" 2>/dev/null
}

ensure_mounted() {
    if ! is_mounted; then
        bash "${0%/*}/../core/mount-chroot.sh" || exit 1
    fi
}

ssh_control() {
    local action="${1:-status}"
    case "$action" in
        start)
            ensure_mounted
            echo "[*] Checking SSH server installation..."
            if ! su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/sbin/sshd" 2>/dev/null; then
                echo "[*] Installing openssh-server inside Debian chroot..."
                su -c "chroot '$DEBIANPATH' /usr/bin/apt-get update && chroot '$DEBIANPATH' /usr/bin/apt-get install -y openssh-server" || return 1
            fi
            su -c "chroot '$DEBIANPATH' /usr/bin/ssh-keygen -A" 2>/dev/null || true
            su -c "chroot '$DEBIANPATH' /bin/mkdir -p /var/run/sshd" 2>/dev/null || true
            if su -c "chroot '$DEBIANPATH' /usr/bin/pgrep -x sshd" >/dev/null 2>&1; then
                echo "[*] SSH server is already running."
            else
                echo "[*] Starting SSH daemon on port 2222..."
                su -c "chroot '$DEBIANPATH' /usr/sbin/sshd -p 2222" || return 1
                echo "[✓] SSH server active. Connect via: ssh root@127.0.0.1 -p 2222"
            fi
            ;;
        stop)
            if is_mounted && su -c "chroot '$DEBIANPATH' /usr/bin/pgrep -x sshd" >/dev/null 2>&1; then
                su -c "chroot '$DEBIANPATH' /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; pkill -TERM -f sshd 2>/dev/null'" || true
                echo "[✓] SSH daemon stopped."
            else
                echo "[*] SSH server is not running."
            fi
            ;;
        status|"")
            if is_mounted && su -c "chroot '$DEBIANPATH' /usr/bin/pgrep -x sshd" >/dev/null 2>&1; then
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
            if ! su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/x11vnc" 2>/dev/null; then
                echo "[*] Installing x11vnc inside Debian chroot..."
                su -c "chroot '$DEBIANPATH' /usr/bin/apt-get update && chroot '$DEBIANPATH' /usr/bin/apt-get install -y x11vnc" || return 1
            fi
            if su -c "chroot '$DEBIANPATH' /usr/bin/pgrep -x x11vnc" >/dev/null 2>&1; then
                echo "[*] VNC server is already running."
            else
                echo "[*] Starting x11vnc server on port 5900..."
                su -c "chroot '$DEBIANPATH' /bin/bash -c 'export DISPLAY=:0; x11vnc -display :0 -forever -shared -rfbport 5900 -nopw -bg >/dev/null 2>&1'" || return 1
                echo "[✓] VNC server active. Connect via VNC client to 127.0.0.1:5900."
            fi
            ;;
        stop)
            if is_mounted && su -c "chroot '$DEBIANPATH' /usr/bin/pgrep -x x11vnc" >/dev/null 2>&1; then
                su -c "chroot '$DEBIANPATH' /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; pkill -TERM -f x11vnc 2>/dev/null'" || true
                echo "[✓] VNC server stopped."
            else
                echo "[*] VNC server is not running."
            fi
            ;;
        status|"")
            if is_mounted && su -c "chroot '$DEBIANPATH' /usr/bin/pgrep -x x11vnc" >/dev/null 2>&1; then
                echo "VNC Server: RUNNING (port 5900)"
            else
                echo "VNC Server: STOPPED"
            fi
            ;;
    esac
}

TARGET="${1:-status}"
shift || true

case "$TARGET" in
    ssh) ssh_control "$@" ;;
    vnc) vnc_control "$@" ;;
    status|"")
        ssh_control status
        vnc_control status
        ;;
    *)
        echo "Usage: superkit remote [ssh|vnc] [start|stop|status]"
        exit 1
        ;;
esac
