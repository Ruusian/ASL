#!/bin/bash
# AndroidLinux-SuperKit: managed Termux:X11, PulseAudio, and XFCE lifecycle.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/gpu-profile.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/superkit/desktop"
STATE_FILE="$STATE_DIR/state"
LAUNCHER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_state_dir() {
    mkdir -p "$STATE_DIR" || return 1
    chmod 700 "$STATE_DIR"
}

pid_start_time() {
    [ -n "${1:-}" ] || return 1
    su -c 'awk '\''{print $22}'\'' /proc/'"$1"'/stat 2>/dev/null' || awk '{print $22}' "/proc/$1/stat" 2>/dev/null
}

process_matches() {
    local pid="$1" expected="$2" start="$3" actual cmd
    actual=$(pid_start_time "$pid")
    [ -n "$actual" ] || return 1
    [ "$actual" = "$start" ] || return 1
    cmd=$(su -c 'tr '\''\0'\'' '\'' '\'' < /proc/'"$1"'/cmdline 2>/dev/null')
    if [ -z "$cmd" ] && [ -r "/proc/$pid/cmdline" ]; then
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
    fi
    [ -n "$cmd" ] || return 1
    [[ "$cmd" == *"$expected"* ]]
}

read_state() {
    [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] || return 1
    [ "$(stat -c %U "$STATE_FILE" 2>/dev/null)" = "$(id -un)" ] || return 1
    unset DISPLAY_ID X11_PID X11_START SESSION_PID SESSION_START PULSE_PID PULSE_START PULSE_OWNED SOCAT_PID SOCAT_START
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            DISPLAY_ID|X11_PID|X11_START|SESSION_PID|SESSION_START|PULSE_PID|PULSE_START|PULSE_OWNED|SOCAT_PID|SOCAT_START)
                printf -v "$key" '%s' "$value"
                ;;
            *) return 1 ;;
        esac
    done < "$STATE_FILE"
    [[ "${DISPLAY_ID:-}" =~ ^:[0-9]+$ ]] || return 1
    [[ "${X11_PID:-}" =~ ^[0-9]+$ && "${X11_START:-}" =~ ^[0-9]+$ ]] || return 1
    [[ "${SESSION_PID:-}" =~ ^[0-9]+$ && "${SESSION_START:-}" =~ ^[0-9]+$ ]] || return 1
    [[ "${PULSE_OWNED:-0}" =~ ^[01]$ ]] || return 1
}

write_state() {
    umask 077
    local tmp="$STATE_FILE.tmp.$$"
    {
        printf 'DISPLAY_ID=%s\n' "$DISPLAY_ID"
        printf 'X11_PID=%s\nX11_START=%s\n' "$X11_PID" "$X11_START"
        printf 'SESSION_PID=%s\nSESSION_START=%s\n' "$SESSION_PID" "$SESSION_START"
        printf 'PULSE_OWNED=%s\nPULSE_PID=%s\nPULSE_START=%s\n' "$PULSE_OWNED" "$PULSE_PID" "$PULSE_START"
        printf 'SOCAT_PID=%s\nSOCAT_START=%s\n' "$SOCAT_PID" "$SOCAT_START"
    } > "$tmp" && mv -f "$tmp" "$STATE_FILE"
}

start_audio() {
    PULSE_OWNED=0 PULSE_PID= PULSE_START=
    if pgrep -x pulseaudio >/dev/null; then
        echo "[*] Reusing existing PulseAudio server."
        return 0
    fi
    if ! command -v pulseaudio >/dev/null; then
        echo "[!] PulseAudio is not installed. Install it with: pkg install pulseaudio"
        return 1
    fi
    echo "[*] Initializing PulseAudio sound server..."
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null || return 1
    PULSE_PID=$(pgrep -xo pulseaudio || true)
    [ -n "$PULSE_PID" ] || return 1
    PULSE_START=$(pid_start_time "$PULSE_PID")
    [ -n "$PULSE_START" ] || return 1
    PULSE_OWNED=1
    echo "[✓] PulseAudio server active."
}

