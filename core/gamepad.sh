#!/bin/bash
# ASL: Bluetooth Gamepad Passthrough & Evdev Input Mapper
# Detects host /dev/input/event* gamepads and passes input nodes into Debian chroot.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_chroot_mounted() {
    if ! su -c "grep -q -F ' $DEBIANPATH/proc ' /proc/mounts" 2>/dev/null; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

asl_gamepad_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- Bluetooth & USB Gamepad Passthrough ---"
    local found=0
    local dev

    for dev in /dev/input/event*; do
        [ -e "$dev" ] || continue
        # Query evdev device name via su getevent / cat /sys
        local sys_name=""
        local node_num="${dev##*/event}"
        if [ -f "/sys/class/input/event${node_num}/device/name" ]; then
            sys_name=$(cat "/sys/class/input/event${node_num}/device/name" 2>/dev/null)
        fi
        if [ -n "$sys_name" ]; then
            echo "  [$dev] -> $sys_name"
            found=$((found + 1))
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "No host gamepad/evdev input devices currently detected in /dev/input/"
        echo "Tip: Connect a Bluetooth controller (Xbox, PS4/PS5, Joy-Con) to Android."
    else
        echo "[✓] Total active input devices: $found"
    fi

    if su -c "grep -q -F ' $DEBIANPATH/dev/input ' /proc/mounts" 2>/dev/null; then
        echo "Debian Chroot Passthrough State: ACTIVE (/dev/input mounted)"
    else
        echo "Debian Chroot Passthrough State: INACTIVE (/dev/input unmounted)"
    fi
}

asl_gamepad_sync() {
    echo "[*] Mounting host /dev/input into Debian chroot..."
    ensure_chroot_mounted || return 1

    su -c "
        mkdir -p '$DEBIANPATH/dev/input'
        chmod 755 '$DEBIANPATH/dev/input'
        if ! grep -q -F ' $DEBIANPATH/dev/input ' /proc/mounts; then
            mount --bind /dev/input '$DEBIANPATH/dev/input' || true
        fi
        chmod 666 $DEBIANPATH/dev/input/event* 2>/dev/null || true
        chmod 666 $DEBIANPATH/dev/input/js* 2>/dev/null || true
    " 2>/dev/null || true

    echo "[✓] Gamepad evdev nodes synchronized into chroot."
}

asl_gamepad_test() {
    asl_gamepad_sync
    echo "[*] Testing gamepad input detection inside Debian chroot..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        if command -v jstest >/dev/null 2>&1; then
            echo \"Running jstest on /dev/input/js0 (Press Ctrl+C to exit)...\"
            jstest --normal /dev/input/js0 2>/dev/null || jstest /dev/input/event0
        elif command -v evtest >/dev/null 2>&1; then
            echo \"Running evtest...\"
            evtest
        else
            echo \"Installing joystick diagnostic tools (joystick, evtest)...\"
            apt-get update && apt-get install -y joystick evtest
            echo \"Run 'asl gamepad test' again to test live inputs.\"
        fi
    '"
}

case "${1:-status}" in
    status|list)
        asl_gamepad_status
        ;;
    sync|enable|map)
        asl_gamepad_sync
        ;;
    test)
        asl_gamepad_test
        ;;
    *)
        echo "Usage: asl gamepad [status|sync|test]"
        ;;
esac
