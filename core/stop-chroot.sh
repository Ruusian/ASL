#!/bin/bash
# Android Subsystem for Linux (ASL): Safe Chroot Stop Script

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

# Restore host sysctl tuning that mount-chroot.sh applied (even if unmounted already)
SYSCTL_BACKUP="/data/local/tmp/asl_sysctl_orig"
if su -c "test -s '$SYSCTL_BACKUP'" 2>/dev/null; then
    echo "[*] Restoring host sysctl tuning..."
    su -c "
        while IFS='=' read -r key val; do
            [ -n \"\$key\" ] && [ -n \"\$val\" ] && sysctl -w \"\$key=\$val\" 2>/dev/null || true
        done < '$SYSCTL_BACKUP'
        rm -f '$SYSCTL_BACKUP'
    " || true
fi

if ! su -c "grep -q -w '$DEBIANPATH/proc' /proc/mounts" 2>/dev/null; then
    echo "[*] Debian chroot is already unmounted."
    exit 0
fi

echo "[*] Stopping Linux chroot environment..."

su -c "
    mount --make-rprivate \"$DEBIANPATH\" 2>/dev/null || true

    chroot \"$DEBIANPATH\" /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; wineserver -k 2>/dev/null || true; pkill -9 -x \"wine|wine64|wineserver|box64\" 2>/dev/null || true' 2>/dev/null || true

    pids=\$(lsof -t \"$DEBIANPATH\" 2>/dev/null || fuser \"$DEBIANPATH\" 2>/dev/null || (for p in /proc/[0-9]*; do target=\$(readlink -f \"\$p/cwd\" 2>/dev/null || readlink -f \"\$p/root\" 2>/dev/null || true); [[ \"\$target\" == \"$DEBIANPATH\"* ]] && echo \"\${p##*/}\"; done) || true)
    if [ -n \"\$pids\" ]; then
        kill -TERM \$pids 2>/dev/null || true
        sleep 1
        for pid in \$pids; do
            if kill -0 \"\$pid\" 2>/dev/null; then
                kill -KILL \"\$pid\" 2>/dev/null || true
            fi
        done
    fi

    MOUNTS=\"
        $DEBIANPATH/sdcard
        $DEBIANPATH/var/lock
        $DEBIANPATH/dev/shm
        $DEBIANPATH/dev/pts
        $DEBIANPATH/dev
        $DEBIANPATH/proc/sys/fs/binfmt_misc
        $DEBIANPATH/proc
        $DEBIANPATH/sys
        $DEBIANPATH/run
        $DEBIANPATH/data/data/com.termux/files/usr/tmp
        $DEBIANPATH/tmp
        $DEBIANPATH
    \"

    failed=0
    for mp in \$MOUNTS; do
        if grep -q -w \"\$mp\" /proc/mounts 2>/dev/null; then
            if ! umount \"\$mp\" 2>/dev/null; then
                if ! umount -l -f \"\$mp\" 2>/dev/null; then
                    echo \"[!] Could not unmount: \$mp\" >&2
                    failed=1
                fi
            fi
        fi
    done
    exit \$failed
" || {
    echo "[!] Chroot stop was incomplete; check active processes and mounts."
    exit 1
}

echo "[✓] Chroot stopped and unmounted cleanly."
