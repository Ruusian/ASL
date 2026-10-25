#!/bin/bash
# ASL: Autonomous AI Ecosystem Auto-Updater (OmniRoute & OpenClaude)
# Checks upstream npm registries, performs atomic updates, restarts daemons, and syncs settings.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

UPDATE_LOG="${PREFIX:-/data/data/com.termux/files/usr}/tmp/asl-ai-update.log"
LOCK_FILE="${PREFIX:-/data/data/com.termux/files/usr}/tmp/.asl_ai_update.lock"
STAMP_FILE="${HOME:-/data/data/com.termux/files/home}/.config/asl/ai_last_update"

mkdir -p "$(dirname "$STAMP_FILE")" "${PREFIX:-/data/data/com.termux/files/usr}/tmp" 2>/dev/null || true

asl_update_omniroute() {
    local force="${1:-0}"
    local cur_ver latest_ver
    cur_ver=$(omniroute --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "none")
    latest_ver=$(npm view omniroute version 2>/dev/null | tr -d '[:space:]')

    if [ -z "$latest_ver" ]; then
        echo "[!] OmniRoute: Unable to fetch latest version from npm registry."
        return 1
    fi

    if [ "$force" = "1" ] || [ "$cur_ver" != "$latest_ver" ]; then
        echo "[*] OmniRoute: Update detected ($cur_ver -> $latest_ver). Installing..."
        if npm install -g omniroute@latest --force >> "$UPDATE_LOG" 2>&1; then
            echo "[✓] OmniRoute successfully updated to v$latest_ver!"
            # Restart OmniRoute daemon cleanly if running
            if asl_is_omniroute_running 2>/dev/null || pgrep -f "omniroute" >/dev/null 2>&1; then
                echo "[*] Restarting OmniRoute AI Proxy daemon..."
                bash "$SCRIPT_DIR/bin/asl" omniroute restart >> "$UPDATE_LOG" 2>&1 || true
            fi
            return 0
        else
            echo "[!] OmniRoute update installation failed. See $UPDATE_LOG"
            return 1
        fi
    else
        echo "[✓] OmniRoute is up to date (v$cur_ver)."
        return 0
    fi
}

asl_update_openclaude() {
    local force="${1:-0}"
    local cur_ver latest_ver
    cur_ver=$(openclaude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "none")
    latest_ver=$(npm view @gitlawb/openclaude version 2>/dev/null | tr -d '[:space:]')

    if [ -z "$latest_ver" ]; then
        echo "[!] OpenClaude: Unable to fetch latest version from npm registry."
        return 1
    fi

    if [ "$force" = "1" ] || [ "$cur_ver" != "$latest_ver" ]; then
        echo "[*] OpenClaude: Update detected ($cur_ver -> $latest_ver). Installing..."
        if npm install -g @gitlawb/openclaude@latest --force >> "$UPDATE_LOG" 2>&1; then
            echo "[✓] OpenClaude successfully updated to v$latest_ver!"
            # Re-assert infinite turns and settings
            if [ -f "$SCRIPT_DIR/core/openclaude-setup.sh" ]; then
                bash "$SCRIPT_DIR/core/openclaude-setup.sh" >> "$UPDATE_LOG" 2>&1 || true
            fi
            return 0
        else
            echo "[!] OpenClaude update installation failed. See $UPDATE_LOG"
            return 1
        fi
    else
        echo "[✓] OpenClaude is up to date (v$cur_ver)."
        return 0
    fi
}

asl_update_ai_all() {
    local force="${1:-0}"
    # Prevent concurrent updates
    if [ -f "$LOCK_FILE" ]; then
        local lpid
        lpid=$(cat "$LOCK_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null; then
            echo "[*] AI update already in progress (PID: $lpid)."
            return 0
        fi
    fi
    echo "$$" > "$LOCK_FILE" 2>/dev/null || true

    echo "=== ASL Autonomous AI Ecosystem Updater ==="
    echo "[*] Checking for updates to OmniRoute & OpenClaude..."
    date '+%Y-%m-%d %H:%M:%S' > "$STAMP_FILE" 2>/dev/null || true

    asl_update_omniroute "$force"
    asl_update_openclaude "$force"

    rm -f "$LOCK_FILE" 2>/dev/null || true
    echo "=== AI Updates Complete ==="
}

asl_update_ai_watchdog() {
    # Automatic in-place background npm updates of live production AI gateways (OmniRoute)
    # are disabled by default to prevent service disruption while sessions are active.
    # Manual updates remain available via: asl ai update
    if [ -f "${HOME:-/data/data/com.termux/files/home}/.config/asl/enable_ai_autoupdate" ]; then
        local now last_time=0 interval=86400
        now=$(date +%s)
        if [ -f "$STAMP_FILE" ]; then
            last_time=$(stat -c %Y "$STAMP_FILE" 2>/dev/null || stat -f %m "$STAMP_FILE" 2>/dev/null || echo 0)
        fi
        if [ $((now - last_time)) -ge $interval ]; then
            ( ( nohup bash "$0" all >/dev/null 2>&1 & ) & ) 2>/dev/null
        fi
    fi
}

case "${1:-check}" in
    omni|omniroute)
        asl_update_omniroute "${2:-0}"
        ;;
    claude|openclaude)
        asl_update_openclaude "${2:-0}"
        ;;
    all|update)
        asl_update_ai_all "${2:-0}"
        ;;
    watchdog|auto)
        asl_update_ai_watchdog
        ;;
    status|check)
        echo "=== ASL AI Ecosystem Versions ==="
        echo " OmniRoute:  $(omniroute --version 2>/dev/null || echo 'not installed') (Latest: $(npm view omniroute version 2>/dev/null || echo 'unknown'))"
        echo " OpenClaude: $(openclaude --version 2>/dev/null || echo 'not installed') (Latest: $(npm view @gitlawb/openclaude version 2>/dev/null || echo 'unknown'))"
        if [ -f "$STAMP_FILE" ]; then
            echo " Last Check: $(cat "$STAMP_FILE")"
        fi
        ;;
    *)
        echo "Usage: $0 [all|update | omniroute|omni | openclaude|claude | status|check | watchdog|auto] [force]"
        exit 1
        ;;
esac
