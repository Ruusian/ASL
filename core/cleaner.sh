#!/bin/bash
# ASL: Storage Cleaner & Cache Purger
# Safely reclaims storage space by purging apt caches, temporary files, Mesa shader caches, and Wine logs.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_chroot_mounted() {
    if ! is_mounted; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

asl_clean_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- ASL Storage Usage & Cleanable Cache ---"
    local du_root du_apt du_tmp du_wine
    du_root=$(du -sh "$DEBIANPATH" 2>/dev/null | cut -f1)
    du_apt=$(asl_exec "du -sh '$DEBIANPATH/var/cache/apt/archives' 2>/dev/null" | cut -f1)
    du_tmp=$(asl_exec "du -sh '$DEBIANPATH/tmp' 2>/dev/null" | cut -f1)
    du_wine=$(asl_exec "du -sh '$DEBIANPATH/root/.cache' 2>/dev/null" | cut -f1)

    echo "Debian RootFS Total Size: ${du_root:-unknown}"
    echo "  - APT Package Archives Cache: ${du_apt:-0B}"
    echo "  - Chroot Temp Dir (/tmp):    ${du_tmp:-0B}"
    echo "  - User Cache (~/.cache):     ${du_wine:-0B}"
}

asl_clean_run() {
    local mode="${1:-all}"
    ensure_chroot_mounted || return 1
    echo "[*] Cleaning ASL storage cache (mode: $mode)..."

    asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        case \"$mode\" in
            apt)
                echo \"[*] Purging APT package cache...\"
                apt-get clean
                rm -rf /var/lib/apt/lists/*
                ;;
            tmp)
                echo \"[*] Cleaning /tmp and /var/tmp...\"
                rm -rf /tmp/* /tmp/.* /tmp/.X11-unix/X* /tmp/.X0-lock /tmp/pulse-* 2>/dev/null || true
                rm -rf /var/tmp/* 2>/dev/null || true
                ;;
            cache)
                echo \"[*] Cleaning user build & shader cache (~/.cache & /tmp/.mesa_cache)...\"
                rm -rf /root/.cache/* /home/*/.cache/* /tmp/.mesa_cache/* 2>/dev/null || true
                ;;
            all)
                echo \"[*] Purging APT package cache...\"
                apt-get clean
                rm -rf /var/lib/apt/lists/*
                echo \"[*] Cleaning temporary files...\"
                rm -rf /tmp/* /var/tmp/* /tmp/.X11-unix/X* /tmp/.X0-lock /tmp/pulse-* 2>/dev/null || true
                echo \"[*] Cleaning user cache & shader cache...\"
                rm -rf /root/.cache/* /home/*/.cache/* /tmp/.mesa_cache/* 2>/dev/null || true
                ;;
            *)
                echo \"[!] Unknown clean mode: $mode\"
                echo \"Usage: asl clean [all|apt|tmp|cache]\"
                exit 1
                ;;
        esac
    "

    # Also clean host side Mesa shader cache if present
    rm -rf /dev/shm/mesa_shader_cache/* /tmp/.mesa_cache/* 2>/dev/null || true

    echo "[✓] Storage cleanup completed successfully."
}

case "${1:-status}" in
    status|du)
        asl_clean_status
        ;;
    run|clean|all|apt|tmp|cache)
        asl_clean_run "${1:-all}"
        ;;
    *)
        echo "Usage: asl clean [status|all|apt|tmp|cache]"
        ;;
esac
