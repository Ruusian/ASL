#!/bin/bash
# Android Subsystem for Linux (ASL): Safe Chroot Mount Script
# ZERO host system/vendor/apex mounts to protect Android OS stability

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "${ASL_EXEC_MODE:-root}" = "proot" ]; then
    if [ -d "$DEBIANPATH" ] || [ -d "$PREFIX/var/lib/proot-distro/containers/asl-debian" ]; then
        echo "[✓] PRoot user-space subsystem active — environment ready at $DEBIANPATH."
        exit 0
    else
        echo "[!] Error: Subsystem rootfs not found at $DEBIANPATH"
        echo "    To install a Linux rootfs, run: asl install"
        exit 1
    fi
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "[!] Error: Debian chroot rootfs not found at /data/local/tmp/chrootDebian"
    echo "    To install a Debian rootfs, run: asl install"
    echo "    Or check if proot-distro is installed: which proot-distro"
    exit 1
fi

TERMUX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"

echo "[*] Mounting Linux chroot environment at $DEBIANPATH..."

asl_exec "
    set -e

    cleanup_on_error() {
        echo '[!] Mount error encountered; rolling back partial mounts...' >&2
        for m in \"$DEBIANPATH/proc/sys/fs/binfmt_misc\" \"$DEBIANPATH/dev/pts\" \"$DEBIANPATH/proc\" \"$DEBIANPATH/sys\" \"$DEBIANPATH/dev/shm\" \"$DEBIANPATH/run\" \"$DEBIANPATH/var/lock\" \"$DEBIANPATH/tmp\" \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\" \"$DEBIANPATH/sdcard\" \"$DEBIANPATH/dev\" \"$DEBIANPATH\"; do
            grep -q -F \" \$m \" /proc/mounts 2>/dev/null && umount -l \"\$m\" 2>/dev/null || true
        done
    }
    trap cleanup_on_error ERR

    is_mounted() {
        local target
        target=\$(readlink -f \"\$1\" 2>/dev/null || echo \"\$1\")
        grep -q -F \" \$target \" /proc/mounts 2>/dev/null
    }

    if ! is_mounted \"$DEBIANPATH\"; then
        mount --bind \"$DEBIANPATH\" \"$DEBIANPATH\"
    fi
    mount --make-rprivate \"$DEBIANPATH\" 2>/dev/null || true

    domount_bind() {
        if ! is_mounted \"\$2\"; then
            mkdir -p \"\$2\"
            mount --bind \"\$1\" \"\$2\"
            mount --make-rslave \"\$2\" 2>/dev/null || true
        fi
    }

    domount_fs() {
        if ! is_mounted \"\$2\"; then
            mkdir -p \"\$2\"
            mount -t \"\$1\" \"\$1\" \"\$2\"
        fi
    }

    domount_tmpfs() {
        if ! is_mounted \"\$1\"; then
            mkdir -p \"\$1\"
            mount -t tmpfs -o \"\$2\" tmpfs \"\$1\"
        fi
    }

    domount_bind /dev \"$DEBIANPATH/dev\"
    # Android's graphics group (GID 1003) owns /dev/input nodes; grant that
    # group rw access for the chroot instead of making devices world-writable
    # (0666 lets any host or chroot process inject input events).
    for dev in /dev/input/event* /dev/input/js* /dev/input/mouse* /dev/input/mice; do
        [ -e \"\$dev\" ] || continue
        chgrp 1003 \"\$dev\" 2>/dev/null || true
        chmod 0660 \"\$dev\" 2>/dev/null || true
    done
    domount_fs proc \"$DEBIANPATH/proc\"
    domount_fs sysfs \"$DEBIANPATH/sys\"
    domount_bind /dev/pts \"$DEBIANPATH/dev/pts\"

    if [ -d /proc/sys/fs/binfmt_misc ] && grep -q -w \"/proc/sys/fs/binfmt_misc\" /proc/mounts 2>/dev/null; then
        domount_bind /proc/sys/fs/binfmt_misc \"$DEBIANPATH/proc/sys/fs/binfmt_misc\"
    fi

    if [ -d /sdcard ]; then
        domount_bind /sdcard \"$DEBIANPATH/sdcard\"
    fi

    mkdir -p \"$TERMUX_TMP\"
    chmod 1777 \"$TERMUX_TMP\"
    if ! is_mounted \"$DEBIANPATH/tmp\"; then
        mount --bind \"$TERMUX_TMP\" \"$DEBIANPATH/tmp\"
        mount --make-rslave \"$DEBIANPATH/tmp\" 2>/dev/null || true
    fi
    mkdir -p \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
    if ! is_mounted \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"; then
        mount --bind \"$TERMUX_TMP\" \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
        mount --make-rslave \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\" 2>/dev/null || true
    fi
    domount_tmpfs \"$DEBIANPATH/run\" rw,nosuid,nodev,mode=0755,noatime
    domount_tmpfs \"$DEBIANPATH/dev/shm\" rw,nosuid,nodev,noatime,size=2G

    if [ -d \"$DEBIANPATH/var\" ] && [ ! -L \"$DEBIANPATH/var/lock\" ]; then
        domount_tmpfs \"$DEBIANPATH/var/lock\" rw,nosuid,nodev,mode=1777,noatime
    fi

    if [ ! -s \"$DEBIANPATH/etc/resolv.conf\" ]; then
        mkdir -p \"$DEBIANPATH/etc\"
        dns1=\$(getprop net.dns1 2>/dev/null)
        dns2=\$(getprop net.dns2 2>/dev/null)
        if [ -n \"\$dns1\" ]; then
            printf 'nameserver %s\n' \"\$dns1\" > \"$DEBIANPATH/etc/resolv.conf\"
            [ -n \"\$dns2\" ] && printf 'nameserver %s\n' \"\$dns2\" >> \"$DEBIANPATH/etc/resolv.conf\"
        elif [ -f /data/data/com.termux/files/usr/etc/resolv.conf ]; then
            cp /data/data/com.termux/files/usr/etc/resolv.conf \"$DEBIANPATH/etc/resolv.conf\" 2>/dev/null || true
        fi
        if [ ! -s \"$DEBIANPATH/etc/resolv.conf\" ]; then
            printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > \"$DEBIANPATH/etc/resolv.conf\"
        fi
    fi

    trap - ERR
" || {
    echo "[!] Chroot mount failed during initialization."
    echo "    Troubleshooting:"
    echo "    - Verify Debian rootfs exists: ls -la $DEBIANPATH"
    echo "    - Check root access: su -c id"
    echo "    - View error logs: dmesg | tail -20"
    echo "    💡 Hint: Ensure your device is rooted and Termux is granted Superuser access in Magisk / KernelSU / APatch."
    exit 1
}

if ! is_mounted; then
    echo "[!] Chroot mount verification failed - /proc not mounted."
    echo "    Verify: grep $DEBIANPATH /proc/mounts"
    exit 1
fi

if [ "${ASL_EXEC_MODE:-root}" = "root" ]; then
    # Sysctl tuning is host-kernel; always apply if root.
    # Save previous values first so `asl stop` can restore them.
    SYSCTL_BACKUP="/data/local/tmp/asl_sysctl_orig"
    SYSCTL_TMP="/data/local/tmp/asl_sysctl_orig.tmp"
    # A repeated `asl start` must retain the values from before ASL's first tune.
    # Create the backup once; stop-chroot removes it after restoration.
    if ! asl_exec "test -e '$SYSCTL_BACKUP'" 2>/dev/null; then
        asl_exec "rm -f '$SYSCTL_TMP'" 2>/dev/null || true
        for kv in vm.swappiness=60 vm.vfs_cache_pressure=50 vm.dirty_ratio=15 vm.dirty_background_ratio=5; do
            key="${kv%%=*}"
            cur="$(asl_exec "sysctl -n '$key'" 2>/dev/null | tr -d '[:space:]')"
            if [ -n "$cur" ] && [ "$cur" != "${kv#*=}" ]; then
                asl_exec "printf '%s\\n' '$key=$cur' >> '$SYSCTL_TMP'" 2>/dev/null || true
            fi
        done
        if asl_exec "test -s '$SYSCTL_TMP'" 2>/dev/null; then
            asl_exec "mv -f '$SYSCTL_TMP' '$SYSCTL_BACKUP'" 2>/dev/null || true
        else
            asl_exec "touch '$SYSCTL_BACKUP'" 2>/dev/null || true
            asl_exec "rm -f '$SYSCTL_TMP'" 2>/dev/null || true
        fi
    fi
    for kv in vm.swappiness=60 vm.vfs_cache_pressure=50 vm.dirty_ratio=15 vm.dirty_background_ratio=5; do
        asl_exec "sysctl -w '$kv'" 2>/dev/null || true
    done

    # Ensure swapfile is enabled if present, or auto-create 2GB swap if RAM < 6GB and disk space > 10GB
    if ! asl_exec "test -f /data/swapfile" 2>/dev/null; then
        mem_kb=$(asl_exec "awk '/MemTotal/ {print \$2}' /proc/meminfo" 2>/dev/null || echo 8000000)
        if [ -n "$mem_kb" ] && [ "$mem_kb" -lt 6291456 ]; then
            free_data_mb=$(asl_exec "df -m /data | awk 'NR==2 {print \$4}'" 2>/dev/null || echo 0)
            if [ -n "$free_data_mb" ] && [ "$free_data_mb" -gt 10240 ]; then
                asl_exec "dd if=/dev/zero of=/data/swapfile bs=1M count=2048 2>/dev/null && chmod 600 /data/swapfile && mkswap /data/swapfile 2>/dev/null" 2>/dev/null || true
            fi
        fi
    fi
    if asl_exec "test -f /data/swapfile" 2>/dev/null; then
        asl_exec "swapon /data/swapfile" 2>/dev/null || true
    fi
fi

echo "[✓] Chroot mounted successfully."
