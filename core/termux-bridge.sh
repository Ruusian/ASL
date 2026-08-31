#!/bin/bash
# ASL: Termux & Android Host Bridge
# Provides deep integration between ASL chroot/CLI and Android host features.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
elif [ -f "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh" ]; then
    source "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh"
elif [ -f "$HOME/ASL/core/common.sh" ]; then
    source "$HOME/ASL/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

termux_wakelock() {
    local action="${1:-status}"
    case "$action" in
        on|enable|acquire)
            if command -v termux-wake-lock >/dev/null 2>&1; then
                termux-wake-lock
                echo "[✓] CPU Wake Lock acquired (prevents Android sleep during background tasks)."
            else
                echo "[!] termux-wake-lock binary not found."
                return 1
            fi
            ;;
        off|disable|release)
            if command -v termux-wake-unlock >/dev/null 2>&1; then
                termux-wake-unlock
                echo "[✓] CPU Wake Lock released."
            else
                echo "[!] termux-wake-unlock binary not found."
                return 1
            fi
            ;;
        status|*)
            if pgrep -f "termux-wake-lock" >/dev/null 2>&1; then
                echo "[*] CPU Wake Lock: ACTIVE"
            else
                echo "[*] CPU Wake Lock: INACTIVE"
            fi
            ;;
    esac
}

termux_open_file() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "Usage: asl open <file-path-or-url>"
        return 1
    fi
    if ! command -v termux-open >/dev/null 2>&1; then
        echo "[!] termux-open is not installed."
        return 1
    fi

    # Files inside the chroot are not directly visible to Android apps.
    if [[ "$target" == "$DEBIANPATH"* ]] && [ -f "$target" ]; then
        local download_dir="/sdcard/Download" base stem ext tmp_copy
        if [ ! -d "$download_dir" ]; then
            echo "[!] Android Download directory is unavailable. Run: asl storage"
            return 1
        fi

        # Prune shared temporary files older than 24 hours
        find "$download_dir" -maxdepth 1 -name "asl-shared-*" -mtime +1 -delete 2>/dev/null || true
        base=$(basename "$target")
        stem="${base%.*}"
        ext="${base##*.}"
        [ "$stem" = "$base" ] && ext="" || ext=".$ext"
        safe_stem=$(echo "$stem" | sed 's/[^A-Za-z0-9_-]/_/g')
        [ -n "$safe_stem" ] || safe_stem="file"
        tmp_copy=$(mktemp --suffix="${ext}" "$download_dir/asl-shared-${safe_stem}.XXXXXX" 2>/dev/null || mktemp "$download_dir/asl-shared-${safe_stem}.XXXXXX") || {
            echo "[!] Could not allocate a unique file in Android Download."
            return 1
        }
        if ! cp "$target" "$tmp_copy"; then
            rm -f "$tmp_copy"
            echo "[!] Failed to copy chroot file to Android Download."
            return 1
        fi
        if ! termux-open "$tmp_copy"; then
            echo "[!] termux-open failed for: $tmp_copy"
            return 1
        fi
        echo "[✓] Opened chroot file in Android host: $tmp_copy"
    else
        if ! termux-open "$target"; then
            echo "[!] termux-open failed for: $target"
            return 1
        fi
        echo "[✓] Opened target in Android host: $target"
    fi
}

termux_clipboard() {
    local action="${1:-paste}"
    shift || true
    case "$action" in
        copy|set)
            local content="$*"
            if [ -z "$content" ] && [ ! -t 0 ]; then
                content=$(cat)
            fi
            if command -v termux-clipboard-set >/dev/null 2>&1; then
                printf '%s' "$content" | termux-clipboard-set
                echo "[✓] Copied to Android system clipboard."
            else
                echo "[!] termux-clipboard-set is not available (install termux-api package)."
                return 1
            fi
            ;;
        paste|get)
            if command -v termux-clipboard-get >/dev/null 2>&1; then
                termux-clipboard-get
            else
                echo "[!] termux-clipboard-get is not available (install termux-api package)."
                return 1
            fi
            ;;
        *)
            echo "Usage: asl clip [copy <text> | paste]"
            return 1
            ;;
    esac
}

