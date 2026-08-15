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
        base=$(basename "$target")
        stem="${base%.*}"
        ext="${base##*.}"
        [ "$stem" = "$base" ] && ext="" || ext=".$ext"
        tmp_copy=$(mktemp "$download_dir/asl-shared-${stem}.XXXXXX${ext}") || {
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
        echo "Usage: asl [wakelock|open|clip|toast|notify|storage]"
        ;;
esac

