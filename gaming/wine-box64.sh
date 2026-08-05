#!/bin/bash
# AndroidLinux-SuperKit: Gaming Layer Helper
# Wine + Box64 Status & Execution Wrapper

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/gpu-profile.sh"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

check_emulation_available() {
    if ! su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/wine -o -x /usr/bin/box64" 2>/dev/null; then
        echo "[!] Wine / Box64 emulation packages are not installed in Debian."
        echo "    x86/x64 Windows emulation is currently disabled on this system."
        return 1
    fi
    return 0
}

show_gaming_menu() {
    echo "=========================================="
    echo "       SuperKit Gaming Launcher"
    echo "=========================================="
    if ! check_emulation_available; then
        return 1
    fi
    echo "1) Launch Wine Config (winecfg)"
    echo "2) Run Windows Executable (.exe)"
    echo "3) Exit"
    echo ""
}

run_wine_exe() {
    if ! check_emulation_available; then
        return 1
    fi
    EXE_PATH="${1:-}"
    if [ -z "$EXE_PATH" ]; then
        echo -n "Enter full path to .exe file: "
        read -r EXE_PATH
    fi

    if [ ! -f "$EXE_PATH" ]; then
        echo "[!] File not found: $EXE_PATH"
        return 1
    fi

    superkit_gpu_apply
    echo "[*] Executing $EXE_PATH..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c 'export DISPLAY=:0; wine \"$EXE_PATH\"'"
}

case "${1:-}" in
    run)
        shift
        run_wine_exe "$@"
        ;;
    menu|"")
        show_gaming_menu
        ;;
    *)
        run_wine_exe "$@"
        ;;
esac