termux_toast_msg() {
    local msg="$*"
    [ -n "$msg" ] || msg="ASL Notification"
    if command -v termux-toast >/dev/null 2>&1; then
        termux-toast "$msg"
    else
        echo "[Toast] $msg"
    fi
}

termux_notification_msg() {
    local title="${1:-ASL}"
    local content="${2:-Notification}"
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --title "$title" --content "$content"
    else
        echo "[$title] $content"
    fi
}

termux_storage_setup() {
    if command -v termux-setup-storage >/dev/null 2>&1; then
        echo "[*] Requesting Android shared storage access..."
        termux-setup-storage
        echo "[✓] Storage setup command issued. Grant storage permissions if prompted."
    else
        echo "[!] termux-setup-storage binary not found."
    fi
}

termux_create_shortcut() {
    local app_name="${1:-}"
    if [ -z "$app_name" ]; then
        echo "Usage: asl shortcut <desktop-app-or-binary-name>"
        return 1
    fi
    local shortcuts_dir="$HOME/.shortcuts"
    local bin_dir="$HOME/bin"
    mkdir -p "$shortcuts_dir" "$bin_dir" 2>/dev/null || true

    local script_name
    script_name=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g')
    local target_script="$shortcuts_dir/${script_name}.sh"
    local target_bin="$bin_dir/${script_name}"

    cat <<EOF > "$target_script"
#!/bin/bash
# ASL Android Home Screen / Termux Shortcut Launcher
export PATH="/data/data/com.termux/files/usr/bin:\$PATH"
asl start >/dev/null 2>&1 || true
asl desktop start >/dev/null 2>&1 || true
asl host launch "$app_name"
EOF
    chmod +x "$target_script"
    cp "$target_script" "$target_bin" 2>/dev/null || true
    chmod +x "$target_bin" 2>/dev/null || true

    echo "[✓] Created ASL application shortcut for '$app_name':"
    echo "  - Termux Widget Shortcut: $target_script"
    echo "  - CLI Command: $target_bin"
}

termux_clipboard_sync() {
    local action="${1:-start}"
    local pid_file="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/asl_clip_sync.pid"

    case "$action" in
        start|on)
            if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                echo "[*] Clipboard sync daemon is already running (PID: $(cat "$pid_file"))."
                return 0
            fi
            echo "[*] Starting ASL Bidirectional System Clipboard Sync..."
            (
                last_clip=""
                while true; do
                    if command -v termux-clipboard-get >/dev/null 2>&1; then
                        curr_clip=$(termux-clipboard-get 2>/dev/null || true)
                        if [ -n "$curr_clip" ] && [ "$curr_clip" != "$last_clip" ]; then
                            last_clip="$curr_clip"
                            enc_clip=$(printf '%s' "$curr_clip" | base64 | tr -d '\n')
                            if type asl_chroot_exec >/dev/null 2>&1; then
                                asl_chroot_exec "export DISPLAY=:0; printf '%s' '$enc_clip' | base64 -d | xclip -selection clipboard 2>/dev/null || printf '%s' '$enc_clip' | base64 -d | xsel -b 2>/dev/null || true" >/dev/null 2>&1 || true
                            elif command -v asl >/dev/null 2>&1; then
                                asl exec "export DISPLAY=:0; printf '%s' '$enc_clip' | base64 -d | xclip -selection clipboard 2>/dev/null || printf '%s' '$enc_clip' | base64 -d | xsel -b 2>/dev/null || true" >/dev/null 2>&1 || true
                            fi
                        fi
                    fi
                    sleep 3
                done
            ) &
            echo $! > "$pid_file"
            echo "[✓] Clipboard sync daemon active (PID: $!)."
            ;;
        stop|off)
            if [ -f "$pid_file" ]; then
                kill "$(cat "$pid_file")" 2>/dev/null || true
                rm -f "$pid_file"
                echo "[✓] Clipboard sync daemon stopped."
            else
                echo "[*] Clipboard sync daemon is not running."
            fi
            ;;
        status|*)
            if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                echo "[*] Clipboard Sync Daemon: ACTIVE (PID: $(cat "$pid_file"))"
            else
                echo "[*] Clipboard Sync Daemon: INACTIVE"
            fi
            ;;
    esac
}

