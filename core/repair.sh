#!/bin/bash
# ASL: Automated Integrity Repair & System Recovery
# Diagnoses and repairs corrupt chroot state, mount leaks, permission issues, and broken package manager locks.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_require_default_debianpath

asl_repair_run() {
    local target="${1:-all}"
    [ "$target" = "run" ] && target="all"
    echo "[*] Running ASL Automated Repair & Recovery (target: $target)..."

    local was_desktop_running=0
    if pgrep -f "xfce4-session|xfwm4" >/dev/null 2>&1; then
        was_desktop_running=1
        echo "[!] Active desktop session detected — saving session state for auto-restart after repair..."
    fi

    ensure_chroot_mounted 2>/dev/null || true

    # Step 1: Repair mounts & stale unmounts
    if [ "$target" = "mounts" ] || [ "$target" = "all" ]; then
        echo "[1/4] Checking and unmounting stale chroot mount points..."
        local stop_script
        stop_script=$(asl_find_script "stop-chroot.sh")
        if [ -f "$stop_script" ]; then
            bash "$stop_script" >/dev/null 2>&1 || true
        fi
        echo "[1/4] Remounting fresh virtual filesystems..."
        local mount_script
        mount_script=$(asl_find_script "mount-chroot.sh")
        if [ -f "$mount_script" ]; then
            bash "$mount_script" || echo "[!] Mount check returned notice."
        fi
    fi

    # Step 2: Fix rootfs permissions & GPU/IPC sockets
    if [ "$target" = "permissions" ] || [ "$target" = "all" ]; then
        echo "[2/4] Repairing critical directory permissions, GPU device nodes, and stale IPC sockets..."
        asl_exec "
            chmod 666 /dev/kgsl-3d0 2>/dev/null || true
            chmod 666 /dev/dri/renderD128 2>/dev/null || true
            chmod 666 /dev/dri/card0 2>/dev/null || true
            chmod 1777 '$DEBIANPATH/tmp' 2>/dev/null || true
            chmod 1777 '$DEBIANPATH/var/tmp' 2>/dev/null || true
            chmod 1777 '$DEBIANPATH/dev/shm' 2>/dev/null || true
            chmod 755 '$DEBIANPATH/dev' 2>/dev/null || true
            chmod 755 '$DEBIANPATH/dev/pts' 2>/dev/null || true
            mkdir -p '$DEBIANPATH/run/user/0' 2>/dev/null || true
            chmod 700 '$DEBIANPATH/run/user/0' 2>/dev/null || true
            chmod +x '$DEBIANPATH/root/Desktop'/*.desktop 2>/dev/null || true
            chmod +x '$DEBIANPATH/usr/share/applications'/*.desktop 2>/dev/null || true
            rm -f '$DEBIANPATH/tmp/.X11-unix/X0.lock' 2>/dev/null || true
            rm -f '$DEBIANPATH/tmp/pulse-socket.lock' 2>/dev/null || true
        "
    fi

    # Step 3: Repair DPKG package manager locks, DNS & broken installs
    if [ "$target" = "dpkg" ] || [ "$target" = "all" ] || [ "$target" = "libs" ]; then
        echo "[3/4] Repairing Debian DPKG / APT lock states, DNS configuration & dynamic linker bindings (ldconfig)..."
        # Ensure DNS in chroot
        asl_exec "
            if [ ! -s '$DEBIANPATH/etc/resolv.conf' ]; then
                mkdir -p '$DEBIANPATH/etc'
                printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > '$DEBIANPATH/etc/resolv.conf'
            fi
        "
        asl_chroot_exec "
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            if pgrep -f '^(apt|apt-get|dpkg)$' >/dev/null 2>&1; then
                echo '[!] Active APT/DPKG process detected; terminating stuck package managers...'
                pkill -f '^(apt|apt-get|dpkg)$' 2>/dev/null || true
                sleep 1
                pkill -9 -f '^(apt|apt-get|dpkg)$' 2>/dev/null || true
            fi
            rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock* /var/lib/apt/lists/lock*
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

    if [ "$was_desktop_running" -eq 1 ]; then
        echo "[*] Auto-restoring XFCE4 desktop session post-repair..."
        local desk_script
        desk_script=$(asl_find_script "start-desktop.sh")
        if [ -f "$desk_script" ]; then
            bash "$desk_script" start >/dev/null 2>&1 || true
        fi
    fi

    echo "[✓] ASL Integrity Repair completed successfully."
}

case "${1:-all}" in
    run|all|mounts|permissions|dpkg|env|libs)
        asl_acquire_lock || { echo "[!] Another ASL operation is in progress; try again shortly."; exit 1; }
        trap asl_release_lock EXIT INT TERM
        asl_repair_run "${1:-all}"
        ;;
    *)
        echo "Usage: asl repair [all|mounts|permissions|dpkg|env|libs]"
        ;;
esac
