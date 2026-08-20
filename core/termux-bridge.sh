#!/bin/bash
# ASL: Termux & Android Host Bridge
# Provides deep integration between ASL chroot/CLI and Android host features.

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
                            asl exec "echo -n \"$curr_clip\" | xclip -selection clipboard 2>/dev/null || echo -n \"$curr_clip\" | xsel -b 2>/dev/null || true" >/dev/null 2>&1 || true
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

case "${1:-}" in
    wakelock|wake)
        shift
        termux_wakelock "$@"
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
        echo "Usage: asl [wakelock|open|clip|shortcut|clip-sync|toast|notify|storage]"
        ;;
esac

