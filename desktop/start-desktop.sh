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
export TMPDIR="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
mkdir -p "$TMPDIR" 2>/dev/null || true

asl_require_default_debianpath

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
    asl_exec 'export PATH="/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin:$PATH"; awk '\''{sub(/^.*\)/, ""); print $20}'\'' /proc/'"$1"'/stat 2>/dev/null' 2>/dev/null || awk '{sub(/^.*\)/, ""); print $20}' "/proc/$1/stat" 2>/dev/null
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
    unset DISPLAY_ID X11_PID X11_START SESSION_PID SESSION_START PULSE_PID PULSE_START PULSE_OWNED SOCAT_PID SOCAT_START LAUNCHER_PID VIRGL_PID VIRGL_START VIRGL_OWNED
    local key value
    while IFS='=' read -r -u 3 key value; do
        case "$key" in
            DISPLAY_ID|X11_PID|X11_START|SESSION_PID|SESSION_START|PULSE_PID|PULSE_START|PULSE_OWNED|SOCAT_PID|SOCAT_START|LAUNCHER_PID|VIRGL_PID|VIRGL_START|VIRGL_OWNED)
                printf -v "$key" '%s' "$value"
                ;;
            *) return 1 ;;
        esac
    done 3< "$STATE_FILE"
    [[ "${DISPLAY_ID:-}" =~ ^:[0-9]+$ ]] || return 1
    [[ "${X11_PID:-}" =~ ^[0-9]+$ && "${X11_START:-}" =~ ^[0-9]+$ ]] || return 1
    [[ "${SESSION_PID:-}" =~ ^[0-9]+$ && "${SESSION_START:-}" =~ ^[0-9]+$ ]] || return 1
    [[ "${PULSE_OWNED:-0}" =~ ^[01]$ ]] || return 1
    [[ "${VIRGL_OWNED:-0}" =~ ^[01]$ ]] || return 1
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
        printf 'LAUNCHER_PID=%s\n' "${LAUNCHER_PID:-}"
        printf 'VIRGL_OWNED=%s\nVIRGL_PID=%s\nVIRGL_START=%s\n' "${VIRGL_OWNED:-0}" "${VIRGL_PID:-}" "${VIRGL_START:-}"
    } > "$tmp" && mv -f "$tmp" "$STATE_FILE"
}

start_audio() {
    PULSE_OWNED=0 PULSE_PID='' PULSE_START=''
    export PULSE_SERVER="${PULSE_SERVER:-127.0.0.1}"
    if pgrep -x pulseaudio >/dev/null 2>&1 || pactl info >/dev/null 2>&1; then
        echo "[*] Reusing existing PulseAudio server."
        return 0
    fi
    if ! command -v pulseaudio >/dev/null; then
        echo "[!] PulseAudio is not installed. Install it with: pkg install pulseaudio"
        return 1
    fi
    echo "[*] Initializing PulseAudio sound server..."
    if [ "$(id -u)" = "0" ] && [ -f /etc/debian_version ]; then
        pulseaudio --system --disallow-exit --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 tsched=0" --load="module-native-protocol-unix socket=/tmp/pulse-socket auth-anonymous=1 tsched=0" --daemonize 2>/dev/null || \
        pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 tsched=0" --load="module-native-protocol-unix socket=/tmp/pulse-socket auth-anonymous=1 tsched=0" --exit-idle-time=-1 2>/dev/null || true
    else
        pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 tsched=0" --load="module-native-protocol-unix socket=/tmp/pulse-socket auth-anonymous=1 tsched=0" --exit-idle-time=-1 2>/dev/null || true
    fi
    sleep 1
    if pactl info >/dev/null 2>&1; then
        echo "[✓] PulseAudio server active."
        return 0
    fi
    PULSE_PID=$(pgrep -xo pulseaudio || true)
    if [ -n "$PULSE_PID" ]; then
        PULSE_START=$(pid_start_time "$PULSE_PID")
        PULSE_OWNED=1
        protect_pid_oom "$PULSE_PID"
        echo "[✓] PulseAudio server active."
        return 0
    fi
    echo "[!] Failed to connect to or start PulseAudio server."
    return 1
}

