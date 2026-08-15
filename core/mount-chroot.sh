#!/bin/bash
# Android Subsystem for Linux (ASL): Safe Chroot Mount Script
# ZERO host system/vendor/apex mounts to protect Android OS stability

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] || [ ! -d "$DEBIANPATH" ]; then
    echo "Error: Debian chroot is not available at /data/local/tmp/chrootDebian"
    exit 1
fi

TERMUX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"

echo "[*] Mounting Linux chroot environment at $DEBIANPATH..."

su -c "
    set -e

    if ! grep -q -w \"$DEBIANPATH\" /proc/mounts 2>/dev/null; then
        mount --bind \"$DEBIANPATH\" \"$DEBIANPATH\"
    fi
    mount --make-rprivate \"$DEBIANPATH\" 2>/dev/null || true

    domount_bind() {
        if ! grep -q -w \"\$2\" /proc/mounts 2>/dev/null; then
            mkdir -p \"\$2\"
            mount --bind \"\$1\" \"\$2\"
            mount --make-rslave \"\$2\" 2>/dev/null || true
        fi
    }

    domount_fs() {
        if ! grep -q -w \"\$2\" /proc/mounts 2>/dev/null; then
            mkdir -p \"\$2\"
            mount -t \"\$1\" \"\$1\" \"\$2\"
        fi
    }

    domount_tmpfs() {
        if ! grep -q -w \"\$1\" /proc/mounts 2>/dev/null; then
            mkdir -p \"\$1\"
            mount -t tmpfs -o \"\$2\" tmpfs \"\$1\"
        fi
    }

    domount_bind /dev $DEBIANPATH/dev
    # Android's graphics group (GID 1003) owns /dev/input nodes; grant that
    # group rw access for the chroot instead of making devices world-writable
    # (0666 lets any host or chroot process inject input events).
    for dev in /dev/input/event* /dev/input/js* /dev/input/mouse* /dev/input/mice; do
        [ -e "\$dev" ] || continue
        chgrp 1003 "\$dev" 2>/dev/null || true
        chmod 0660 "\$dev" 2>/dev/null || true
    done
    domount_fs proc $DEBIANPATH/proc
    domount_fs sysfs $DEBIANPATH/sys
    domount_bind /dev/pts $DEBIANPATH/dev/pts

    if [ -d /proc/sys/fs/binfmt_misc ] && grep -q -w "/proc/sys/fs/binfmt_misc" /proc/mounts 2>/dev/null; then
        domount_bind /proc/sys/fs/binfmt_misc $DEBIANPATH/proc/sys/fs/binfmt_misc
    fi

    if [ -d /sdcard ]; then
        domount_bind /sdcard $DEBIANPATH/sdcard
    fi

    mkdir -p \"$TERMUX_TMP\"
    chmod 1777 \"$TERMUX_TMP\"
    if ! grep -q -w \"$DEBIANPATH/tmp\" /proc/mounts 2>/dev/null; then
        mount --bind \"$TERMUX_TMP\" \"$DEBIANPATH/tmp\"
        mount --make-rslave \"$DEBIANPATH/tmp\" 2>/dev/null || true
    fi
    mkdir -p \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
    if ! grep -q -w \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\" /proc/mounts 2>/dev/null; then
        mount --bind \"$TERMUX_TMP\" \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
        mount --make-rslave \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\" 2>/dev/null || true
    fi
    domount_tmpfs $DEBIANPATH/run rw,nosuid,nodev,mode=0755,noatime
    domount_tmpfs $DEBIANPATH/dev/shm rw,nosuid,nodev,noatime

    if [ -d $DEBIANPATH/var ] && [ ! -L $DEBIANPATH/var/lock ]; then
        domount_tmpfs $DEBIANPATH/var/lock rw,nosuid,nodev,mode=1777,noatime
    fi

    if [ ! -s $DEBIANPATH/etc/resolv.conf ]; then
        mkdir -p $DEBIANPATH/etc
        dns1=\$(getprop net.dns1 2>/dev/null)
        dns2=\$(getprop net.dns2 2>/dev/null)
        if [ -n \"\$dns1\" ]; then
            printf 'nameserver %s\n' \"\$dns1\" > $DEBIANPATH/etc/resolv.conf
            [ -n \"\$dns2\" ] && printf 'nameserver %s\n' \"\$dns2\" >> $DEBIANPATH/etc/resolv.conf
        elif [ -f /data/data/com.termux/files/usr/etc/resolv.conf ]; then
            cp /data/data/com.termux/files/usr/etc/resolv.conf $DEBIANPATH/etc/resolv.conf 2>/dev/null || true
        fi
        if [ ! -s $DEBIANPATH/etc/resolv.conf ]; then
            printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > $DEBIANPATH/etc/resolv.conf
        fi
    fi

" || {
    echo "[!] Chroot mount failed."
    exit 1
}

if ! su -c "grep -q -w '$DEBIANPATH/proc' /proc/mounts" 2>/dev/null; then
    echo "[!] Chroot mount verification failed."
    exit 1
fi

# Sysctl tuning is host-kernel; always apply if root.
# Save previous values first so `asl stop` can restore them.
SYSCTL_BACKUP="/data/local/tmp/asl_sysctl_orig"
# A repeated `asl start` must retain the values from before ASL's first tune.
# Create the backup once; stop-chroot removes it after restoration.
if ! su -c "test -e '$SYSCTL_BACKUP'" 2>/dev/null; then
    for kv in vm.swappiness=60 vm.vfs_cache_pressure=50 vm.dirty_ratio=15 vm.dirty_background_ratio=5; do
        key="${kv%%=*}"
        cur="$(su -c "sysctl -n '$key'" 2>/dev/null | tr -d '[:space:]')"
        if [ -n "$cur" ] && [ "$cur" != "${kv#*=}" ]; then
            su -c "printf '%s\\n' '$key=$cur' >> '$SYSCTL_BACKUP'" 2>/dev/null || true
        fi
    done
fi
for kv in vm.swappiness=60 vm.vfs_cache_pressure=50 vm.dirty_ratio=15 vm.dirty_background_ratio=5; do
    su -c "sysctl -w '$kv'" 2>/dev/null || true
done

echo "[✓] Chroot mounted successfully."
