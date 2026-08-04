#!/bin/bash
# AndroidLinux-SuperKit: Safe Chroot Mount Script
# ZERO host system/vendor/apex mounts to protect Android OS stability

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] || [ ! -d "$DEBIANPATH" ]; then
    echo "Error: Debian chroot is not available at /data/local/tmp/chrootDebian"
    exit 1
fi

echo "[*] Mounting Linux chroot environment at $DEBIANPATH..."

su -c "
    set -e

    if ! grep -q -w \"$DEBIANPATH\" /proc/mounts 2>/dev/null; then
        mount --bind \"$DEBIANPATH\" \"$DEBIANPATH\"
    fi
    mount --make-rprivate \"$DEBIANPATH\"

    domount_bind() {
        if ! grep -q -w \"\$2\" /proc/mounts 2>/dev/null; then
            mkdir -p \"\$2\"
            mount --bind \"\$1\" \"\$2\"
            mount --make-rslave \"\$2\"
        fi
    }

    domount_fs() {
        if ! grep -q -w \"\$2\" /proc/mounts 2>/dev/null; then
            mkdir -p \"\$2\"
            mount -t \"\$1\" \"\$1\" \"\$2\"
        fi
    }

    domount_tmpfs() {
        if ! grep -q -w \"\$2\" /proc/mounts 2>/dev/null; then
            mkdir -p \"\$2\"
            mount -t tmpfs -o \"\$3\" tmpfs \"\$2\"
        fi
    }

    domount_bind /dev $DEBIANPATH/dev
    domount_fs proc $DEBIANPATH/proc
    domount_fs sysfs $DEBIANPATH/sys
    domount_bind /dev/pts $DEBIANPATH/dev/pts

    if [ -d /sdcard ]; then
        domount_bind /sdcard $DEBIANPATH/sdcard
    fi

    domount_tmpfs $DEBIANPATH/tmp rw,nosuid,nodev,mode=1777,noatime
    domount_tmpfs $DEBIANPATH/run rw,nosuid,nodev,mode=0755,noatime
    domount_tmpfs $DEBIANPATH/dev/shm rw,nosuid,nodev,noatime

    if [ -d $DEBIANPATH/var ] && [ ! -L $DEBIANPATH/var/lock ]; then
        domount_tmpfs $DEBIANPATH/var/lock rw,nosuid,nodev,mode=1777,noatime
    fi
" || {
    echo "[!] Chroot mount failed."
    exit 1
}

if ! su -c "mountpoint -q '$DEBIANPATH/proc'" 2>/dev/null; then
    echo "[!] Chroot mount verification failed."
    exit 1
fi

echo "[✓] Chroot mounted successfully."
