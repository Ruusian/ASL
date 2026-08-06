#!/bin/bash
# AndroidLinux-SuperKit: Safe Chroot Stop Script

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

if ! su -c "grep -q -w '$DEBIANPATH/proc' /proc/mounts" 2>/dev/null; then
    echo "[*] Debian chroot is already unmounted."
    exit 0
fi

echo "[*] Stopping Linux chroot environment..."

su -c "
    mount --make-rprivate \"$DEBIANPATH\" 2>/dev/null || true

    pids=\$(lsof -t \"$DEBIANPATH\" 2>/dev/null || fuser \"$DEBIANPATH\" 2>/dev/null || grep -l \"$DEBIANPATH\" /proc/[0-9]*/cwd 2>/dev/null | cut -d/ -f3 || true)
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