_asl_host_su() {
    local cmd="$1"
    if [ -f /etc/debian_version ] && [ -e /proc/1/ns/mnt ] && command -v nsenter >/dev/null 2>&1; then
        nsenter --mount=/proc/1/ns/mnt /system/bin/sh -c "$cmd"
    elif command -v su >/dev/null 2>&1 && [ ! -f /etc/debian_version ]; then
        su -c "$cmd"
    elif [ -e /proc/1/ns/mnt ] && command -v nsenter >/dev/null 2>&1; then
        nsenter --mount=/proc/1/ns/mnt /system/bin/sh -c "$cmd"
    else
        su -c "$cmd" 2>/dev/null || sh -c "$cmd"
    fi
}

if [ -f /etc/debian_version ] && [ ! -d "/data/local/tmp/chrootDebian" ]; then
    SCREEN_STATE_FILE="/tmp/.asl_screen_state"
    ROTATION_STATE_FILE="/tmp/.asl_rotation_state"
    ROTATION_CONF_FILE="/etc/asl_rotation.conf"
    ROTATION_WATCHER_PID="/tmp/.asl_rotation_watcher.pid"
else
    SCREEN_STATE_FILE="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/.asl_screen_state"
    ROTATION_STATE_FILE="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/.asl_rotation_state"
    ROTATION_CONF_FILE="${HOME:-/data/data/com.termux/files/home}/.config/asl/rotation.conf"
    ROTATION_WATCHER_PID="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/.asl_rotation_watcher.pid"
fi

_asl_save_rotation_state() {
    local forced="$1"
    local mode="$2"
    local rot_val="$3"
    local c_dir
    c_dir=$(dirname "$ROTATION_CONF_FILE")
    mkdir -p "$c_dir" 2>/dev/null || true
    local s_dir
    s_dir=$(dirname "$ROTATION_STATE_FILE")
    mkdir -p "$s_dir" 2>/dev/null || true
    local content="FORCED_LANDSCAPE=${forced}
ROTATION_MODE=${mode}
USER_ROTATION=${rot_val}
OVERRIDE_NATIVE_AUTOROTATE=${forced}
LAST_UPDATED=$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s\n' "$content" > "$ROTATION_CONF_FILE" 2>/dev/null || _asl_host_su "printf '%s\n' \"$content\" > '$ROTATION_CONF_FILE'" 2>/dev/null || true
    printf '%s\n' "$content" > "$ROTATION_STATE_FILE" 2>/dev/null || _asl_host_su "printf '%s\n' \"$content\" > '$ROTATION_STATE_FILE'" 2>/dev/null || true
    chmod 666 "$ROTATION_CONF_FILE" 2>/dev/null || _asl_host_su "chmod 666 '$ROTATION_CONF_FILE'" 2>/dev/null || true
    chmod 666 "$ROTATION_STATE_FILE" 2>/dev/null || _asl_host_su "chmod 666 '$ROTATION_STATE_FILE'" 2>/dev/null || true
}

_asl_load_rotation_state() {
    if [ -f "$ROTATION_CONF_FILE" ]; then
        source "$ROTATION_CONF_FILE" 2>/dev/null || true
    elif [ -f "$ROTATION_STATE_FILE" ]; then
        source "$ROTATION_STATE_FILE" 2>/dev/null || true
    fi
}

