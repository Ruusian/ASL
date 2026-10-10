#!/bin/bash
# ASL Fast 0.2s Rotation Guard Daemon
# Actively monitors and enforces 90° Forced Landscape lock (accelerometer=0, user_rotation=1).

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PID_FILE="${PREFIX}/tmp/.asl_rotation_watcher.pid"
LOG_FILE="${PREFIX}/tmp/asl-rotation-guard.log"
CONF_FILE="/data/data/com.termux/files/home/.config/asl/rotation.conf"
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
    while true; do
        local is_forced=1
        local target_rot=1

        if [ -f "$CONF_FILE" ]; then
            local f_val r_val
            f_val=$(grep -E "^FORCED_LANDSCAPE=" "$CONF_FILE" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
            [ -n "$f_val" ] && is_forced="$f_val"
            r_val=$(grep -E "^USER_ROTATION=" "$CONF_FILE" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
            [ -n "$r_val" ] && target_rot="$r_val"
        elif [ -f "$STATE_FILE" ]; then
            local f_val r_val
            f_val=$(grep -E "^FORCED_LANDSCAPE=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
            [ -n "$f_val" ] && is_forced="$f_val"
            r_val=$(grep -E "^USER_ROTATION=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d "[:space:]")
            [ -n "$r_val" ] && target_rot="$r_val"
        fi

        if [ "$is_forced" = "1" ]; then
            local accel u_rot
            accel=$(_host_cmd "settings get system accelerometer_rotation" 2>/dev/null | tr -d "[:space:]")
            u_rot=$(_host_cmd "settings get system user_rotation" 2>/dev/null | tr -d "[:space:]")
            if [ "$accel" = "1" ] || [ "$u_rot" != "$target_rot" ]; then
                _host_cmd "settings put system accelerometer_rotation 0" 2>/dev/null || true
                _host_cmd "settings put system user_rotation $target_rot" 2>/dev/null || true
            fi
        fi
        sleep 0.2
    done
}

start_guard() {
    local running_pid
    running_pid=$(su -c "pgrep -f 'rotation-guard.sh run_loop'" 2>/dev/null | head -1); [ -z "$pid" ] && pid=$(pgrep -f "rotation-guard.sh run_loop" 2>/dev/null | head -1)
    if [ -n "$running_pid" ]; then
        echo "$running_pid" > "$PID_FILE"
        echo "[*] Rotation guard daemon is already RUNNING (PID: $running_pid)."
        return 0
    fi

    stop_guard >/dev/null 2>&1 || true

    echo "[*] Starting ASL Fast 0.2s Rotation Guard daemon..."
    mkdir -p "${PREFIX}/tmp" 2>/dev/null || true

    local script_path="/data/data/com.termux/files/usr/share/asl/core/rotation-guard.sh"
    [ ! -f "$script_path" ] && script_path="$0"

    nohup bash "$script_path" run_loop >> "$LOG_FILE" 2>&1 </dev/null &
    local lpid=$!

    echo "$lpid" > "$PID_FILE"
    echo "[✓] Rotation guard daemon ACTIVE (PID: $lpid, Polling: 0.2s Loop)."
}

stop_guard() {
    if [ -f "$PID_FILE" ]; then
        local p
        p=$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$p" ]; then
            kill -9 "$p" 2>/dev/null || true
        fi
        rm -f "$PID_FILE" 2>/dev/null || true
    fi
    pkill -9 -f "rotation-guard.sh run_loop" 2>/dev/null || true
    echo "[✓] Rotation guard daemon STOPPED."
}

status_guard() {
    local pid
    pid=$(su -c "pgrep -f 'rotation-guard.sh run_loop'" 2>/dev/null | head -1); [ -z "$pid" ] && pid=$(pgrep -f "rotation-guard.sh run_loop" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid" > "$PID_FILE" 2>/dev/null || true
        echo " Rotation Guard: ACTIVE (PID: $pid, Polling: 0.2s Loop)"
        return 0
    fi
    echo " Rotation Guard: INACTIVE"
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
