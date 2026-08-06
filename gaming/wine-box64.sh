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

setup_gaming() {
    echo "[*] Initializing Gaming Environment dependencies inside Debian chroot..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        dpkg --add-architecture i386 2>/dev/null || true
        CODENAME=\$(grep -oP \"(?<=VERSION_CODENAME=)[a-z]+\" /etc/os-release 2>/dev/null || echo trixie)
        [ -n \"\$CODENAME\" ] || CODENAME=trixie
        echo \"deb http://deb.debian.org/debian \$CODENAME main contrib non-free non-free-firmware\" > /etc/apt/sources.list
        apt-get update && apt-get install -y wine wine64 wine32:i386 box64 dxvk winetricks fonts-liberation libvulkan1 cabextract wget unzip || true
    '"
    echo "[*] Setting up Wine win64 prefix..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        export WINEARCH=win64
        export WINEPREFIX=/root/.wine
        wineboot -u 2>/dev/null || true
    '"
    echo "[✓] Gaming Environment setup completed."
}

show_gaming_menu() {
    echo "=========================================="
    echo "       SuperKit Gaming Launcher"
    echo "=========================================="
    if ! check_emulation_available; then
        echo "0) Auto-Install Wine / Box64 Gaming Packages"
    fi
    echo "1) Launch Wine Configuration (winecfg)"
    echo "2) Launch Winetricks helper (winetricks)"
    echo "3) Run Windows Executable (.exe)"
    echo "4) Exit"
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
    echo "[*] Executing $EXE_PATH with Box64 + Wine64..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        export DISPLAY=:0
        export WINEARCH=win64
        export WINEPREFIX=/root/.wine
        export DXVK_ASYNC=1
        export MALLOC_ARENA_MAX=2
        export BOX64_DYNAREC_STRONGMEM=2
        export BOX64_DYNAREC_SAFEFLAGS=2
        wine \"$EXE_PATH\"
    '"
}

run_winecfg() {
    if ! check_emulation_available; then return 1; fi
    echo "[*] Opening Wine Configuration..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c 'export DISPLAY=:0; winecfg'"
}

run_winetricks() {
    if ! check_emulation_available; then return 1; fi
    echo "[*] Launching Winetricks..."
    su -c "chroot '$DEBIANPATH' /bin/bash -c 'export DISPLAY=:0; winetricks'"
}

case "${1:-}" in
    setup|setup-gaming)
        setup_gaming
        ;;
    winecfg|cfg)
        run_winecfg
        ;;
    winetricks|tricks)
        run_winetricks
        ;;
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
