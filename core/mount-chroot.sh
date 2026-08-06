#!/bin/bash
# AndroidLinux-SuperKit: Safe Chroot Mount Script
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
        printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > $DEBIANPATH/etc/resolv.conf
    fi
" || {
    echo "[!] Chroot mount failed."
    exit 1
}

if ! su -c "grep -q -w '$DEBIANPATH/proc' /proc/mounts" 2>/dev/null; then
    echo "[!] Chroot mount verification failed."
    exit 1
fi

echo "[✓] Chroot mounted successfully."
