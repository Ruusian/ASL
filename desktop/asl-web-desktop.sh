#!/bin/bash
# ASL: Autonomous Web-Accessible Remote Desktop (TigerVNC + noVNC + WebSockify)
# Serves interactive Debian XFCE4 desktop over HTML5 canvas on port 6080

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
STATE_FILE="$PREFIX/tmp/.asl-desktop.active"
VNC_LOG="$PREFIX/tmp/web-desktop-vnc.log"
SOCK_LOG="$PREFIX/tmp/web-desktop-sock.log"

export PATH="$PREFIX/bin:$PATH"

is_vnc_running() {
    pgrep -f "Xtigervnc :1" >/dev/null 2>&1 || (timeout 1 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/5901') 2>/dev/null
}

is_websockify_running() {
    pgrep -f "websockify.*6080" >/dev/null 2>&1 || (timeout 1 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/6080') 2>/dev/null
}

start_web_desktop() {
    echo "[*] Initializing ASL Debian Linux Web Desktop (XFCE4 + noVNC)..."
    
    # 1. Ensure chroot is mounted
    if ! [ -d "$DEBIANPATH/proc/1" ]; then
        if [ -f "$TERMUX_HOME/ASL/bin/asl" ]; then
            bash "$TERMUX_HOME/ASL/bin/asl" start >/dev/null 2>&1 || true
        fi
    fi

    # 2. Setup ~/.vnc/xstartup inside Debian chroot if missing
    if ! [ -f "$DEBIANPATH/root/.vnc/xstartup" ]; then
        su -c "mkdir -p '$DEBIANPATH/root/.vnc' && cat << 'XEOF' > '$DEBIANPATH/root/.vnc/xstartup'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export DISPLAY=:1
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP=\"XFCE\"
export XDG_MENU_PREFIX=\"xfce-\"
[ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup
[ -r \$HOME/.Xresources ] && xrdb \$HOME/.Xresources
which xfce4-session >/dev/null && exec xfce4-session
exec startxfce4
XEOF
chmod 755 '$DEBIANPATH/root/.vnc/xstartup'" 2>/dev/null || true
    fi
    
    # Ensure noVNC index.html symlink exists
    if [ -f "$DEBIANPATH/usr/share/novnc/vnc.html" ] && [ ! -f "$DEBIANPATH/usr/share/novnc/index.html" ]; then
        su -c "ln -sf /usr/share/novnc/vnc.html '$DEBIANPATH/usr/share/novnc/index.html'" 2>/dev/null || true
    fi

    # 3. Clean any stale locks on display :1
    su -c "rm -f '$DEBIANPATH/tmp/.X1-lock' '$DEBIANPATH/tmp/.X11-unix/X1'" 2>/dev/null || true

    # 4. Start TigerVNC server on :1 (port 5901)
    if ! is_vnc_running; then
        echo "[*] Starting TigerVNC server on display :1 (1280x720 24-bit)..."
        su -c "chroot '$DEBIANPATH' /usr/bin/tigervncserver :1 -SecurityTypes None -geometry 1280x720 -depth 16 -FrameRate 60 -CompareFB 1 --I-KNOW-THIS-IS-INSECURE" >> "$VNC_LOG" 2>&1 || true
        sleep 2
    fi

    # 5. Start websockify proxy on port 6080 -> 127.0.0.1:5901
    if ! is_websockify_running; then
        echo "[*] Starting WebSockify noVNC bridge on port 6080..."
        su -c "chroot '$DEBIANPATH' /usr/bin/nohup /usr/bin/python3 /usr/bin/websockify --web=/usr/share/novnc 6080 127.0.0.1:5901 >> '$SOCK_LOG' 2>&1 &" || true
        sleep 1
    fi

    for _retry in 1 2 3 4 5 6; do
        if is_vnc_running && is_websockify_running; then
            touch "$STATE_FILE" 2>/dev/null || true
            echo "[✓] ASL Debian Linux Web Desktop is LIVE on port 6080!"
            echo "    Local URL:   http://localhost:6080/vnc.html?autoconnect=true&resize=remote"
            echo "    Public URL:  https://desktop.144.24.122.241.sslip.io/vnc.html?autoconnect=true&resize=remote"
            return 0
        fi
        sleep 1
    done

    echo "[!] Warning: Web Desktop startup incomplete. Check logs:"
    echo "    $VNC_LOG"
    echo "    $SOCK_LOG"
    return 1
}

stop_web_desktop() {
    echo "[*] Stopping ASL Debian Linux Web Desktop..."
    
    # 1. Stop websockify
    su -c "killall -9 websockify 2>/dev/null || pkill -9 -f 'websockify.*6080' 2>/dev/null || true" 2>/dev/null || true

    # 2. Stop TigerVNC server on :1
    su -c "chroot '$DEBIANPATH' /usr/bin/tigervncserver -kill :1" >> "$VNC_LOG" 2>&1 || true
    su -c "killall -9 Xtigervnc 2>/dev/null || pkill -9 -f 'Xtigervnc :1' 2>/dev/null || true" 2>/dev/null || true
    
    # 3. Clean lingering display processes
    su -c "rm -f '$DEBIANPATH/tmp/.X1-lock' '$DEBIANPATH/tmp/.X11-unix/X1'" 2>/dev/null || true
    rm -f "$STATE_FILE" 2>/dev/null || true

    # 4. Flush caches & reclaim memory
    sync
    su -c "echo 3 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true" 2>/dev/null || true

    echo "[✓] ASL Debian Linux Web Desktop stopped. Graphical memory reclaimed."
    return 0
}

status_web_desktop() {
    local vnc_ok=0 sock_ok=0
    is_vnc_running && vnc_ok=1
    is_websockify_running && sock_ok=1

    if [ "$vnc_ok" -eq 1 ] && [ "$sock_ok" -eq 1 ]; then
        echo "WEB_DESKTOP_ACTIVE (Port 6080, Display :1, noVNC Ready)"
    elif [ "$vnc_ok" -eq 1 ]; then
        echo "WEB_DESKTOP_VNC_ONLY (Port 5901 active, WebSockify stopped)"
    else
        echo "WEB_DESKTOP_STOPPED"
    fi
}

case "${1:-status}" in
    start) start_web_desktop ;;
    stop) stop_web_desktop ;;
    restart) stop_web_desktop; sleep 1; start_web_desktop ;;
    status|"") status_web_desktop ;;
    *) echo "Usage: asl-web-desktop.sh [start|stop|restart|status]"; exit 1 ;;
esac
