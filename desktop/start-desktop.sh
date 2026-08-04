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

pid_start_time() { [ -r "/proc/$1/stat" ] && awk '{print $22}' "/proc/$1/stat"; }

process_matches() {
    local pid="$1" expected="$2" start="$3" actual cmd
    actual=$(pid_start_time "$pid") || return 1
    [ "$actual" = "$start" ] || return 1
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
    [[ "$cmd" == *"$expected"* ]]
}

read_state() {
    [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] || return 1
    [ "$(stat -c %U "$STATE_FILE" 2>/dev/null)" = "$(id -un)" ] || return 1
    unset DISPLAY_ID X11_PID X11_START SESSION_PID SESSION_START PULSE_PID PULSE_START PULSE_OWNED
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            DISPLAY_ID|X11_PID|X11_START|SESSION_PID|SESSION_START|PULSE_PID|PULSE_START|PULSE_OWNED)
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
    PULSE_START=$(pid_start_time "$PULSE_PID") || return 1
    PULSE_OWNED=1
    echo "[✓] PulseAudio server active."
}

cleanup_started() {
    if [ -n "${SESSION_PID:-}" ] && process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"; then kill -TERM "$SESSION_PID" 2>/dev/null || true; fi
    if [ -n "${X11_PID:-}" ] && process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || true; fi
    if [ "${PULSE_OWNED:-0}" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || true; fi
}

start_desktop() {
    ensure_state_dir || { echo "[!] Cannot create SuperKit state directory."; return 1; }
    if read_state; then
        if process_matches "$SESSION_PID" "xfce4-session" "$SESSION_START"; then
            echo "[*] Desktop is already running on $DISPLAY_ID."
            return 0
        fi
        rm -f "$STATE_FILE"
    fi
    command -v termux-x11 >/dev/null || { echo "[!] Termux:X11 client is not installed. Install it with: pkg install termux-x11"; return 1; }
    start_audio || return 1
    DISPLAY_ID=:0
    echo "[*] Starting Termux:X11 display server..."
    termux-x11 "$DISPLAY_ID" >/dev/null 2>&1 &
    X11_PID=$!
    X11_START=$(pid_start_time "$X11_PID") || { cleanup_started; return 1; }
    superkit_gpu_apply
    local gpu_env="GALLIUM_DRIVER=$GALLIUM_DRIVER MESA_VK_WINSYS=$MESA_VK_WINSYS"
    [ -n "${MESA_LOADER_DRIVER_OVERRIDE:-}" ] && gpu_env="$gpu_env MESA_LOADER_DRIVER_OVERRIDE=$MESA_LOADER_DRIVER_OVERRIDE"
    [ -n "${TU_DEBUG:-}" ] && gpu_env="$gpu_env TU_DEBUG=$TU_DEBUG"
    echo "[*] Launching XFCE4 Desktop Session inside chroot with $SUPERKIT_GPU_PROFILE..."
    su -c "chroot '$DEBIANPATH' /bin/bash --noprofile --norc -c 'export DISPLAY=$DISPLAY_ID PULSE_SERVER=tcp:127.0.0.1 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=xterm LANG=C.UTF-8 $gpu_env; exec setsid dbus-run-session xfce4-session'" >/dev/null 2>&1 &
    SESSION_PID=$!
    SESSION_START=$(pid_start_time "$SESSION_PID") || { cleanup_started; return 1; }
    sleep 1
    if ! process_matches "$SESSION_PID" "chroot" "$SESSION_START"; then
        echo "[!] XFCE session exited during startup."
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
    if process_matches "$SESSION_PID" "chroot" "$SESSION_START"; then kill -TERM -- "-$SESSION_PID" 2>/dev/null || kill -TERM "$SESSION_PID" 2>/dev/null || failed=1; fi
    sleep 1
    if process_matches "$SESSION_PID" "chroot" "$SESSION_START"; then kill -KILL -- "-$SESSION_PID" 2>/dev/null || kill -KILL "$SESSION_PID" 2>/dev/null || failed=1; fi
    if process_matches "$X11_PID" "termux-x11" "$X11_START"; then kill -TERM "$X11_PID" 2>/dev/null || failed=1; fi
    if [ "$PULSE_OWNED" = 1 ] && process_matches "$PULSE_PID" "pulseaudio" "$PULSE_START"; then kill -TERM "$PULSE_PID" 2>/dev/null || failed=1; fi
    if [ "$failed" -ne 0 ]; then echo "[!] Desktop shutdown was incomplete."; return 1; fi
    rm -f "$STATE_FILE"
    echo "[✓] SuperKit-managed desktop stopped."
}

status_desktop() {
    if ! read_state; then echo "Desktop: STOPPED"; return 0; fi
    if process_matches "$SESSION_PID" "chroot" "$SESSION_START"; then
        echo "Desktop: RUNNING ($DISPLAY_ID)"
        process_matches "$X11_PID" "termux-x11" "$X11_START" || echo "Warning: Termux:X11 process is not running."
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
    while IFS= read -r file; do
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
    done < <(su -c "chroot '$DEBIANPATH' /usr/bin/find /usr/share/applications /usr/local/share/applications /root/.local/share/applications -type f -name '*.desktop' 2>/dev/null" 2>/dev/null)
    echo "[✓] Synchronized $count SuperKit-owned launchers."
}

case "${1:-start}" in
    start|"") start_desktop ;;
    stop) stop_desktop ;;
    status) status_desktop ;;
    audio) start_audio ;;
    sync-apps) sync_apps ;;
    launch) shift; launch_app "$@" ;;
    *) echo "Usage: start-desktop.sh {start|stop|status|audio|sync-apps|launch}"; exit 1 ;;
esac