_asl_enforce_rotation_lock() {
    _asl_load_rotation_state
    if [ "${FORCED_LANDSCAPE:-0}" = "1" ]; then
        local cur_accel cur_rot target_rot="${USER_ROTATION:-1}"
        cur_accel=$(_asl_host_su "settings get system accelerometer_rotation" 2>/dev/null | tr -d '[:space:]')
        cur_rot=$(_asl_host_su "settings get system user_rotation" 2>/dev/null | tr -d '[:space:]')
        if [ "$cur_accel" = "1" ] || [ "$cur_rot" != "$target_rot" ]; then
            _asl_host_su "settings put system accelerometer_rotation 0; settings put system user_rotation $target_rot" 2>/dev/null
            return 2
        fi
        return 0
    fi
    return 1
}

_asl_get_screen_info() {
    local wm_out
    wm_out=$(_asl_host_su "wm size; wm density" 2>/dev/null)
    PHYS_SIZE=$(echo "$wm_out" | grep -i "Physical size:" | head -n1 | awk '{print $NF}')
    OVER_SIZE=$(echo "$wm_out" | grep -i "Override size:" | head -n1 | awk '{print $NF}')
    PHYS_DENSITY=$(echo "$wm_out" | grep -i "Physical density:" | head -n1 | awk '{print $NF}')
    OVER_DENSITY=$(echo "$wm_out" | grep -i "Override density:" | head -n1 | awk '{print $NF}')

    CURR_SIZE="${OVER_SIZE:-$PHYS_SIZE}"
    CURR_DENSITY="${OVER_DENSITY:-$PHYS_DENSITY}"
}

_asl_save_screen_state() {
    local save_size="$1"
    local save_den="$2"
    _asl_get_screen_info
    local s_dir
    s_dir=$(dirname "$SCREEN_STATE_FILE")
    mkdir -p "$s_dir" 2>/dev/null || true
    local content="PHYSICAL_SIZE=${PHYS_SIZE}
PHYSICAL_DENSITY=${PHYS_DENSITY}
SAVED_OVERRIDE_SIZE=${save_size:-$CURR_SIZE}
SAVED_OVERRIDE_DENSITY=${save_den:-$CURR_DENSITY}
LAST_SAVED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s\n' "$content" > "$SCREEN_STATE_FILE" 2>/dev/null || _asl_host_su "printf '%s\n' \"$content\" > '$SCREEN_STATE_FILE'" 2>/dev/null || true
    chmod 666 "$SCREEN_STATE_FILE" 2>/dev/null || _asl_host_su "chmod 666 '$SCREEN_STATE_FILE'" 2>/dev/null || true
}

_asl_load_screen_state() {
    if [ -f "$SCREEN_STATE_FILE" ]; then
        source "$SCREEN_STATE_FILE" 2>/dev/null || true
    fi
}

