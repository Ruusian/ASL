#!/bin/bash
# ASL: Wayland & Xwayland Display Backend Manager

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/asl"
BACKEND_FILE="$STATE_DIR/display_backend"
WAYLAND_SOCKET_NAME="${WAYLAND_DISPLAY:-wayland-0}"
TERMUX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"

ensure_state_dir() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
}

asl_get_backend() {
    if [ -f "$BACKEND_FILE" ]; then
        cat "$BACKEND_FILE" 2>/dev/null | tr -d '[:space:]'
    else
        echo "x11"
    fi
}

asl_set_backend() {
    ensure_state_dir
    local target="${1:-x11}"
    case "$target" in
        wayland|xwayland)
            echo "wayland" > "$BACKEND_FILE"
            echo "[✓] Display backend set to: WAYLAND (Native Wayland / Xwayland)."
            ;;
        x11|termux-x11|default)
            echo "x11" > "$BACKEND_FILE"
            echo "[✓] Display backend set to: X11 (Termux:X11)."
            ;;
        *)
            echo "Error: Unknown backend '$target'. Choices: x11 | wayland"
            return 1
            ;;
    esac
}

asl_detect_wayland_socket() {
    local candidate
    for candidate in \
        "${XDG_RUNTIME_DIR:-/tmp}/$WAYLAND_SOCKET_NAME" \
        "$TERMUX_TMP/$WAYLAND_SOCKET_NAME" \
        "/tmp/$WAYLAND_SOCKET_NAME"; do
        if [ -S "$candidate" ] || [ -e "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

asl_wayland_status() {
    local current socket_path
    current=$(asl_get_backend)
    echo "Display Backend: ${current^^}"
    if socket_path=$(asl_detect_wayland_socket); then
        echo "  - Wayland Socket: DETECTED ($socket_path)"
    else
        echo "  - Wayland Socket: NOT DETECTED (Termux:X11 / X11 fallback)"
    fi
}

asl_wayland_env_exports() {
    local backend socket_path
    backend=$(asl_get_backend)
    if [ "$backend" = "wayland" ]; then
        socket_path=$(asl_detect_wayland_socket || true)
        printf 'export XDG_SESSION_TYPE="wayland"\n'
        printf 'export WAYLAND_DISPLAY="%s"\n' "${socket_path:-wayland-0}"
        printf 'export QT_QPA_PLATFORM="wayland;xcb"\n'
        printf 'export GDK_BACKEND="wayland,x11"\n'
        printf 'export CLUTTER_BACKEND="wayland"\n'
        printf 'export DISPLAY=":0"\n'
    else
        printf 'export XDG_SESSION_TYPE="x11"\n'
        printf 'export DISPLAY=":0"\n'
        printf 'unset WAYLAND_DISPLAY QT_QPA_PLATFORM GDK_BACKEND CLUTTER_BACKEND\n'
    fi
}

case "${1:-status}" in
    set|backend)
        shift
        asl_set_backend "$@"
        ;;
    status)
        asl_wayland_status
        ;;
    env|exports)
        asl_wayland_env_exports
        ;;
    *)
        echo "Usage: asl wayland [status|set <x11|wayland>|env]"
        ;;
esac
