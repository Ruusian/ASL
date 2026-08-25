#!/bin/bash
# ASL: Storage Cleaner & Cache Purger
# Safely reclaims storage space by purging apt caches, temporary files, Mesa shader caches, and Wine logs.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_require_default_debianpath
# Refuse to operate when the target is the host root, which would wipe host /tmp.
if [ "$DEBIANPATH" = "/" ]; then
    echo "Error: refusing to clean DEBIANPATH '/'. Run inside a real chroot only." >&2
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
    du_root=$(asl_exec "du -sh -x '$DEBIANPATH' 2>/dev/null" | cut -f1)
    [ -n "$du_root" ] || du_root=$(du -sh "$DEBIANPATH" 2>/dev/null | cut -f1)
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
    # If a desktop/X11 session is live, never remove the display socket/lock —
    # doing so kills the active Termux:X11 session.
    local x11_active=0
    if pgrep -f "termux-x11.*:[0-9]" >/dev/null 2>&1 || pgrep -f "Xorg.*:[0-9]" >/dev/null 2>&1; then
        x11_active=1
    fi

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
                if [ \"$x11_active\" = \"1\" ]; then
                    find /tmp /var/tmp -mindepth 1 ! -name '.X11-unix*' ! -name '.X0-lock' ! -name 'pulse*' ! -name '.asl*' -delete 2>/dev/null || true
                else
                    rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
                fi
                ;;
            cache)
                echo \"[*] Cleaning user build & shader cache (~/.cache & /tmp/.mesa_cache)...\"
                rm -rf /root/.cache/* /home/*/.cache/* /tmp/.mesa_cache/* 2>/dev/null || true
                ;;
            all|run|clean)
                echo \"[*] Purging APT package cache...\"
                apt-get clean
                rm -rf /var/lib/apt/lists/*
                echo \"[*] Cleaning temporary files...\"
                if [ \"$x11_active\" = \"1\" ]; then
                    find /tmp /var/tmp -mindepth 1 ! -name '.X11-unix*' ! -name '.X0-lock' ! -name 'pulse*' ! -name '.asl*' -delete 2>/dev/null || true
                else
                    rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
                fi
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

    # Also clean host side Mesa shader cache and temporary execution wrappers if present
    asl_exec "rm -rf /dev/shm/mesa_shader_cache/* /tmp/.mesa_cache/* '${PREFIX:-/data/data/com.termux/files/usr}/tmp/.mesa_cache'/* '${PREFIX:-/data/data/com.termux/files/usr}/tmp/.asl_cmd_'*.sh 2>/dev/null" || true
    rm -rf "${PREFIX:-/data/data/com.termux/files/usr}/tmp/.mesa_cache"/* "${PREFIX:-/data/data/com.termux/files/usr}/tmp/.asl_cmd_"*.sh 2>/dev/null || true

    echo "[✓] Storage cleanup completed successfully."
}

case "${1:-status}" in
    status|du)
        asl_clean_status
        ;;
    run|clean|all|apt|tmp|cache)
        asl_acquire_lock || { echo "[!] Another ASL operation is in progress; try again shortly."; exit 1; }
        trap asl_release_lock EXIT INT TERM
        asl_clean_run "${1:-all}"
        ;;
    *)
        echo "Usage: asl clean [status|all|apt|tmp|cache]"
        ;;
esac