termux_screen_resolution() {
    local action="${1:-status}"
    shift || true
    case "$action" in
        status|"")
            _asl_get_screen_info
            _asl_load_screen_state
            echo "=== Android Screen Resolution & Density ==="
            echo " Physical Size:     ${PHYS_SIZE:-Unknown}"
            echo " Physical Density:  ${PHYS_DENSITY:-Unknown} dpi"
            if [ -n "$OVER_SIZE" ] || [ -n "$OVER_DENSITY" ]; then
                echo " Current Active:    ${CURR_SIZE} @ ${CURR_DENSITY} dpi (Override Active)"
            else
                echo " Current Active:    ${CURR_SIZE} @ ${CURR_DENSITY} dpi (Native Hardware)"
            fi
            if [ -n "${SAVED_OVERRIDE_SIZE:-}" ]; then
                echo " Saved Profile:     ${SAVED_OVERRIDE_SIZE} @ ${SAVED_OVERRIDE_DENSITY:-163} dpi"
            fi
            ;;
        save)
            _asl_get_screen_info
            _asl_save_screen_state "$CURR_SIZE" "$CURR_DENSITY"
            echo "[✓] Saved current resolution ($CURR_SIZE) and density (${CURR_DENSITY} dpi) to profile."
            ;;
        reset|native|default)
            _asl_get_screen_info
            _asl_load_screen_state
            if [ -n "$OVER_SIZE" ] || [ -n "$OVER_DENSITY" ]; then
                _asl_save_screen_state "$OVER_SIZE" "$OVER_DENSITY"
            fi
            echo "[*] Resetting Android screen resolution and density to native hardware values..."
            _asl_host_su "wm size reset; wm density reset" 2>/dev/null
            _asl_get_screen_info
            echo "[✓] Screen resolution and density reset to native (${PHYS_SIZE:-Unknown} @ ${PHYS_DENSITY:-Unknown} dpi)."
            ;;
        set)
            local res="${1:-}"
            local density="${2:-}"
            if [ -z "$res" ]; then
                echo "Usage: asl screen-res set <WIDTHxHEIGHT> [DENSITY_DPI]"
                echo "Example: asl screen-res set 1080x1920 163"
                return 1
            fi
            if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
                echo "[!] Invalid resolution format. Expected <WIDTHxHEIGHT> (e.g. 1080x1920)."
                return 1
            fi
            _asl_load_screen_state
            if [ -z "$density" ]; then
                if [ "$res" = "${SAVED_OVERRIDE_SIZE:-}" ] && [ -n "${SAVED_OVERRIDE_DENSITY:-}" ]; then
                    density="$SAVED_OVERRIDE_DENSITY"
                else
                    _asl_get_screen_info
                    density="$CURR_DENSITY"
                fi
            fi
            if [ -n "$density" ] && [[ ! "$density" =~ ^[0-9]+$ ]]; then
                echo "[!] Invalid density value '$density' (must be integer DPI)."
                return 1
            fi
            _asl_save_screen_state "$res" "$density"
            echo "[*] Setting Android screen resolution to $res (Density: ${density} dpi)..."
            if [ -n "$density" ]; then
                _asl_host_su "wm size '$res'; wm density '$density'" 2>/dev/null
            else
                _asl_host_su "wm size '$res'" 2>/dev/null
            fi
            _asl_get_screen_info
            echo "[✓] Screen resolution updated: ${CURR_SIZE} @ ${CURR_DENSITY} dpi."
            ;;
        1080p|1080x1920)
            _asl_load_screen_state
            local den="${1:-${SAVED_OVERRIDE_DENSITY:-163}}"
            _asl_save_screen_state "1080x1920" "$den"
            echo "[*] Switching screen resolution to 1080x1920 (FHD 16:9, Density: ${den} dpi)..."
            _asl_host_su "wm size 1080x1920; wm density '$den'" 2>/dev/null
            _asl_get_screen_info
            echo "[✓] Screen resolution set to ${CURR_SIZE} (Density: ${CURR_DENSITY} dpi)."
            ;;
        720p|720x1280)
            _asl_load_screen_state
            local den="${1:-${SAVED_OVERRIDE_DENSITY:-120}}"
            _asl_save_screen_state "720x1280" "$den"
            echo "[*] Switching screen resolution to 720x1280 (HD 16:9, Density: ${den} dpi)..."
            _asl_host_su "wm size 720x1280; wm density '$den'" 2>/dev/null
            _asl_get_screen_info
            echo "[✓] Screen resolution set to ${CURR_SIZE} (Density: ${CURR_DENSITY} dpi)."
            ;;
        toggle|switch)
            _asl_get_screen_info
            _asl_load_screen_state
            if [ -n "$OVER_SIZE" ] || [ -n "$OVER_DENSITY" ]; then
                _asl_save_screen_state "$OVER_SIZE" "$OVER_DENSITY"
                echo "[*] Toggling display: Resetting to Android Native hardware resolution..."
                _asl_host_su "wm size reset; wm density reset" 2>/dev/null
                _asl_get_screen_info
                echo "[✓] Display toggled: Active Native Hardware (${PHYS_SIZE} @ ${PHYS_DENSITY} dpi)."
            else
                local target_res="${SAVED_OVERRIDE_SIZE:-1080x1920}"
                local target_den="${SAVED_OVERRIDE_DENSITY:-163}"
                echo "[*] Toggling display: Switching to custom resolution ($target_res @ ${target_den} dpi)..."
                _asl_save_screen_state "$target_res" "$target_den"
                _asl_host_su "wm size '$target_res'; wm density '$target_den'" 2>/dev/null
                _asl_get_screen_info
                echo "[✓] Display toggled: Active Custom (${CURR_SIZE} @ ${CURR_DENSITY} dpi)."
            fi
            ;;
        *)
            if [[ "$action" =~ ^[0-9]+x[0-9]+$ ]]; then
                local den="${1:-}"
                termux_screen_resolution set "$action" "$den"
            else
                echo "Usage: asl screen-res [status | toggle | reset | 1080p [dpi] | 720p [dpi] | set <WxH> [dpi] | save]"
                return 1
            fi
            ;;
    esac
}

