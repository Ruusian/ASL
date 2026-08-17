#!/bin/bash
# ASL: Automated Integrity Repair & System Recovery
# Diagnoses and repairs corrupt chroot state, mount leaks, permission issues, and broken package manager locks.

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

asl_repair_run() {
    local target="${1:-all}"
    echo "[*] Running ASL Automated Repair & Recovery (target: $target)..."

    # Step 1: Repair mounts & stale unmounts
    if [ "$target" = "mounts" ] || [ "$target" = "all" ]; then
        echo "[1/4] Checking and unmounting stale chroot mount points..."
        if [ -f "$SCRIPT_DIR/core/stop-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/stop-chroot.sh" >/dev/null 2>&1 || true
        fi
        echo "[1/4] Remounting fresh virtual filesystems..."
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || echo "[!] Mount check returned notice."
        fi
    fi

    # Step 2: Fix rootfs permissions
    if [ "$target" = "permissions" ] || [ "$target" = "all" ]; then
        echo "[2/4] Repairing critical directory permissions (/tmp, /dev/shm, /var/tmp)..."
        asl_exec "
            chmod 1777 '$DEBIANPATH/tmp' 2>/dev/null || true
            chmod 1777 '$DEBIANPATH/var/tmp' 2>/dev/null || true
            chmod 1777 '$DEBIANPATH/dev/shm' 2>/dev/null || true
            chmod 755 '$DEBIANPATH/dev' 2>/dev/null || true
            chmod 755 '$DEBIANPATH/dev/pts' 2>/dev/null || true
            chmod 755 '$DEBIANPATH/proc' 2>/dev/null || true
            chmod 755 '$DEBIANPATH/sys' 2>/dev/null || true
            mkdir -p '$DEBIANPATH/run/user/0' 2>/dev/null || true
            chmod 700 '$DEBIANPATH/run/user/0' 2>/dev/null || true
        "
    fi

    # Step 3: Repair DPKG package manager locks & broken installs
    if [ "$target" = "dpkg" ] || [ "$target" = "all" ] || [ "$target" = "libs" ]; then
        echo "[3/4] Repairing Debian DPKG / APT lock states & dynamic linker bindings (ldconfig)..."
        asl_chroot_exec "
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock*
            dpkg --configure -a 2>/dev/null || true
            apt-get install -f -y 2>/dev/null || true
            ldconfig 2>/dev/null || true
        " 2>/dev/null || true
    fi

    # Step 4: Re-sync dynamic environment profiles
    if [ "$target" = "env" ] || [ "$target" = "all" ]; then
        echo "[4/4] Resynchronizing dynamic profile.d GPU/HUD environment variables..."
        source "$SCRIPT_DIR/core/gpu-profile.sh"
        asl_sync_chroot_env
    fi

    echo "[✓] ASL Integrity Repair completed successfully."
}

case "${1:-all}" in
    run|all|mounts|permissions|dpkg|env|libs)
        asl_repair_run "${1:-all}"
        ;;
    *)
        echo "Usage: asl repair [all|mounts|permissions|dpkg|env|libs]"
        ;;
esac