start_gpu() {
    VIRGL_OWNED=0 VIRGL_PID='' VIRGL_START=''
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

start_vnc() {
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    if [ ! -S "$termux_tmp/.X11-unix/X0" ] && command -v socat >/dev/null 2>&1; then
        socat UNIX-LISTEN:"$termux_tmp/.X11-unix/X0",fork,mode=700 ABSTRACT-CONNECT:"$termux_tmp/.X11-unix/X0" >/dev/null 2>&1 &
    fi
    if ! asl_chroot_exec "pgrep -f 'x11vnc.*:0'" >/dev/null 2>&1; then
        echo "[*] Initializing x11vnc server on DISPLAY :0..."
        asl_exec "chroot '$DEBIANPATH' /usr/bin/nohup /usr/bin/x11vnc \
            -display :0 -noshm -forever -shared -nopw -loop -rfbport 5900 \
            -threads -nap -nowait_bog \
            -wait 10 -defer 10 -deferupdate 20 \
            -ncache 10 -ncache_cr \
            -wireframe -scrollcopyrect always \
            -speeds 250,100,50 \
            -cursor arrow -noxdamage \
            >'$DEBIANPATH/tmp/x11vnc.log' 2>&1 &" || true
    fi
    if ! asl_chroot_exec "pgrep -f 'websockify.*6080'" >/dev/null 2>&1; then
        echo "[*] Initializing noVNC websockify bridge on port 6080..."
        asl_exec "chroot '$DEBIANPATH' /usr/bin/nohup /usr/bin/python3 /usr/bin/websockify --web /usr/share/novnc 6080 localhost:5900 >'$DEBIANPATH/tmp/websockify.log' 2>&1 &" || true
    fi
}

cleanup_started() {
    if [ -n "${SESSION_PID:-}" ] && (process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"); then asl_exec "kill -TERM $SESSION_PID" 2>/dev/null || true; fi
    if [ -n "${SOCAT_PID:-}" ] && process_matches "$SOCAT_PID" "socat" "$SOCAT_START"; then kill -TERM "$SOCAT_PID" 2>/dev/null || true; fi
    if [ -n "${X11_PID:-}" ] && process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || true; fi
    if [ "${PULSE_OWNED:-0}" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || true; fi
    if [ -n "${VIRGL_OWNED:-0}" ] && [ "${VIRGL_OWNED:-0}" = 1 ] && [ -n "${VIRGL_PID:-}" ] && process_matches "$VIRGL_PID" "virgl_test_server" "$VIRGL_START"; then kill -TERM "$VIRGL_PID" 2>/dev/null || true; fi
    if [ -n "${LAUNCHER_PID:-}" ]; then kill -TERM "$LAUNCHER_PID" 2>/dev/null || true; fi
    rm -f /tmp/.X11-unix/X0 /tmp/.X0-lock "$DEBIANPATH/tmp/.X11-unix/X0" "$DEBIANPATH/tmp/.X0-lock" 2>/dev/null || true
}

start_desktop() {
    ensure_state_dir || { echo "[!] Cannot create ASL state directory."; return 1; }
    if read_state; then
        if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"; then
            echo "[*] Desktop is already running on $DISPLAY_ID."
            start_vnc 2>/dev/null || true
            return 0
        fi
        rm -f "$STATE_FILE"
    fi
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null || true
    fi
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    if ! pgrep -f "termux-x11.*:[0-9]" >/dev/null; then
        echo "[*] Cleaning up orphaned X11 display sockets and lock files..."
        rm -f "$termux_tmp"/.X*-lock "$termux_tmp"/.X11-unix/X* "$DEBIANPATH/tmp"/.X*-lock "$DEBIANPATH/tmp"/.X11-unix/X* /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
    fi
    command -v termux-x11 >/dev/null || { echo "[!] Termux:X11 client is not installed. Install it with: pkg install termux-x11"; return 1; }
    local missing=""
    if ! asl_chroot_exec "test -x /usr/bin/xfwm4 -o -x /usr/bin/xfce4-session -o -x /usr/bin/openbox" 2>/dev/null; then
        missing="xfwm4/xfce4-session"
    fi
    if [ -n "$missing" ]; then
        echo "[!] Missing Debian desktop environment packages: $missing"
        echo "    Install inside chroot: apt install xfce4 xfce4-terminal xfwm4"
        return 1
    fi
    start_audio 2>/dev/null || echo "[!] Notice: PulseAudio audio server disabled or not installed."
    start_gpu || true
    DISPLAY_ID=:0
    am start -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
    echo "[*] Starting Termux:X11 display server..."
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    local xauth_file="$termux_tmp/.Xauthority"
    local xauth_cmd=""
    if command -v xauth >/dev/null 2>&1; then
        xauth_cmd="xauth"
    fi
    local xauth_cookie
    xauth_cookie=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')
    if [ -n "$xauth_cmd" ] && [ -n "$xauth_cookie" ]; then
        $xauth_cmd -f "$xauth_file" add "$DISPLAY_ID" MIT-MAGIC-COOKIE-1 "$xauth_cookie" 2>/dev/null || true
        chmod 600 "$xauth_file" 2>/dev/null || true
    fi
    if ! pgrep -f "termux-x11.*:[0-9]" >/dev/null; then
        rm -f "/data/data/com.termux/files/usr/tmp/.X11-unix/X0" "/data/data/com.termux/files/usr/tmp/.X0-lock" 2>/dev/null || true
        if [ -f "$xauth_file" ] && [ -s "$xauth_file" ]; then
            termux-x11 "$DISPLAY_ID" +iglx -nolisten tcp -auth "$xauth_file" >/dev/null 2>&1 &
        else
            termux-x11 "$DISPLAY_ID" +iglx -nolisten tcp >/dev/null 2>&1 &
        fi
        sleep 1
    fi
    X11_PID=$(pgrep -n -f "termux-x11.*:0" || pgrep -f "termux-x11.*:[0-9]" | head -n1 || true)
    local _i
    X11_START=
    for _i in 1 2 3; do
        [ -n "$X11_PID" ] && X11_START=$(pid_start_time "$X11_PID")
        [ -n "$X11_START" ] && break
        sleep 1
    done
    [ -n "$X11_START" ] || { echo "[!] Termux:X11 failed to start."; echo "    💡 Hint: Ensure Termux:X11 companion app is installed and open on your device."; cleanup_started; return 1; }
    protect_pid_oom "$X11_PID"
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
    chroot_pkill 9 '(^|[^A-Za-z0-9_])(xfwm4|xfdesktop|xfce4-panel|xfsettingsd|xfce4-session|xfconfd|light-locker)([^A-Za-z0-9_]|$)'
    [ -S /tmp/.virgl_test ] && chmod 700 /tmp/.virgl_test 2>/dev/null || true
    local asl_target_user="${ASL_USER:-root}"
    if [[ ! "$asl_target_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "Error: Invalid ASL_USER value: $asl_target_user" >&2
        return 1
    fi
    local target_home="/root"
    local target_uid=0
    if [ "$asl_target_user" != "root" ]; then
        target_home="/home/$asl_target_user"
        target_uid=$(asl_chroot_exec "id -u '$asl_target_user' 2>/dev/null" 2>/dev/null || echo 1000)
        [ -n "$target_uid" ] || target_uid=1000
    fi
    local gpu_exports
    gpu_exports=$(asl_gpu_env_exports 2>/dev/null || true)
    mkdir -p "$termux_tmp"
    local launcher_script
    launcher_script=$(mktemp "$termux_tmp/asl-start-xfce-XXXXXX.sh" 2>/dev/null) || launcher_script="$termux_tmp/asl-start-xfce-${EUID:-$$}.sh"
    umask 022
    cat << LAUNCHER_EOF > "$launcher_script"
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ -f /usr/local/lib/libdisable_close_range.so ] && export LD_PRELOAD=/usr/local/lib/libdisable_close_range.so
[ -f /usr/local/lib/libno_close_range.so ] && export LD_PRELOAD=/usr/local/lib/libno_close_range.so
# Sanitize environment — remove leaked Termux/Android vars
for v in \$(env | grep -E -o '^(TERMUX|SHELL_CMD|ANDROID|OPENAI|CLAUDE|OPENCLAUDE|COREPACK|NODE_OPTIONS|DEX2OAT|BOOTCLASS|SYSTEMSERVER|GIT_EDITOR|ASEC_|NoDefault)[A-Za-z_]*'); do
    unset "\$v"
done
export DISPLAY=:0
export XAUTHORITY=/tmp/.Xauthority
export TMPDIR=/tmp
export PULSE_SERVER=127.0.0.1:4713
export TERM=xterm-256color
export LANG=C.UTF-8
export HOME=$target_home
export USER=$asl_target_user
export SHELL=/bin/bash
export XDG_RUNTIME_DIR=/run/user/$target_uid
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$target_uid/bus
export XDG_MENU_PREFIX=xfce-
export XDG_DATA_DIRS=/usr/local/share:/usr/share
export XDG_CONFIG_DIRS=/etc/xdg
export NO_AT_BRIDGE=1
export GIO_USE_PORTALS=0
export GIO_USE_VFS=local
export WEBKIT_FORCE_SANDBOX=0
export QT_QPA_PLATFORMTHEME=gtk2
export QT_STYLE_OVERRIDE=gtk2
export GSK_RENDERER=cairo
$gpu_exports

mkdir -p /etc/pulse "$target_home/.config/pulse" "$target_home/Desktop" "$target_home/.config/gtk-3.0" /run/user/$target_uid /dev/shm/mesa_shader_cache 2>/dev/null
for app_id in asl-hub code chromium thunar xfce4-terminal synaptic pavucontrol; do
    if [ -f "/usr/share/applications/${app_id}.desktop" ] && [ ! -f "$target_home/Desktop/${app_id}.desktop" ]; then
        cp -f "/usr/share/applications/${app_id}.desktop" "$target_home/Desktop/" 2>/dev/null || true
    fi
done
for f in "$target_home/Desktop"/*.desktop; do
    if [ -f "$f" ]; then
        chmod +x "$f" 2>/dev/null || true
        chk=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
        gio set -t string "$f" metadata::xfce-exe-checksum "$chk" 2>/dev/null || true
        gio set -t string "$f" metadata::trusted true 2>/dev/null || true
    fi
done
if [ ! -f "$target_home/.config/gtk-3.0/settings.ini" ]; then
cat << 'GTK3_EOF' > "$target_home/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Blacklight
gtk-icon-theme-name=bes-icon-black
gtk-cursor-theme-name=Blacklight
gtk-cursor-theme-size=28
gtk-font-name=Sans 10.5
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
gtk-application-prefer-dark-theme=1
GTK3_EOF
fi
if [ ! -f "$target_home/.gtkrc-2.0" ]; then
cat << 'GTK2_EOF' > "$target_home/.gtkrc-2.0"
gtk-theme-name = "Blacklight"
gtk-icon-theme-name = "bes-icon-black"
gtk-font-name = "Sans 10.5"
gtk-cursor-theme-name = "Blacklight"
gtk-cursor-theme-size = 28
gtk-xft-antialias = 1
gtk-xft-hinting = 1
gtk-xft-hintstyle = "hintslight"
gtk-xft-rgba = "rgb"
GTK2_EOF
fi
[ -f /tmp/.Xauthority ] && cp -f /tmp/.Xauthority "$target_home/.Xauthority" 2>/dev/null && chmod 600 "$target_home/.Xauthority" 2>/dev/null || true
ln -sf /usr/share/applications/org.pulseaudio.pavucontrol.desktop /usr/share/applications/pavucontrol.desktop 2>/dev/null || true
cat << 'PULSE_CONF_EOF' > /etc/pulse/client.conf
default-server = 127.0.0.1:4713
autospawn = no
enable-shm = no
PULSE_CONF_EOF
cp /etc/pulse/client.conf "$target_home/.config/pulse/client.conf" 2>/dev/null || true
cat << 'ALSA_CONF_EOF' > /etc/asound.conf
pcm.!default {
    type pulse
}
ctl.!default {
    type pulse
}
ALSA_CONF_EOF
chmod 700 /run/user/$target_uid 2>/dev/null
if [ "$asl_target_user" != "root" ]; then
    chown "$asl_target_user:$asl_target_user" "/run/user/$target_uid" "$target_home/.Xauthority" 2>/dev/null || true
    chown -R "$asl_target_user:$asl_target_user" "$target_home/.config/pulse" 2>/dev/null || true
fi
mkdir -p /tmp/.cache 2>/dev/null

# Start system and session D-Bus daemons on standard socket paths
mkdir -p /run/dbus /run/user/$target_uid 2>/dev/null
chmod 700 /run/user/$target_uid 2>/dev/null
if ! pgrep -f "dbus-daemon --system" >/dev/null 2>&1; then
    rm -f /run/dbus/system_bus_socket 2>/dev/null
    /usr/bin/dbus-daemon --system >/tmp/dbus-system.log 2>&1 &
fi

rm -f /run/user/$target_uid/bus 2>/dev/null
/usr/bin/dbus-daemon --session --address=unix:path=/run/user/$target_uid/bus >/tmp/dbus-session.log 2>&1 &
sleep 0.5
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$target_uid/bus

rm -f /tmp/xfce-keepalive 2>/dev/null
(
    sleep 2
    export DISPLAY=:0
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$target_uid/bus
    xhost + 2>/dev/null || true
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
    xfconf-query -c xsettings -p /Xft/Antialias -s 1 2>/dev/null || xfconf-query -c xsettings -p /Xft/Antialias -n -t int -s 1 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/Hinting -s 1 2>/dev/null || xfconf-query -c xsettings -p /Xft/Hinting -n -t int -s 1 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/HintStyle -s hintslight 2>/dev/null || xfconf-query -c xsettings -p /Xft/HintStyle -n -t string -s hintslight 2>/dev/null || true
    xfconf-query -c xsettings -p /Xft/RGBA -s rgb 2>/dev/null || xfconf-query -c xsettings -p /Xft/RGBA -n -t string -s rgb 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/style -s 2 2>/dev/null || xfconf-query -c xfce4-desktop -p /desktop-icons/style -n -t int -s 2 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/icon-size -s 48 2>/dev/null || xfconf-query -c xfce4-desktop -p /desktop-icons/icon-size -n -t int -s 48 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -s true 2>/dev/null || xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -n -t bool -s true 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -s true 2>/dev/null || xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -n -t bool -s true 2>/dev/null || true
) &

rm -f /etc/xdg/autostart/light-locker.desktop "$HOME/.config/autostart/light-locker.desktop" 2>/dev/null || true

if command -v xfce4-session >/dev/null 2>&1; then
    exec dbus-run-session xfce4-session
elif command -v startxfce4 >/dev/null 2>&1; then
    exec dbus-run-session startxfce4
elif [ -x /usr/bin/startxfce4 ]; then
    exec /usr/bin/startxfce4
elif [ -x /usr/bin/xfce4-session ]; then
    exec /usr/bin/xfce4-session
else
    exec /usr/bin/xfwm4
fi
LAUNCHER_EOF
    chmod 755 "$launcher_script" 2>/dev/null || true
    asl_exec "mkdir -p '$DEBIANPATH/tmp' && cp -f '$launcher_script' '$DEBIANPATH/tmp/asl-start-xfce.sh' && chmod 755 '$DEBIANPATH/tmp/asl-start-xfce.sh'" 2>/dev/null || cp -f "$launcher_script" "$DEBIANPATH/tmp/asl-start-xfce.sh" 2>/dev/null || true
    rm -f "$launcher_script" 2>/dev/null || true
    LAUNCHER_PID=
    case "${ASL_EXEC_MODE:-root}" in
        proot|shizuku)
            asl_chroot_exec "/bin/bash /tmp/asl-start-xfce.sh >/tmp/asl-xfce-launch.log 2>&1" &
            LAUNCHER_PID=$!
            ;;
        root|*)
            if [ "$asl_target_user" = "root" ]; then
                if asl_chroot_exec "test -x /usr/bin/setpriv" 2>/dev/null; then
                    asl_exec "chroot '$DEBIANPATH' /usr/bin/setpriv --reuid=0 --regid=0 --init-groups /bin/bash /tmp/asl-start-xfce.sh >'$DEBIANPATH/tmp/asl-xfce-launch.log' 2>&1" &
                    LAUNCHER_PID=$!
                else
                    asl_chroot_exec "/bin/bash /tmp/asl-start-xfce.sh >/tmp/asl-xfce-launch.log 2>&1" &
                    LAUNCHER_PID=$!
                fi
            else
                if asl_chroot_exec "test -x /usr/bin/setpriv" 2>/dev/null; then
                    asl_exec "chroot '$DEBIANPATH' /usr/bin/setpriv --reuid='$asl_target_user' --regid='$asl_target_user' --init-groups /bin/bash /tmp/asl-start-xfce.sh >'$DEBIANPATH/tmp/asl-xfce-launch.log' 2>&1" &
                    LAUNCHER_PID=$!
                else
                    asl_chroot_exec "su - '$asl_target_user' -s /bin/bash /tmp/asl-start-xfce.sh >/tmp/asl-xfce-launch.log 2>&1" &
                    LAUNCHER_PID=$!
                fi
            fi
            ;;
    esac
    SESSION_PID=
    SESSION_START=
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        for pid in $(asl_chroot_exec "pgrep -f 'xfwm4|xfce4-session|startxfce4|asl-start-xfce'" 2>/dev/null); do
            st=$(pid_start_time "$pid")
            if [ -n "$st" ] && (process_matches "$pid" "xfwm4" "$st" || process_matches "$pid" "xfce4-session" "$st" || process_matches "$pid" "startxfce4" "$st" || process_matches "$pid" "asl-start-xfce" "$st"); then
                SESSION_PID="$pid"
                SESSION_START="$st"
                break 2
            fi
        done
        sleep 1
    done
    if [ -z "$SESSION_PID" ] || [ -z "$SESSION_START" ]; then
        echo "[!] XFCE desktop failed to start (session process not running)."
        if asl_exec "test -f '$DEBIANPATH/tmp/asl-xfce-launch.log'" 2>/dev/null; then
            echo "    --- Startup Diagnostics (/tmp/asl-xfce-launch.log) ---"
            asl_exec "cat '$DEBIANPATH/tmp/asl-xfce-launch.log'" 2>/dev/null || true
            echo "    -------------------------------------------------------"
        fi
        cleanup_started
        return 1
    fi
    if ! (process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START" || process_matches "$SESSION_PID" "startxfce4" "$SESSION_START" || process_matches "$SESSION_PID" "asl-start-xfce" "$SESSION_START"); then
        echo "[!] XFCE desktop process exited during startup."
        cleanup_started
        return 1
    fi
    write_state || { cleanup_started; return 1; }
    am start -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
    start_vnc 2>/dev/null || true
    echo "[✓] Desktop started on $DISPLAY_ID. Open the Termux:X11 Android app or noVNC web viewer."
}

stop_desktop() {
    if ! read_state; then
        echo "[*] No ASL-managed desktop session is active."
        return 0
    fi
    local failed=0 pid
    echo "[*] Stopping ASL-managed desktop..."
    chroot_pkill TERM '(^|[^A-Za-z0-9_])(xfwm4|xfdesktop|xfce4-panel|xfsettingsd|xfce4-session|xfconfd|xfconf-query|picom)([^A-Za-z0-9_]|$)'
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START" || process_matches "$SESSION_PID" "startxfce4" "$SESSION_START" || process_matches "$SESSION_PID" "asl-start-xfce" "$SESSION_START"; then asl_exec "kill -TERM $SESSION_PID" 2>/dev/null || failed=1; fi
    sleep 1
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START" || process_matches "$SESSION_PID" "startxfce4" "$SESSION_START" || process_matches "$SESSION_PID" "asl-start-xfce" "$SESSION_START"; then asl_exec "kill -KILL $SESSION_PID" 2>/dev/null || failed=1; fi
    sleep 1
    chroot_pkill TERM '(^|[^A-Za-z0-9_])(asl-start-xfce|dbus-run-session|dbus-daemon)([^A-Za-z0-9_]|$)'
    chroot_pkill 9 '(^|[^A-Za-z0-9_])(asl-start-xfce|dbus-run-session|sleep)([^A-Za-z0-9_]|$)'
    if process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || failed=1; fi
    if [ -n "${SOCAT_PID:-}" ] && process_matches "$SOCAT_PID" "socat" "$SOCAT_START"; then kill -TERM "$SOCAT_PID" 2>/dev/null || true; fi
    if [ "$PULSE_OWNED" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || failed=1; fi
    if [ "${VIRGL_OWNED:-0}" = 1 ] && [ -n "${VIRGL_PID:-}" ] && process_matches "$VIRGL_PID" "virgl_test_server" "$VIRGL_START"; then kill -TERM "$VIRGL_PID" 2>/dev/null || true; fi
    if [ -n "${LAUNCHER_PID:-}" ]; then kill -TERM "$LAUNCHER_PID" 2>/dev/null || true; fi
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
    echo "[*] Force-stopping all GUI, X11, GPU, and audio processes..."
    chroot_pkill 9 '(^|[^A-Za-z0-9_])(xfce4-session|xfwm4|xfdesktop|xfce4-panel|xfsettingsd|xfconfd|xfconf-query|picom|dbus-daemon|dbus-launch|x11vnc)([^A-Za-z0-9_]|$)'
    chroot_pkill 9 '(^|[^A-Za-z0-9_])(asl-start-xfce)([^A-Za-z0-9_]|$)'
    host_pkill 9 '(^|[^A-Za-z0-9_])(termux-x11|virgl_test_server_android|pulseaudio|socat)([^A-Za-z0-9_]|$)'
    local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    rm -rf "$termux_tmp/.X11-unix"/X* "$termux_tmp/.X0-lock" "$DEBIANPATH/tmp/.X0-lock" "$DEBIANPATH/tmp/xfce-keepalive" "$DEBIANPATH/run/dbus/system_bus_socket" "$DEBIANPATH/tmp/.X11-vnc" "$DEBIANPATH/tmp/.vnc"/*.pid "$STATE_FILE" "$STATE_FILE.tmp."* 2>/dev/null || true
    sleep 1
    echo "[✓] Complete stop: All GUI processes terminated and state cleared."
}

status_desktop() {
    if ! read_state; then echo "Desktop: STOPPED"; return 0; fi
    if process_matches "$SESSION_PID" "xfwm4" "$SESSION_START" || process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START" || process_matches "$SESSION_PID" "startxfce4" "$SESSION_START" || process_matches "$SESSION_PID" "asl-start-xfce" "$SESSION_START"; then
        echo "Desktop: RUNNING ($DISPLAY_ID)"
        process_matches "$X11_PID" "termux-x11" "$X11_START" || echo "Warning: Termux:X11 process is not running."
        return 0
    else
        rm -f "$STATE_FILE" "$STATE_FILE.tmp."* 2>/dev/null || true
        echo "Desktop: STOPPED"
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
            return 0
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
    PULSE_OWNED=0 PULSE_PID='' PULSE_START=''
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
            export PULSE_SERVER="${PULSE_SERVER:-127.0.0.1}"
            if pgrep -x pulseaudio >/dev/null 2>&1 || pactl info >/dev/null 2>&1; then
                echo "PulseAudio Server: RUNNING"
            else
                echo "PulseAudio Server: STOPPED"
            fi
            ;;
        test)
            export PULSE_SERVER="${PULSE_SERVER:-127.0.0.1}"
            if ! pgrep -x pulseaudio >/dev/null 2>&1 && ! pactl info >/dev/null 2>&1; then
                start_audio || return 1
            fi
            echo "[*] Playing audio test tone..."
            if command -v paplay >/dev/null; then
                local sound_file=""
                for s in "$PREFIX/share/sounds/freedesktop/stereo/bell.oga" "$DEBIANPATH/usr/share/sounds/freedesktop/stereo/bell.oga" /usr/share/sounds/freedesktop/stereo/bell.oga /usr/share/sounds/freedesktop/stereo/complete.oga; do
                    if [ -f "$s" ]; then sound_file="$s"; break; fi
                done
                if [ -n "$sound_file" ]; then
                    paplay "$sound_file" 2>/dev/null && echo "[✓] Audio playback successful." || echo "[*] Audio pipeline active."
                elif command -v speaker-test >/dev/null 2>&1; then
                    speaker-test -t sine -f 440 -l 1 >/dev/null 2>&1 && echo "[✓] Audio playback successful." || echo "[*] Audio pipeline active."
                else
                    echo "[*] Audio pipeline active (PulseAudio server running)."
                fi
            elif command -v speaker-test >/dev/null 2>&1; then
                speaker-test -t sine -f 440 -l 1 >/dev/null 2>&1 && echo "[✓] Audio playback successful." || echo "[*] Audio pipeline active."
            else
                echo "[*] Audio pipeline active (PulseAudio server running)."
            fi
            ;;
        volume)
            export PULSE_SERVER="${PULSE_SERVER:-127.0.0.1}"
            if [ -n "$level" ]; then
                if command -v pactl >/dev/null; then
                    pactl set-sink-volume @DEFAULT_SINK@ "${level}%" 2>/dev/null && echo "[✓] Master volume set to ${level}%." || echo "[!] pactl failed to set volume."
                else
                    echo "[!] pactl is not installed."
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
