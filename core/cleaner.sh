#!/bin/bash
# ASL: Storage Cleaner & Cache Purger
# Safely reclaims storage space by purging apt caches, temporary files, Mesa shader caches, and logs.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_require_default_debianpath
# Refuse to operate when the target is the Android host root, which would wipe host /tmp.
if [ "$DEBIANPATH" = "/" ] && [ ! -f /etc/debian_version ]; then
    echo "Error: refusing to clean host root. Run inside a real chroot only." >&2
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
    local du_root du_apt du_tmp du_cache
    du_root=$(asl_exec "du -sh -x '$DEBIANPATH' 2>/dev/null" | cut -f1)
    [ -n "$du_root" ] || du_root=$(du -sh "$DEBIANPATH" 2>/dev/null | cut -f1)
    du_apt=$(asl_exec "du -sh '$DEBIANPATH/var/cache/apt/archives' 2>/dev/null" | cut -f1)
    du_tmp=$(asl_exec "du -sh '$DEBIANPATH/tmp' 2>/dev/null" | cut -f1)
    du_cache=$(asl_exec "du -sh '$DEBIANPATH/root/.cache' 2>/dev/null" | cut -f1)

    echo "Debian RootFS Total Size: ${du_root:-unknown}"
    echo "  - APT Package Archives Cache: ${du_apt:-0B}"
    echo "  - Chroot Temp Dir (/tmp):    ${du_tmp:-0B}"
    echo "  - User Cache (~/.cache):     ${du_cache:-0B}"
}

clean_tmp_files() {
    # Safe ephemeral cleanup: only remove stale temp files older than 30 mins
    # Never delete active session sockets, locks, or Claude Code / OpenClaude worker outputs.
    find /tmp /var/tmp -maxdepth 2 -type f \( -name '*.tmp' -o -name 'asl-start-xfce-*.sh' -o -name '.asl_cmd_*.sh' -o -name '.asl_chroot_cmd_*.sh' -o -name 'app_launch.log' -o -name 'proton-ge.tar.gz' -o -name 'cs.tar.gz' \) -mmin +30 -delete 2>/dev/null || true
    find /tmp -maxdepth 1 -type f -name 'core.*' -delete 2>/dev/null || true
}

asl_clean_run() {
    local mode="${1:-safe}"
    ensure_chroot_mounted || return 1
    echo "[*] Cleaning ASL storage cache (mode: $mode)..."

    asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        case '$mode' in
            apt)
                echo '[*] Purging APT package cache...'
                apt-get clean
                rm -rf /var/lib/apt/lists/*
                ;;
            tmp)
                echo '[*] Cleaning stale temporary files in /tmp and /var/tmp...'
                find /tmp /var/tmp -maxdepth 2 -type f \( -name '*.tmp' -o -name 'asl-*.sh' -o -name '.asl_chroot_cmd_*.sh' -o -name 'app_launch.log' -o -name 'proton-ge.tar.gz' \) -mmin +30 -delete 2>/dev/null || true
                ;;
            cache)
                echo '[*] Cleaning user build & shader cache (~/.cache & /tmp/.mesa_cache)...'
                rm -rf /root/.cache/* /home/*/.cache/* /tmp/.mesa_cache/* 2>/dev/null || true
                ;;
            safe|all|run|clean)
                echo '[*] Purging APT package cache...'
                apt-get clean
                rm -rf /var/lib/apt/lists/*
                echo '[*] Cleaning stale temporary files...'
                find /tmp /var/tmp -maxdepth 2 -type f \( -name '*.tmp' -o -name 'asl-*.sh' -o -name '.asl_chroot_cmd_*.sh' -o -name 'app_launch.log' -o -name 'proton-ge.tar.gz' \) -mmin +30 -delete 2>/dev/null || true
                echo '[*] Cleaning user cache & shader cache...'
                rm -rf /root/.cache/* /home/*/.cache/* /tmp/.mesa_cache/* 2>/dev/null || true
                ;;
            deep)
                echo '[*] Running Deep Storage Clean...'
                echo '[*] Purging APT package cache & unused packages...'
                apt-get clean
                apt-get autoremove -y 2>/dev/null || true
                rm -rf /var/lib/apt/lists/*
                echo '[*] Cleaning stale temporary files...'
                find /tmp /var/tmp -maxdepth 2 -type f \( -name '*.tmp' -o -name 'asl-*.sh' -o -name '.asl_chroot_cmd_*.sh' -o -name 'app_launch.log' -o -name 'proton-ge.tar.gz' \) -mmin +30 -delete 2>/dev/null || true
                echo '[*] Purging user cache, shader cache & truncating old logs...'
                rm -rf /root/.cache/* /home/*/.cache/* /tmp/.mesa_cache/* 2>/dev/null || true
                find /var/log -type f -name '*.log' -exec truncate -s 0 {} + 2>/dev/null || true
                ;;
            *)
                echo '[!] Unknown clean mode: $mode'
                echo 'Usage: asl clean [safe|deep|all|apt|tmp|cache|dry-run]'
                exit 1
                ;;
        esac
    "

    # Also safely clean host side Mesa shader cache and old execution wrappers (>30m)
    clean_tmp_files
    find "${PREFIX:-/data/data/com.termux/files/usr}/tmp" -maxdepth 1 -name '.asl_cmd_*.sh' -mmin +30 -delete 2>/dev/null || true
    asl_exec "rm -rf /dev/shm/mesa_shader_cache/* /tmp/.mesa_cache/* '${PREFIX:-/data/data/com.termux/files/usr}/tmp/.mesa_cache'/* 2>/dev/null" || true
    rm -rf "${PREFIX:-/data/data/com.termux/files/usr}/tmp/.mesa_cache"/* 2>/dev/null || true

    echo "[✓] Storage cleanup completed successfully."
}

case "${1:-status}" in
    status|du|dry-run|dryrun)
        asl_clean_status
        ;;
    run|clean|safe|deep|all|apt|tmp|cache)
        asl_acquire_lock || { echo "[!] Another ASL operation is in progress; try again shortly."; exit 1; }
        trap asl_release_lock EXIT INT TERM
        asl_clean_run "${1:-safe}"
        ;;
    *)
        echo "Usage: asl clean [status|safe|deep|all|apt|tmp|cache|dry-run]"
        ;;
esac