termux_screen_rotation() {
    local action="${1:-status}"
    shift || true
    case "$action" in
        status|"")
            _asl_load_rotation_state
            local accel user_rot
            accel=$(_asl_host_su "settings get system accelerometer_rotation" 2>/dev/null | tr -d '[:space:]')
            user_rot=$(_asl_host_su "settings get system user_rotation" 2>/dev/null | tr -d '[:space:]')
            if [ "${FORCED_LANDSCAPE:-0}" = "1" ]; then
                local target_rot="${USER_ROTATION:-1}"
                if [ "$accel" = "1" ] || [ "$user_rot" != "$target_rot" ]; then
                    echo "[!] Android Native Auto-Rotation detected active ($accel) while Forced Landscape is configured."
                    echo "[*] Overriding and enforcing Forced Landscape lock (accel=0, rotation=$target_rot)..."
                    _asl_host_su "settings put system accelerometer_rotation 0; settings put system user_rotation $target_rot" 2>/dev/null
                    accel="0"
                    user_rot="$target_rot"
                fi
            fi
            echo "=== Android Screen Rotation & Orientation ==="
            if [ "${FORCED_LANDSCAPE:-0}" = "1" ]; then
                echo " Auto-Rotate:         DISABLED (Overridden by ASL Forced Landscape)"
                if [ "$user_rot" = "3" ]; then
                    echo " Forced Landscape:    ENABLED (Permanent 270° Reverse Landscape Override)"
                    echo " Locked Mode:         Reverse Landscape (270°)"
                else
                    echo " Forced Landscape:    ENABLED (Permanent 90° Landscape Override)"
                    echo " Locked Mode:         Landscape (90°)"
                fi
                echo " Native Override:     ACTIVE (Accelerometer auto-rotation blocked)"
            elif [ "$accel" = "1" ]; then
                echo " Auto-Rotate:         ENABLED (Dynamic Sensor Mode)"
                echo " Forced Landscape:    DISABLED"
                echo " Locked State:        OFF"
            else
                echo " Auto-Rotate:         DISABLED (Orientation Locked)"
                case "$user_rot" in
                    1)
                        echo " Forced Landscape:    ENABLED (Permanent 90° Landscape)"
                        echo " Locked Mode:         Landscape (90°)"
                        ;;
                    3)
                        echo " Forced Landscape:    ENABLED (Permanent 270° Reverse Landscape)"
                        echo " Locked Mode:         Reverse Landscape (270°)"
                        ;;
                    0)
                        echo " Forced Landscape:    DISABLED (Permanent 0° Portrait)"
                        echo " Locked Mode:         Portrait (0°)"
                        ;;
                    2)
                        echo " Forced Landscape:    DISABLED (Permanent 180° Reverse Portrait)"
                        echo " Locked Mode:         Reverse Portrait (180°)"
                        ;;
                    *)
                        echo " Forced Landscape:    CUSTOM ($user_rot)"
                        echo " Locked Mode:         Custom / Unknown ($user_rot)"
                        ;;
                esac
            fi
            ;;
        landscape|land|enable-forced-landscape|forced-landscape-on|on|90)
            echo "[*] Enabling Forced Landscape mode (Locking screen to 90° Landscape & Overriding Auto-Rotate)..."
            _asl_host_su "settings put system accelerometer_rotation 0; settings put system user_rotation 1" 2>/dev/null
            _asl_save_rotation_state "1" "landscape" "1"
            echo "[✓] Forced Landscape mode ENABLED (Native Auto-Rotate overridden, 90° orientation active)."
            ;;
        rev-landscape|reverse-landscape|270)
            echo "[*] Enabling Forced Reverse Landscape mode (Locking screen to 270° Landscape & Overriding Auto-Rotate)..."
            _asl_host_su "settings put system accelerometer_rotation 0; settings put system user_rotation 3" 2>/dev/null
            _asl_save_rotation_state "1" "rev-landscape" "3"
            echo "[✓] Forced Reverse Landscape mode ENABLED (Native Auto-Rotate overridden, 270° orientation active)."
            ;;
        disable-forced-landscape|forced-landscape-off|off|auto|auto-on|enable|auto-rotate)
            echo "[*] Disabling Forced Landscape mode (Enabling Android Auto-Rotation Sensor Mode)..."
            _asl_host_su "settings put system accelerometer_rotation 1" 2>/dev/null
            _asl_save_rotation_state "0" "auto" ""
            echo "[✓] Forced Landscape mode DISABLED (Android Auto-Rotation sensor mode active)."
            ;;
        lock|auto-off|disable)
            echo "[*] Disabling Android Auto-Rotation (Locking current orientation)..."
            _asl_host_su "settings put system accelerometer_rotation 0" 2>/dev/null
            _asl_save_rotation_state "0" "locked" ""
            echo "[✓] Android Auto-Rotation disabled / locked."
            ;;
        portrait|port|0)
            echo "[*] Enabling Forced Portrait mode (Locking screen to 0° Portrait)..."
            _asl_host_su "settings put system accelerometer_rotation 0; settings put system user_rotation 0" 2>/dev/null
            _asl_save_rotation_state "0" "portrait" "0"
            echo "[✓] Forced Portrait mode ENABLED (Auto-Rotate locked off, 0° orientation active)."
            ;;
        rev-portrait|reverse-portrait|180)
            echo "[*] Enabling Forced Reverse Portrait mode (Locking screen to 180° Portrait)..."
            _asl_host_su "settings put system accelerometer_rotation 0; settings put system user_rotation 2" 2>/dev/null
            _asl_save_rotation_state "0" "rev-portrait" "2"
            echo "[✓] Forced Reverse Portrait mode ENABLED (Auto-Rotate locked off, 180° orientation active)."
            ;;
        enforce|guard|clamp|check)
            _asl_enforce_rotation_lock
            local enforce_res=$?
            if [ "$enforce_res" -eq 2 ]; then
                echo "[✓] Android native auto-rotation detected and overridden back to Forced Landscape."
            elif [ "$enforce_res" -eq 0 ]; then
                echo "[✓] Forced Landscape mode is actively locked and enforced."
            else
                echo "[*] Forced Landscape mode is not active (normal auto-rotate / portrait)."
            fi
            ;;
        watch|watcher|daemon)
            local sub_act="${1:-status}"
            case "$sub_act" in
                start)
                    if [ -f "$ROTATION_WATCHER_PID" ] && kill -0 "$(cat "$ROTATION_WATCHER_PID" 2>/dev/null)" 2>/dev/null; then
                        echo "[*] Rotation watcher daemon is already running (PID: $(cat "$ROTATION_WATCHER_PID"))."
                        return 0
                    fi
                    echo "[*] Starting ASL Rotation Watcher daemon (auto-overriding Android auto-rotation)..."
                    (
                        while true; do
                            _asl_enforce_rotation_lock >/dev/null 2>&1 || true
                            sleep 2
                        done
                    ) &
                    echo $! > "$ROTATION_WATCHER_PID" 2>/dev/null || true
                    echo "[✓] Rotation watcher active (PID: $!)."
                    ;;
                stop)
                    if [ -f "$ROTATION_WATCHER_PID" ]; then
                        local w_pid
                        w_pid=$(cat "$ROTATION_WATCHER_PID" 2>/dev/null)
                        [ -n "$w_pid" ] && kill "$w_pid" 2>/dev/null || true
                        rm -f "$ROTATION_WATCHER_PID" 2>/dev/null || true
                        echo "[✓] Rotation watcher stopped."
                    else
                        echo "[*] Rotation watcher is not running."
                    fi
                    ;;
                status|*)
                    if [ -f "$ROTATION_WATCHER_PID" ] && kill -0 "$(cat "$ROTATION_WATCHER_PID" 2>/dev/null)" 2>/dev/null; then
                        echo " Rotation Watcher: ACTIVE (PID: $(cat "$ROTATION_WATCHER_PID"))"
                    else
                        echo " Rotation Watcher: INACTIVE (Integrated with ASL Service Watchdog)"
                    fi
                    ;;
            esac
            ;;
        toggle|switch|toggle-landscape)
            _asl_load_rotation_state
            local accel user_rot
            accel=$(_asl_host_su "settings get system accelerometer_rotation" 2>/dev/null | tr -d '[:space:]')
            user_rot=$(_asl_host_su "settings get system user_rotation" 2>/dev/null | tr -d '[:space:]')
            if [ "${FORCED_LANDSCAPE:-0}" = "1" ] || ([ "$accel" = "0" ] && [ "$user_rot" = "1" ]); then
                termux_screen_rotation disable-forced-landscape
            else
                termux_screen_rotation landscape
            fi
            ;;
        *)
            echo "Usage: asl rotation [landscape | auto | off | portrait | toggle | enforce | watch | status]"
            echo "       asl rotation landscape  - Enable Forced Landscape (90° lock, overrides native auto-rotate)"
            echo "       asl rotation auto       - Disable Forced Landscape (Enable Android Auto-Rotate)"
            echo "       asl rotation off        - Lock current orientation (Auto-Rotate off)"
            echo "       asl rotation portrait   - Lock to Portrait (0°)"
            echo "       asl rotation toggle     - Toggle Forced Landscape ON/OFF"
            echo "       asl rotation enforce    - Check & clamp orientation back to Forced Landscape"
            echo "       asl rotation watch      - Start/stop background auto-rotation override watcher"
            return 1
            ;;
    esac
}

case "${1:-}" in
    wakelock|wake)
        shift
        termux_wakelock "$@"
        ;;
    screen-res|screen-resolution|host-resolution|resolution-host|host-res|screen-density)
        shift
        termux_screen_resolution "$@"
        ;;
    rotation|rotate|orientation|screen-rotation|forced-landscape|landscape)
        shift
        termux_screen_rotation "$@"
        ;;
    open)
        shift
        termux_open_file "$@"
        ;;
    clip|clipboard)
        shift
        termux_clipboard "$@"
        ;;
    shortcut|app-shortcut)
        shift
        termux_create_shortcut "$@"
        ;;
    clip-sync|clipdaemon)
        shift
        termux_clipboard_sync "$@"
        ;;
    toast)
        shift
        termux_toast_msg "$@"
        ;;
    notify|notification)
        shift
        termux_notification_msg "$@"
        ;;
    storage)
        termux_storage_setup
        ;;
    *)
        echo "ASL Termux & Android Host Bridge"
        echo "Usage: asl [screen-res|rotation|wakelock|open|clip|shortcut|clip-sync|toast|notify|storage]"
        ;;
esac

