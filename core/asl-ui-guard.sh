#!/bin/bash
# ASL Autonomous UI Guard Daemon
# Actively monitors and enforces:
# 1. 90° Forced Landscape lock (accelerometer=0, user_rotation=1) at 0.2s intervals.
# 2. Zero-gap Keyboard Bar overlay (config_imeDrawsImeNavBar=false) auto-persistence.

TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PID_FILE="${PREFIX}/tmp/.asl_ui_guard.pid"
LOG_FILE="${PREFIX}/tmp/asl-ui-guard.log"
CONF_FILE="${TERMUX_HOME}/.config/asl/rotation.conf"
STATE_FILE="${PREFIX}/tmp/.asl_rotation_state"

_host_cmd() {
    if [ -f /etc/debian_version ] && [ -e /proc/1/ns/mnt ] && command -v nsenter >/dev/null 2>&1; then
        nsenter --mount=/proc/1/ns/mnt /system/bin/sh -c "$1"
    elif command -v su >/dev/null 2>&1; then
        su -c "$1" </dev/null
    else
        sh -c "$1"
    fi
}

run_loop() {
    local tick=0
    while true; do
        local is_forced=1
        local target_rot=1
        local hide_kbd=1

        if [ -f "$CONF_FILE" ]; then
            local f_val r_val k_val
            f_val=$(grep -E "^FORCED_LANDSCAPE=" "$CONF_FILE" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
            [ -n "$f_val" ] && is_forced="$f_val"
            r_val=$(grep -E "^USER_ROTATION=" "$CONF_FILE" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
            [ -n "$r_val" ] && target_rot="$r_val"
            k_val=$(grep -E "^HIDE_KEYBOARD_BAR=" "$CONF_FILE" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
            [ -n "$k_val" ] && hide_kbd="$k_val"
        fi

        # 1. Rotation Check & Clamp (every 0.2s)
        if [ "$is_forced" = "1" ]; then
            local accel u_rot
            accel=$(_host_cmd "settings get system accelerometer_rotation" 2>/dev/null | tr -d "[:space:]")
            u_rot=$(_host_cmd "settings get system user_rotation" 2>/dev/null | tr -d "[:space:]")
            if [ "$accel" = "1" ] || [ "$u_rot" != "$target_rot" ]; then
                _host_cmd "settings put system accelerometer_rotation 0" 2>/dev/null || true
                _host_cmd "settings put system user_rotation $target_rot" 2>/dev/null || true
                # Force immediate keyboard bar refresh when rotation changes
                tick=99
            fi
        fi

        # 2. Keyboard Spacing Check & Re-enforcement (every ~2 seconds / 10 ticks)
        tick=$((tick + 1))
        if [ "$hide_kbd" = "1" ] && [ "$tick" -ge 10 ]; then
            tick=0
            local kbd_val
            kbd_val=$(_host_cmd "cmd overlay lookup android android:bool/config_imeDrawsImeNavBar 2>/dev/null" | tr -d "[:space:]")
            if [ "$kbd_val" != "false" ]; then
                _host_cmd "cmd overlay fabricate --target android --name HideKeyboardBar android:bool/config_imeDrawsImeNavBar 0x12 0x0 2>/dev/null" || true
                _host_cmd "cmd overlay enable --user 0 com.android.shell:HideKeyboardBar 2>/dev/null" || true
            fi
        fi

        sleep 0.2
    done
}

start_guard() {
    local running_pid
    running_pid=$(_host_cmd "pgrep -f '[a]sl-ui-guard.sh run_loop'" 2>/dev/null | head -1)
    if [ -n "$running_pid" ]; then
        echo "$running_pid" > "$PID_FILE" 2>/dev/null || true
        chmod 666 "$PID_FILE" 2>/dev/null || true
        echo "[*] ASL UI Guard daemon is already RUNNING (PID: $running_pid)."
        return 0
    fi

    stop_guard >/dev/null 2>&1 || true

    echo "[*] Starting ASL Autonomous UI Guard daemon (Rotation + Keyboard Spacing)..."
    mkdir -p "${PREFIX}/tmp" 2>/dev/null || true

    local script_path="/data/data/com.termux/files/usr/share/asl/core/asl-ui-guard.sh"
    [ ! -f "$script_path" ] && script_path="$0"

    nohup bash "$script_path" run_loop >> "$LOG_FILE" 2>&1 </dev/null &
    local lpid=$!

    sleep 0.4
    local actual_pid
    actual_pid=$(_host_cmd "pgrep -f '[a]sl-ui-guard.sh run_loop'" 2>/dev/null | head -1)
    [ -z "$actual_pid" ] && actual_pid="$lpid"
    echo "$actual_pid" > "$PID_FILE" 2>/dev/null || true
    chmod 666 "$PID_FILE" 2>/dev/null || true
    echo "[✓] ASL UI Guard daemon ACTIVE (PID: $actual_pid, Polling: 0.2s)."
}

stop_guard() {
    local pids
    pids=$(_host_cmd "pgrep -f '[a]sl-ui-guard.sh run_loop'" 2>/dev/null)
    for p in $pids; do
        _host_cmd "kill -9 $p 2>/dev/null" || kill -9 "$p" 2>/dev/null || true
    done
    rm -f "$PID_FILE" 2>/dev/null || true
    echo "[✓] ASL UI Guard daemon STOPPED."
}

status_guard() {
    local pid
    pid=$(_host_cmd "pgrep -f '[a]sl-ui-guard.sh run_loop'" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid" > "$PID_FILE" 2>/dev/null || true
        echo " UI Guard:        ACTIVE (PID: $pid, 0.2s Rotation + Keyboard Spacing Enforced)"
        return 0
    fi
    echo " UI Guard:        INACTIVE"
    return 1
}

case "${1:-status}" in
    start)
        start_guard
        ;;
    stop)
        stop_guard
        ;;
    restart)
        stop_guard
        sleep 0.3
        start_guard
        ;;
    status)
        status_guard
        ;;
    run_loop)
        run_loop
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