start_gpu() {
    VIRGL_OWNED=0 VIRGL_PID= VIRGL_START=
    if pgrep -x virgl_test_server_android >/dev/null || pgrep -f virgl_test_server >/dev/null; then
        echo "[*] Reusing active VirGL GPU hardware acceleration server."
        [ -S /tmp/.virgl_test ] && chmod 777 /tmp/.virgl_test 2>/dev/null || true
        return 0
    fi
    if command -v virgl_test_server_android >/dev/null; then
        echo "[*] Initializing VirGL GPU hardware acceleration server (ANGLE)..."
        virgl_test_server_android --angle-gl >/dev/null 2>&1 &
        VIRGL_PID=$!
        VIRGL_START=$(pid_start_time "$VIRGL_PID")
        VIRGL_OWNED=1
        sleep 1
        [ -S /tmp/.virgl_test ] && chmod 777 /tmp/.virgl_test 2>/dev/null || true
        echo "[✓] VirGL GPU hardware acceleration active."
    fi
}

cleanup_started() {
    if [ -n "${SESSION_PID:-}" ] && process_matches "$SESSION_PID" "xfwm4" "$SESSION_START"; then su -c "kill -TERM $SESSION_PID" 2>/dev/null || true; fi
    if [ -n "${SOCAT_PID:-}" ] && process_matches "$SOCAT_PID" "socat" "$SOCAT_START"; then kill -TERM "$SOCAT_PID" 2>/dev/null || true; fi
    if [ -n "${X11_PID:-}" ] && process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || true; fi
    if [ "${PULSE_OWNED:-0}" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || true; fi
}

start_desktop() {
    ensure_state_dir || { echo "[!] Cannot create SuperKit state directory."; return 1; }
    if read_state; then
        if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START"; then
            echo "[*] Desktop is already running on $DISPLAY_ID."
            return 0
        fi
        rm -f "$STATE_FILE"
    fi
    command -v termux-x11 >/dev/null || { echo "[!] Termux:X11 client is not installed. Install it with: pkg install termux-x11"; return 1; }
    local missing=""
    su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/xfwm4" 2>/dev/null || missing="xfwm4"
    su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/xfdesktop" 2>/dev/null || missing="$missing${missing:+ }xfdesktop4"
    su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/dbus-launch" 2>/dev/null || missing="$missing${missing:+ }dbus-x11"
    su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/dbus-daemon" 2>/dev/null || missing="$missing${missing:+ }dbus"
    su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/xfsettingsd" 2>/dev/null || missing="$missing${missing:+ }xfce4-settings"
    if [ -n "$missing" ]; then
        echo "[!] Missing Debian packages: $missing"
        echo "    Install inside chroot: apt install $missing"
        return 1
    fi
    start_audio || return 1
    start_gpu || true
    echo "[*] Optimizing system memory before desktop startup..."
    su -c "sync; echo 3 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory" 2>/dev/null || true
    DISPLAY_ID=:0
    am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
    echo "[*] Starting Termux:X11 display server..."
    if ! pgrep -f "termux-x11.*:[0-9]" >/dev/null; then
        rm -f "/data/data/com.termux/files/usr/tmp/.X11-unix/X0" "/data/data/com.termux/files/usr/tmp/.X0-lock" 2>/dev/null || true
        termux-x11 "$DISPLAY_ID" +iglx -ac >/dev/null 2>&1 &
        sleep 1
    fi
    X11_PID=$(pgrep -f "termux-x11.*:[0-9]" | head -n1 || true)
    local _i
    X11_START=
    for _i in 1 2 3; do
        [ -n "$X11_PID" ] && X11_START=$(pid_start_time "$X11_PID")
        [ -n "$X11_START" ] && break
        sleep 1
    done
    [ -n "$X11_START" ] || { echo "[!] Termux:X11 failed to start."; cleanup_started; return 1; }
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        if su -c "grep -q '/data/data/com.termux/files/usr/tmp/.X11-unix/X0' /proc/net/unix" 2>/dev/null; then
            break
        fi
        if [ "$_i" -eq 10 ]; then
            echo "[!] Termux:X11 display socket is not accepting connections."
            cleanup_started
            return 1
        fi
        sleep 1
    done
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    mkdir -p "$termux_tmp/.X11-unix"
    rm -f "$termux_tmp/.X11-unix/X0" 2>/dev/null || true
    if command -v socat >/dev/null 2>&1; then
        socat UNIX-LISTEN:"$termux_tmp/.X11-unix/X0",fork,mode=777 ABSTRACT-CONNECT:"$termux_tmp/.X11-unix/X0" >/dev/null 2>&1 &
        SOCAT_PID=$!
        SOCAT_START=$(pid_start_time "$SOCAT_PID")
    fi
    superkit_gpu_apply
    echo "[*] Launching XFCE4 Desktop inside chroot (hardware acceleration)..."
    [ -S /tmp/.virgl_test ] && chmod 777 /tmp/.virgl_test 2>/dev/null || true
    mkdir -p "$termux_tmp"
    local launcher_script="$termux_tmp/superkit-start-xfce.sh"
    umask 022
    cat << LAUNCHER_EOF > "$launcher_script"
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LD_PRELOAD=/usr/local/lib/libno_close_range.so
# Sanitize environment — remove leaked Termux/Android vars
for v in \$(env | grep -oP '^(TERMUX|SHELL_CMD|ANDROID|OPENAI|CLAUDE|OPENCLAUDE|COREPACK|NODE_OPTIONS|DEX2OAT|BOOTCLASS|SYSTEMSERVER|GIT_EDITOR|ASEC_|NoDefault)[A-Za-z_]*'); do
    unset "\$v"
done
export DISPLAY=:0
export TMPDIR=/tmp
export PULSE_SERVER=tcp:127.0.0.1
export TERM=xterm-256color
export LANG=C.UTF-8
export HOME=/root
export USER=root
export SHELL=/bin/bash
export XDG_RUNTIME_DIR=/run/user/0
export NO_AT_BRIDGE=1
export GIO_USE_PORTALS=0
export GIO_USE_VFS=local
export WEBKIT_FORCE_SANDBOX=0
export QT_QPA_PLATFORM=xcb
export QT_QPA_PLATFORMTHEME=gtk2
export QT_STYLE_OVERRIDE=gtk2
export MESA_SHADER_CACHE_DIR=/tmp/.cache
export GALLIUM_DRIVER="virpipe"
export MESA_GL_VERSION_OVERRIDE=4.0
export MESA_VK_WINSYS="x11"

mkdir -p /run/user/0 2>/dev/null
chmod 700 /run/user/0 2>/dev/null
mkdir -p /tmp/.cache 2>/dev/null

rm -f /tmp/xfce-keepalive
mkfifo /tmp/xfce-keepalive
exec dbus-run-session -- bash -c '
    xfwm4 --replace --compositor=off >> /tmp/xfce-xfwm4.log 2>&1 &
    sleep 1
    xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus-Dark 2>/dev/null || xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s Papirus-Dark 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/ThemeName -s Arc-Dark 2>/dev/null || xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s Arc-Dark 2>/dev/null || true
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s Breeze_Snow 2>/dev/null || xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s Breeze_Snow 2>/dev/null || true
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 28 2>/dev/null || xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 28 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/Antialias -s 1 2>/dev/null || xfconf-query -c xsettings -p /Xft/Antialias -n -t int -s 1 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/Hinting -s 1 2>/dev/null || xfconf-query -c xsettings -p /Xft/Hinting -n -t int -s 1 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/HintStyle -s hintslight 2>/dev/null || xfconf-query -c xsettings -p /Xft/HintStyle -n -t string -s hintslight 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/RGBA -s rgb 2>/dev/null || xfconf-query -c xsettings -p /Xft/RGBA -n -t string -s rgb 2>/dev/null || true
    sleep 1
    xfce4-panel >> /tmp/xfce-panel.log 2>&1 &
    xfdesktop >> /tmp/xfce-desktop.log 2>&1 &
    xfsettingsd >> /tmp/xfce-settings.log 2>&1 &
    thunar --daemon >> /tmp/xfce-thunar.log 2>&1 &
    exec 3<>/tmp/xfce-keepalive
    read <&3
'
LAUNCHER_EOF
    chmod 755 "$launcher_script"
    su -c "chroot '$DEBIANPATH' /bin/bash /tmp/superkit-start-xfce.sh" >/dev/null 2>&1 &
    SESSION_PID=
    SESSION_START=
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        for pid in $(su -c "chroot '$DEBIANPATH' /usr/bin/pgrep -x xfwm4" 2>/dev/null); do
            st=$(pid_start_time "$pid")
            if [ -n "$st" ] && process_matches "$pid" "xfwm4" "$st"; then
                SESSION_PID="$pid"
                SESSION_START="$st"
                break 2
            fi
        done
        sleep 1
    done
    if [ -z "$SESSION_PID" ] || [ -z "$SESSION_START" ]; then
        echo "[!] XFCE desktop failed to start (xfwm4 not running)."
        cleanup_started
        return 1
    fi
    if ! process_matches "$SESSION_PID" "xfwm4" "$SESSION_START"; then
        echo "[!] XFCE window manager exited during startup."
        cleanup_started
        return 1
    fi
    write_state || { cleanup_started; return 1; }
    echo "[✓] Desktop started on $DISPLAY_ID. Open the Termux:X11 Android app."
}

stop_desktop() {
    if ! read_state; then
        echo "[*] No SuperKit-managed desktop session is active."
        return 0
    fi
    local failed=0 pid
    echo "[*] Stopping SuperKit-managed desktop..."
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START"; then su -c "kill -TERM $SESSION_PID" 2>/dev/null || failed=1; fi
    su -c "chroot '$DEBIANPATH' /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; killall -TERM xfwm4 xfdesktop xfce4-panel xfsettingsd xfce4-session 2>/dev/null'" 2>/dev/null || true
    sleep 1
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START"; then su -c "kill -KILL $SESSION_PID" 2>/dev/null || failed=1; fi
    if process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || failed=1; fi
    if [ -n "${SOCAT_PID:-}" ] && process_matches "$SOCAT_PID" "socat" "$SOCAT_START"; then kill -TERM "$SOCAT_PID" 2>/dev/null || true; fi
    if [ "$PULSE_OWNED" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || failed=1; fi
    if [ "$failed" -ne 0 ]; then echo "[!] Desktop shutdown was incomplete."; return 1; fi
    rm -f "$STATE_FILE"
    echo "[✓] SuperKit-managed desktop stopped."
}

force_stop_desktop() {
    echo "[*] Force-stopping all GUI, X11, GPU, and audio processes..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; killall -9 xfce4-session xfwm4 xfdesktop xfce4-panel xfsettingsd xfconfd dbus-daemon dbus-launch 2>/dev/null'" 2>/dev/null || true
    pkill -9 -x termux-x11 2>/dev/null || true
    pkill -9 -x virgl_test_server_android 2>/dev/null || true
    pkill -9 -x pulseaudio 2>/dev/null || true
    pkill -9 -f "superkit-start-xfce|socat" 2>/dev/null || true
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    rm -rf "$termux_tmp/.X11-unix"/X* "$STATE_FILE" "$STATE_FILE.tmp."* 2>/dev/null || true
    sleep 1
    echo "[✓] Complete stop: All GUI processes terminated and state cleared."
}

status_desktop() {
    if ! read_state; then echo "Desktop: STOPPED"; return 0; fi
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START"; then
        echo "Desktop: RUNNING ($DISPLAY_ID)"
        process_matches "$X11_PID" "termux-x11" "$X11_START" || echo "Warning: Termux:X11 process is not running."
        return 0
    else
        echo "Desktop: STALE STATE"
        return 1
    fi
}

safe_id() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

launch_app() {
    local id="${1:-}" root
    safe_id "$id" || { echo "[!] Invalid desktop application ID."; return 1; }
    for root in /usr/share/applications /usr/local/share/applications /root/.local/share/applications; do
        if su -c "chroot '$DEBIANPATH' /usr/bin/test -f '$root/$id.desktop'" 2>/dev/null; then
            exec su -c "chroot '$DEBIANPATH' /usr/bin/gtk-launch '$id'"
        fi
    done
    echo "[!] Debian desktop entry not found: $id"
    return 1
}

sync_apps() {
    if ! su -c "mountpoint -q '$DEBIANPATH/proc'" 2>/dev/null; then echo "[!] Mount the Debian chroot before synchronizing apps."; return 1; fi
    mkdir -p "$LAUNCHER_DIR" || return 1
    local file root id name target tmp count=0
    for target in "$LAUNCHER_DIR"/superkit-*.desktop; do
        [ -f "$target" ] && [ ! -L "$target" ] && grep -qx 'X-SuperKit-Managed=true' "$target" && rm -f "$target"
    done
    while IFS= read -r -d '' file; do
        root=
        for candidate in /usr/share/applications /usr/local/share/applications /root/.local/share/applications; do
            [[ "$file" == "$candidate/"* ]] && root="$candidate" && break
        done
        [ -n "$root" ] || continue
        id=$(basename "$file" .desktop)
        safe_id "$id" || continue
        name=$(su -c "chroot '$DEBIANPATH' /usr/bin/awk -F= 'BEGIN { type=\"\"; hidden=0; nodisplay=0 } /^Type=/{type=\$2} /^Hidden=true$/{hidden=1} /^NoDisplay=true$/{nodisplay=1} /^Name=/{if (name == \"\") name=substr(\$0, 6)} END {if (type == \"Application\" && !hidden && !nodisplay && name != \"\") print name}' '$root/$id.desktop'" 2>/dev/null) || continue
        [ -n "$name" ] || continue
        target="$LAUNCHER_DIR/superkit-$id.desktop"; tmp="$target.tmp.$$"
        umask 077
        {
            printf '[Desktop Entry]\nType=Application\nName=%s\n' "${name//$'\n'/ }"
            printf 'Exec=%s desktop launch %s\n' "${0%/*}/../bin/superkit" "$id"
            printf 'Terminal=false\nX-SuperKit-Managed=true\nX-SuperKit-Desktop-Id=%s\n' "$id"
        } > "$tmp" && mv -f "$tmp" "$target" && count=$((count + 1))
    done < <(su -c "chroot '$DEBIANPATH' /usr/bin/find /usr/share/applications /usr/local/share/applications /root/.local/share/applications -type f -name '*.desktop' -print0 2>/dev/null" 2>/dev/null)
    echo "[✓] Synchronized $count SuperKit-owned launchers."
}

case "${1:-start}" in
    start|"") start_desktop ;;
    stop) stop_desktop ;;
    force-stop|kill) force_stop_desktop ;;
    restart) force_stop_desktop && start_desktop ;;
    status) status_desktop ;;
    audio) start_audio ;;
    sync-apps) sync_apps ;;
    launch) shift; launch_app "$@" ;;
    *) echo "Usage: start-desktop.sh {start|stop|force-stop|restart|status|audio|sync-apps|launch}"; exit 1 ;;
esac
