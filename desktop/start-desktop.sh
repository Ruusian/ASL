#!/bin/bash
# ASL: managed Termux:X11, PulseAudio, and XFCE lifecycle.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi
source "$SCRIPT_DIR/core/gpu-profile.sh"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/asl/desktop"
STATE_FILE="$STATE_DIR/state"
LAUNCHER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MAXMAP_BACKUP="/data/local/tmp/asl_desktop_max_map_count"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_state_dir() {
    mkdir -p "$STATE_DIR" || return 1
    chmod 700 "$STATE_DIR"
}

protect_pid_oom() {
    local pid="${1:-}"
    [ -n "$pid" ] || return 0
    if [ "${ASL_EXEC_MODE:-root}" = "root" ]; then
        asl_exec "echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null || true" 2>/dev/null || true
    fi
}

pid_start_time() {
    [ -n "${1:-}" ] || return 1
    asl_exec 'export PATH="/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin:$PATH"; awk '\''{print $22}'\'' /proc/'"$1"'/stat 2>/dev/null' || awk '{print $22}' "/proc/$1/stat" 2>/dev/null
}

process_matches() {
    local pid="$1" expected="$2" start="$3" actual cmd
    actual=$(pid_start_time "$pid")
    [ -n "$actual" ] || return 1
    [ "$actual" = "$start" ] || return 1
    cmd=$(asl_exec 'export PATH="/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin:$PATH"; tr '\''\0'\'' '\'' '\'' < /proc/'"$1"'/cmdline 2>/dev/null')
    if [ -z "$cmd" ] && [ -r "/proc/$pid/cmdline" ]; then
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
    fi
    [ -n "$cmd" ] || return 1
    [[ "$cmd" == *"$expected"* ]]
}

# Kill processes jailed in the chroot whose comm/cmdline matches an ERE pattern.
# The chroot's /proc is a bind mount of the host /proc, so a bare `pkill -f`
# run inside the chroot can kill HOST processes whose cmdline merely contains
# the pattern. Guarding on /proc/<pid>/root restricts the kill to processes
# actually jailed in $DEBIANPATH. The guard must run from the host root view:
# from inside the chroot, every process (host or chroot) resolves to "/".
# Note: $pat is expanded by the outer shell; all other vars run under su.
chroot_pkill() {
    local sig="$1" pat="$2"
    asl_exec "
        for pid in \$(pgrep -f '$pat' 2>/dev/null); do
            [ \"\$(readlink \"/proc/\$pid/root\" 2>/dev/null)\" = \"$DEBIANPATH\" ] && kill $sig \"\$pid\" 2>/dev/null || true
        done
    " 2>/dev/null || true
}

host_pkill() {
    local sig="$1" pat="$2"
    asl_exec "
        for pid in \$(pgrep -f '$pat' 2>/dev/null); do
            [ \"\$(readlink \"/proc/\$pid/root\" 2>/dev/null)\" = \"/\" ] && kill $sig \"\$pid\" 2>/dev/null || true
        done
    " 2>/dev/null || true
}

read_state() {
    [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] || return 1
    [ "$(stat -c %U "$STATE_FILE" 2>/dev/null)" = "$(id -un)" ] || return 1
    unset DISPLAY_ID X11_PID X11_START SESSION_PID SESSION_START PULSE_PID PULSE_START PULSE_OWNED SOCAT_PID SOCAT_START
    local key value
    while IFS='=' read -r -u 3 key value; do
        case "$key" in
            DISPLAY_ID|X11_PID|X11_START|SESSION_PID|SESSION_START|PULSE_PID|PULSE_START|PULSE_OWNED|SOCAT_PID|SOCAT_START)
                printf -v "$key" '%s' "$value"
                ;;
            *) return 1 ;;
        esac
    done 3< "$STATE_FILE"
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
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 tsched=0" --load="module-native-protocol-unix socket=/tmp/pulse-socket auth-anonymous=1 tsched=0" --exit-idle-time=-1 2>/dev/null || true
    sleep 1
    PULSE_PID=$(pgrep -xo pulseaudio || true)
    [ -n "$PULSE_PID" ] || return 1
    PULSE_START=$(pid_start_time "$PULSE_PID")
    [ -n "$PULSE_START" ] || return 1
    PULSE_OWNED=1
    protect_pid_oom "$PULSE_PID"
    echo "[✓] PulseAudio server active."
}

start_gpu() {
    VIRGL_OWNED=0 VIRGL_PID= VIRGL_START=
    asl_gpu_detect
    if [ "$ASL_GPU_PROFILE" = "adreno-turnip-zink" ]; then
        echo "[*] Direct Adreno Turnip + Zink Vulkan acceleration active; VirGL server not needed."
        return 0
    fi
    if pgrep -x virgl_test_server_android >/dev/null || pgrep -f virgl_test_server >/dev/null; then
        echo "[*] Reusing active VirGL GPU hardware acceleration server."
        [ -S /tmp/.virgl_test ] && chmod 700 /tmp/.virgl_test 2>/dev/null || true
        return 0
    fi
    if command -v virgl_test_server_android >/dev/null; then
        echo "[*] Initializing VirGL GPU hardware acceleration server (ANGLE)..."
        virgl_test_server_android --angle-gl >/dev/null 2>&1 &
        VIRGL_PID=$!
        VIRGL_START=$(pid_start_time "$VIRGL_PID")
        VIRGL_OWNED=1
        protect_pid_oom "$VIRGL_PID"
        sleep 1
        [ -S /tmp/.virgl_test ] && chmod 700 /tmp/.virgl_test 2>/dev/null || true
        echo "[✓] VirGL GPU hardware acceleration active."
    fi
}

cleanup_started() {
    if [ -n "${SESSION_PID:-}" ] && (process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"); then asl_exec "kill -TERM $SESSION_PID" 2>/dev/null || true; fi
    if [ -n "${SOCAT_PID:-}" ] && process_matches "$SOCAT_PID" "socat" "$SOCAT_START"; then kill -TERM "$SOCAT_PID" 2>/dev/null || true; fi
    if [ -n "${X11_PID:-}" ] && process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || true; fi
    if [ "${PULSE_OWNED:-0}" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || true; fi
    rm -f /tmp/.X11-unix/X0 /tmp/.X0-lock "$DEBIANPATH/tmp/.X11-unix/X0" "$DEBIANPATH/tmp/.X0-lock" 2>/dev/null || true
}

start_desktop() {
    ensure_state_dir || { echo "[!] Cannot create ASL state directory."; return 1; }
    if read_state; then
        if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"; then
            echo "[*] Desktop is already running on $DISPLAY_ID."
            return 0
        fi
        rm -f "$STATE_FILE"
    fi
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null || true
    fi
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    if ! pgrep -f "termux-x11.*:[0-9]" >/dev/null; then
        rm -f "$termux_tmp/.X11-unix/X0" "$termux_tmp/.X0-lock" "$DEBIANPATH/tmp/.X11-unix/X0" "$DEBIANPATH/tmp/.X0-lock" 2>/dev/null || true
    fi
    command -v termux-x11 >/dev/null || { echo "[!] Termux:X11 client is not installed. Install it with: pkg install termux-x11"; return 1; }
    local missing=""
    asl_chroot_exec "/usr/bin/test -x /usr/bin/xfwm4" 2>/dev/null || missing="xfwm4"
    asl_chroot_exec "/usr/bin/test -x /usr/bin/xfdesktop" 2>/dev/null || missing="$missing${missing:+ }xfdesktop4"
    asl_chroot_exec "/usr/bin/test -x /usr/bin/dbus-launch" 2>/dev/null || missing="$missing${missing:+ }dbus-x11"
    asl_chroot_exec "/usr/bin/test -x /usr/bin/dbus-daemon" 2>/dev/null || missing="$missing${missing:+ }dbus"
    asl_chroot_exec "/usr/bin/test -x /usr/bin/xfsettingsd" 2>/dev/null || missing="$missing${missing:+ }xfce4-settings"
    if [ -n "$missing" ]; then
        echo "[!] Missing Debian packages: $missing"
        echo "    Install inside chroot: apt install $missing"
        return 1
    fi
    start_audio || return 1
    start_gpu || true
    DISPLAY_ID=:0
    am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
    echo "[*] Starting Termux:X11 display server..."
    if ! pgrep -f "termux-x11.*:[0-9]" >/dev/null; then
        rm -f "/data/data/com.termux/files/usr/tmp/.X11-unix/X0" "/data/data/com.termux/files/usr/tmp/.X0-lock" 2>/dev/null || true
        # -ac disables X host access control (Termux:X11's auth model relies on
        # the socket being reachable by chroot clients without xauth). The X
        # socket is exposed only via the socat bridge above with mode=700, so
        # access is limited to the Termux user + root rather than any local app.
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
    [ -n "$X11_START" ] || { echo "[!] Termux:X11 failed to start."; echo "    💡 Hint: Ensure Termux:X11 companion app is installed and open on your device."; cleanup_started; return 1; }
    protect_pid_oom "$X11_PID"
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        if [ -S "$termux_tmp/.X11-unix/X0" ] || asl_exec "grep -q -E '\.X11-unix/X0' /proc/net/unix 2>/dev/null" 2>/dev/null; then
            break
        fi
        if [ "$_i" -eq 10 ]; then
            echo "[!] Termux:X11 display socket is not accepting connections."
            echo "    💡 Hint: Open Termux:X11 app manually from Android launcher and retry."
            cleanup_started
            return 1
        fi
        sleep 1
    done
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    mkdir -p "$termux_tmp/.X11-unix"
    if [ ! -S "$termux_tmp/.X11-unix/X0" ] && command -v socat >/dev/null 2>&1; then
        # mode=700: only the Termux user (plus root, who bypasses mode checks)
        # may connect to the X socket; world-accessible 777 would let any local
        # app drive the display.
        socat UNIX-LISTEN:"$termux_tmp/.X11-unix/X0",fork,mode=700 ABSTRACT-CONNECT:"$termux_tmp/.X11-unix/X0" >/dev/null 2>&1 &
        SOCAT_PID=$!
        SOCAT_START=$(pid_start_time "$SOCAT_PID")
        protect_pid_oom "$SOCAT_PID"
    fi
    asl_gpu_apply
    asl_sync_chroot_env 2>/dev/null || true
    echo "[*] Launching XFCE4 Desktop inside chroot (hardware acceleration)..."
    [ -S /tmp/.virgl_test ] && chmod 700 /tmp/.virgl_test 2>/dev/null || true
    local asl_target_user="${ASL_USER:-root}"
    local target_home="/root"
    local target_uid=0
    if [ "$asl_target_user" != "root" ]; then
        target_home="/home/$asl_target_user"
        target_uid=$(asl_chroot_exec "id -u '$asl_target_user' 2>/dev/null" 2>/dev/null || echo 1000)
        [ -n "$target_uid" ] || target_uid=1000
    fi
    mkdir -p "$termux_tmp"
    local launcher_script="$termux_tmp/asl-start-xfce.sh"
    umask 022
    cat << LAUNCHER_EOF > "$launcher_script"
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ -f /usr/local/lib/libno_close_range.so ] && export LD_PRELOAD=/usr/local/lib/libno_close_range.so
# Sanitize environment — remove leaked Termux/Android vars
for v in \$(env | grep -E -o '^(TERMUX|SHELL_CMD|ANDROID|OPENAI|CLAUDE|OPENCLAUDE|COREPACK|NODE_OPTIONS|DEX2OAT|BOOTCLASS|SYSTEMSERVER|GIT_EDITOR|ASEC_|NoDefault)[A-Za-z_]*'); do
    unset "\$v"
done
export DISPLAY=:0
export TMPDIR=/tmp
export PULSE_SERVER=unix:/tmp/pulse-socket,tcp:127.0.0.1
export TERM=xterm-256color
export LANG=C.UTF-8
export HOME=$target_home
export USER=$asl_target_user
export SHELL=/bin/bash
export XDG_RUNTIME_DIR=/run/user/$target_uid
export XDG_MENU_PREFIX=xfce-
export XDG_DATA_DIRS=/usr/local/share:/usr/share
export XDG_CONFIG_DIRS=/etc/xdg
export NO_AT_BRIDGE=1
export GIO_USE_PORTALS=0
export GIO_USE_VFS=local
export WEBKIT_FORCE_SANDBOX=0
export QT_QPA_PLATFORMTHEME=gtk2
export QT_STYLE_OVERRIDE=gtk2
$(asl_gpu_env_exports)

mkdir -p /run/user/0 /dev/shm/mesa_shader_cache 2>/dev/null
chmod 700 /run/user/0 2>/dev/null
mkdir -p /tmp/.cache 2>/dev/null

# Start the D-Bus system bus (the session bus is started below via dbus-run-session).
mkdir -p /run/dbus 2>/dev/null
if ! pgrep -f "dbus-daemon --system" >/dev/null 2>&1; then
    rm -f /run/dbus/system_bus_socket 2>/dev/null
    /usr/bin/dbus-daemon --system >/tmp/dbus-system.log 2>&1 &
fi

rm -f /tmp/xfce-keepalive 2>/dev/null
(
    sleep 3
    export DISPLAY=:0
    xrandr --newmode "1280x720" 74.50 1280 1344 1472 1664 720 723 728 748 -hsync +vsync 2>/dev/null || true
    xrandr --addmode builtin "1280x720" 2>/dev/null || true
    xrandr --newmode "1600x900" 118.25 1600 1696 1856 2112 900 903 908 934 -hsync +vsync 2>/dev/null || true
    xrandr --addmode builtin "1600x900" 2>/dev/null || true
    xrandr --newmode "1366x768" 85.50 1366 1436 1579 1792 768 771 774 798 -hsync +vsync 2>/dev/null || true
    xrandr --addmode builtin "1366x768" 2>/dev/null || true
    xrandr --newmode "1024x768" 65.00 1024 1048 1184 1344 768 771 777 806 -hsync +vsync 2>/dev/null || true
    xrandr --addmode builtin "1024x768" 2>/dev/null || true
    xrandr --newmode "800x600" 40.00 800 840 920 1056 600 601 605 628 +hsync +vsync 2>/dev/null || true
    xrandr --addmode builtin "800x600" 2>/dev/null || true

    xfconf-query -c xfwm4 -p /general/titleless_fullscreen -s true 2>/dev/null || xfconf-query -c xfwm4 -p /general/titleless_fullscreen -n -t bool -s true 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/borderless_maximize -s true 2>/dev/null || xfconf-query -c xfwm4 -p /general/borderless_maximize -n -t bool -s true 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/box_move -s false 2>/dev/null || xfconf-query -c xfwm4 -p /general/box_move -n -t bool -s false 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/box_resize -s false 2>/dev/null || xfconf-query -c xfwm4 -p /general/box_resize -n -t bool -s false 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus-Dark 2>/dev/null || xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s Papirus-Dark 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/ThemeName -s Arc-Dark 2>/dev/null || xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s Arc-Dark 2>/dev/null || true
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s Breeze_Light 2>/dev/null || xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s Breeze_Light 2>/dev/null || true
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 28 2>/dev/null || xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 28 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/Antialias -s 1 2>/dev/null || xfconf-query -c xsettings -p /Xft/Antialias -n -t int -s 1 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/Hinting -s 1 2>/dev/null || xfconf-query -c xsettings -p /Xft/Hinting -n -t int -s 1 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/HintStyle -s hintslight 2>/dev/null || xfconf-query -c xsettings -p /Xft/HintStyle -n -t string -s hintslight 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/RGBA -s rgb 2>/dev/null || xfconf-query -c xsettings -p /Xft/RGBA -n -t string -s rgb 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s /usr/share/backgrounds/xfce/xfce-blue.jpg 2>/dev/null || xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -n -t string -s /usr/share/backgrounds/xfce/xfce-blue.jpg 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/image-style -s 5 2>/dev/null || xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/image-style -n -t int -s 5 2>/dev/null || true
) &

if command -v startxfce4 >/dev/null 2>&1; then
    exec dbus-run-session startxfce4
elif command -v xfce4-session >/dev/null 2>&1; then
    exec dbus-run-session xfce4-session
else
    exec dbus-run-session xfwm4
fi
LAUNCHER_EOF
    chmod 755 "$launcher_script"
    cp -f "$launcher_script" "$termux_tmp/asl-start-xfce.sh" 2>/dev/null || true
    case "${ASL_EXEC_MODE:-root}" in
        proot|shizuku)
            asl_chroot_exec "/bin/bash /tmp/asl-start-xfce.sh" >/dev/null 2>&1 &
            ;;
        root|*)
            if [ "$asl_target_user" = "root" ]; then
                if asl_chroot_exec "test -x /usr/bin/setpriv" 2>/dev/null; then
                    asl_exec "chroot '$DEBIANPATH' /usr/bin/setpriv --reuid=0 --regid=0 --init-groups /bin/bash /tmp/asl-start-xfce.sh" >/dev/null 2>&1 &
                else
                    asl_chroot_exec "/bin/bash /tmp/asl-start-xfce.sh" >/dev/null 2>&1 &
                fi
            else
                if asl_chroot_exec "test -x /usr/bin/setpriv" 2>/dev/null; then
                    asl_exec "chroot '$DEBIANPATH' /usr/bin/setpriv --reuid='$asl_target_user' --regid='$asl_target_user' --init-groups /bin/bash /tmp/asl-start-xfce.sh" >/dev/null 2>&1 &
                else
                    asl_chroot_exec "su - '$asl_target_user' -s /bin/bash /tmp/asl-start-xfce.sh" >/dev/null 2>&1 &
                fi
            fi
            ;;
    esac
    SESSION_PID=
    SESSION_START=
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        for pid in $(asl_chroot_exec "pgrep -x xfwm4 || pgrep -x xfce4-session" 2>/dev/null); do
            st=$(pid_start_time "$pid")
            if [ -n "$st" ] && (process_matches "$pid" "xfwm4" "$st" || process_matches "$pid" "xfce4-session" "$st"); then
                SESSION_PID="$pid"
                SESSION_START="$st"
                break 2
            fi
        done
        sleep 1
    done
    if [ -z "$SESSION_PID" ] || [ -z "$SESSION_START" ]; then
        echo "[!] XFCE desktop failed to start (session process not running)."
        cleanup_started
        return 1
    fi
    if ! (process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"); then
        echo "[!] XFCE desktop process exited during startup."
        cleanup_started
        return 1
    fi
    write_state || { cleanup_started; return 1; }
    echo "[✓] Desktop started on $DISPLAY_ID. Open the Termux:X11 Android app."
}

stop_desktop() {
    if ! read_state; then
        echo "[*] No ASL-managed desktop session is active."
        return 0
    fi
    local failed=0 pid
    echo "[*] Stopping ASL-managed desktop..."
    # Wine shutdown can block indefinitely under Box64. Terminate only
    # processes actually rooted in this chroot, then continue cleanup.
    chroot_pkill TERM '\b(wine|wine64|wineserver|box64)\b'
    sleep 1
    chroot_pkill 9 '\b(wine|wine64|wineserver|box64)\b'
    chroot_pkill TERM '\b(xfwm4|xfdesktop|xfce4-panel|xfsettingsd|xfce4-session|xfconfd|xfconf-query|picom)\b'
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"; then asl_exec "kill -TERM $SESSION_PID" 2>/dev/null || failed=1; fi
    sleep 1
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"; then asl_exec "kill -KILL $SESSION_PID" 2>/dev/null || failed=1; fi
    sleep 1
    chroot_pkill TERM '\b(asl-start-xfce|dbus-run-session|dbus-daemon)\b'
    chroot_pkill 9 '\b(asl-start-xfce|dbus-run-session|sleep)\b'
    if process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || failed=1; fi
    if [ -n "${SOCAT_PID:-}" ] && process_matches "$SOCAT_PID" "socat" "$SOCAT_START"; then kill -TERM "$SOCAT_PID" 2>/dev/null || true; fi
    if [ "$PULSE_OWNED" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || failed=1; fi
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    rm -rf "$termux_tmp/.X0-lock" "$termux_tmp/.X11-unix"/X* "$DEBIANPATH/tmp/.X0-lock" "$DEBIANPATH/tmp/xfce-keepalive" "$DEBIANPATH/run/dbus/system_bus_socket" "$DEBIANPATH/tmp/.X11-vnc" "$DEBIANPATH/tmp/.vnc"/*.pid 2>/dev/null || true
    if [ "$failed" -ne 0 ]; then echo "[!] Desktop shutdown was incomplete."; return 1; fi
    rm -f "$STATE_FILE"
    if command -v termux-wake-unlock >/dev/null 2>&1; then
        termux-wake-unlock 2>/dev/null || true
    fi
    echo "[✓] ASL-managed desktop stopped."
}

force_stop_desktop() {
    echo "[*] Force-stopping all GUI, X11, GPU, Wine, Box64, and audio processes..."
    # Do not invoke wineserver -k: it may block indefinitely under Box64.
    chroot_pkill TERM '\b(wine|wine64|wineserver|box64)\b'
    sleep 1
    chroot_pkill 9 '\b(wine|wine64|wineserver|box64|xfce4-session|xfwm4|xfdesktop|xfce4-panel|xfsettingsd|xfconfd|xfconf-query|picom|dbus-daemon|dbus-launch|x11vnc)\b'
    chroot_pkill 9 '\b(asl-start-xfce)\b'
    host_pkill 9 '\b(termux-x11|virgl_test_server_android|pulseaudio|socat)\b'
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    rm -rf "$termux_tmp/.X11-unix"/X* "$termux_tmp/.X0-lock" "$DEBIANPATH/tmp/.X0-lock" "$DEBIANPATH/tmp/xfce-keepalive" "$DEBIANPATH/run/dbus/system_bus_socket" "$DEBIANPATH/tmp/.X11-vnc" "$DEBIANPATH/tmp/.vnc"/*.pid "$STATE_FILE" "$STATE_FILE.tmp."* 2>/dev/null || true
    sleep 1
    echo "[✓] Complete stop: All GUI and gaming processes terminated and state cleared."
}

status_desktop() {
    if ! read_state; then echo "Desktop: STOPPED"; return 0; fi
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"; then
        echo "Desktop: RUNNING ($DISPLAY_ID)"
        process_matches "$X11_PID" "termux-x11" "$X11_START" || echo "Warning: Termux:X11 process is not running."
        return 0
    else
        echo "Desktop: STALE STATE"
        return 0
    fi
}

refresh_x11_state() {
    if ! read_state; then return 0; fi
    local new_pid new_start _i
    new_pid=$(pgrep -f "termux-x11.*:[0-9]" | head -n1 || true)
    [ -n "$new_pid" ] || { echo "[!] Termux:X11 process not found."; return 1; }
    new_start=
    for _i in 1 2 3; do
        new_start=$(pid_start_time "$new_pid")
        [ -n "$new_start" ] && break
        sleep 1
    done
    [ -n "$new_start" ] || { echo "[!] Could not read Termux:X11 start time."; return 1; }
    X11_PID="$new_pid"
    X11_START="$new_start"
    write_state || return 1
    echo "[✓] Termux:X11 state updated."
}

safe_id() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

launch_app() {
    local id="${1:-}" root
    safe_id "$id" || { echo "[!] Invalid desktop application ID."; return 1; }
    for root in /usr/share/applications /usr/local/share/applications /root/.local/share/applications; do
        if asl_chroot_exec "test -f '$root/$id.desktop'" 2>/dev/null; then
            asl_chroot_exec "export DISPLAY=:0; export XDG_DATA_DIRS=/usr/local/share:/usr/share; export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH; /usr/bin/gtk-launch \"$id.desktop\" 2>/dev/null || /usr/bin/gtk-launch \"$id\""
        fi
    done
    echo "[!] Debian desktop entry not found: $id"
    return 1
}

sync_apps() {
    if ! is_mounted; then echo "[!] Mount the Debian chroot before synchronizing apps."; return 1; fi
    mkdir -p "$LAUNCHER_DIR" || return 1
    local file root id name target tmp count=0
    for target in "$LAUNCHER_DIR"/asl-*.desktop; do
        [ -f "$target" ] && [ ! -L "$target" ] && grep -qx 'X-ASL-Managed=true' "$target" && rm -f "$target"
    done
    while IFS= read -r -d '' file; do
        root=
        for candidate in /usr/share/applications /usr/local/share/applications /root/.local/share/applications; do
            [[ "$file" == "$candidate/"* ]] && root="$candidate" && break
        done
        [ -n "$root" ] || continue
        id=$(basename "$file" .desktop)
        safe_id "$id" || continue
        name=$(asl_chroot_exec "awk -F= 'BEGIN { type=\"\"; hidden=0; nodisplay=0 } /^Type=/{type=\$2} /^Hidden=true$/{hidden=1} /^NoDisplay=true$/{nodisplay=1} /^Name=/{if (name == \"\") name=substr(\$0, 6)} END {if (type == \"Application\" && !hidden && !nodisplay && name != \"\") print name}' '$root/$id.desktop'" 2>/dev/null) || continue
        [ -n "$name" ] || continue
        target="$LAUNCHER_DIR/asl-$id.desktop"; tmp="$target.tmp.$$"
        umask 077
        {
            printf '[Desktop Entry]\nType=Application\nName=%s\n' "${name//$'\n'/ }"
            printf 'Exec="%s" desktop launch %s\n' "${0%/*}/../bin/asl" "$id"
            printf 'Terminal=false\nX-ASL-Managed=true\nX-ASL-Desktop-Id=%s\n' "$id"
        } > "$tmp" && mv -f "$tmp" "$target" && count=$((count + 1))
    done < <(asl_chroot_exec "find /usr/share/applications /usr/local/share/applications /root/.local/share/applications -type f -name '*.desktop' -print0 2>/dev/null" 2>/dev/null)
    echo "[✓] Synchronized $count ASL-owned launchers."
}

audio_control() {
    local action="${1:-status}" level="${2:-}"
    case "$action" in
        start) start_audio ;;
        stop)
            if read_state && [ "$PULSE_OWNED" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then
                if kill -TERM "$PULSE_PID" 2>/dev/null; then
                    PULSE_OWNED=0 PULSE_PID= PULSE_START=
                    write_state || return 1
                    echo "[✓] ASL-managed PulseAudio stopped."
                else
                    echo "[!] Failed to stop ASL-managed PulseAudio."
                    return 1
                fi
            else
                echo "[*] No ASL-managed PulseAudio server is running."
            fi
            ;;
        status|"")
            if pgrep -x pulseaudio >/dev/null 2>&1; then
                echo "PulseAudio Server: RUNNING"
            else
                echo "PulseAudio Server: STOPPED"
            fi
            ;;
        test)
            if ! pgrep -x pulseaudio >/dev/null; then start_audio || return 1; fi
            echo "[*] Playing audio test tone..."
            if command -v paplay >/dev/null; then
                paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || echo "[*] Audio pipeline active."
            else
                echo "[!] paplay is not installed in Termux."
            fi
            ;;
        volume)
            if [ -n "$level" ]; then
                if command -v pactl >/dev/null; then
                    pactl set-sink-volume @DEFAULT_SINK@ "${level}%" 2>/dev/null && echo "[✓] Master volume set to ${level}%." || echo "[!] pactl failed to set volume."
                else
                    echo "[!] pactl is not installed in Termux."
                fi
            else
                echo "Usage: asl audio volume <0-100>"
            fi
            ;;
        *) echo "Usage: start-desktop.sh audio {start|stop|test|volume <level>}" ;;
    esac
}

case "${1:-start}" in
    start|"") start_desktop ;;
    stop) stop_desktop ;;
    force-stop|kill) force_stop_desktop ;;
    restart) force_stop_desktop && start_desktop ;;
    status) status_desktop ;;
    refresh-x11) refresh_x11_state ;;
    audio) shift; audio_control "$@" ;;
    sync-apps) sync_apps ;;
    launch) shift; launch_app "$@" ;;
    *) echo "Usage: start-desktop.sh {start|stop|force-stop|restart|status|refresh-x11|audio|sync-apps|launch}"; exit 1 ;;
esac
