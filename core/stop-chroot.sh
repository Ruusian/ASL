#!/bin/bash
# Android Subsystem for Linux (ASL): Safe Chroot Stop Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "${ASL_EXEC_MODE:-root}" = "proot" ]; then
    pkill -TERM -f "proot.*(asl-debian|$DEBIANPATH)" 2>/dev/null || true
    sleep 1
    pkill -KILL -f "proot.*(asl-debian|$DEBIANPATH)" 2>/dev/null || true
    echo "[✓] PRoot session processes terminated cleanly."
    exit 0
fi

asl_require_default_debianpath

# Remove legacy sysctl backup file if present
SYSCTL_BACKUP="/data/local/tmp/asl_sysctl_orig"
if [ "${ASL_EXEC_MODE:-root}" = "root" ]; then
    asl_exec "rm -f '$SYSCTL_BACKUP' '${SYSCTL_BACKUP}.tmp'" 2>/dev/null || true
fi

if ! is_mounted "$DEBIANPATH"; then
    echo "[✓] Debian chroot is already unmounted."
    exit 0
fi

echo "[*] Stopping Linux chroot environment at $DEBIANPATH..."

STOP_SCRIPT=$(cat << STOP_EOF
mount --make-rprivate "$DEBIANPATH" 2>/dev/null || true

# Restore original /dev/input ownership and modes changed at mount time.
INPUT_PERMS_BACKUP="$DEBIANPATH/.asl_input_perms"
if [ -f "\$INPUT_PERMS_BACKUP" ]; then
    while read -r dev owner mode; do
        [ -n "\$dev" ] || continue
        [ -e "\$dev" ] || continue
        [ -n "\$owner" ] && chown "\$owner" "\$dev" 2>/dev/null || true
        [ -n "\$mode" ] && chmod "\$mode" "\$dev" 2>/dev/null || true
    done < "\$INPUT_PERMS_BACKUP"
    rm -f "\$INPUT_PERMS_BACKUP" 2>/dev/null || true
fi

chroot_pkill() {
    sig="\$1"
    for pid in \$(pgrep -f 'wine|wine64|wineserver|box64' 2>/dev/null || true); do
        if [ "\$(readlink /proc/\$pid/root 2>/dev/null)" = "$DEBIANPATH" ]; then
            kill -\$sig \$pid 2>/dev/null || true
        fi
    done
}
chroot_pkill TERM
sleep 1
chroot_pkill KILL

pids=""
for pid_dir in /proc/[0-9]*; do
    pid=\$(basename "\$pid_dir")
    [ "\$pid" = "\$\$" ] && continue
    if [ "\$(readlink /proc/\$pid/root 2>/dev/null)" = "$DEBIANPATH" ]; then
        pids="\$pids \$pid"
    fi
done
if [ -n "\$pids" ]; then
    kill -TERM \$pids 2>/dev/null || true
    sleep 1
    for pid in \$pids; do
        if kill -0 "\$pid" 2>/dev/null; then
            kill -KILL "\$pid" 2>/dev/null || true
        fi
    done
fi

MOUNTS="\$(
    (
        echo "$DEBIANPATH/proc/sys/fs/binfmt_misc"
        echo "$DEBIANPATH/dev/input"
        echo "$DEBIANPATH/dev/pts"
        echo "$DEBIANPATH/dev/shm"
        echo "$DEBIANPATH/data/data/com.termux/files/usr/tmp"
        echo "$DEBIANPATH/var/lock"
        echo "$DEBIANPATH/sdcard"
        echo "$DEBIANPATH/tmp"
        echo "$DEBIANPATH/run"
        echo "$DEBIANPATH/sys"
        echo "$DEBIANPATH/proc"
        echo "$DEBIANPATH/dev"
        echo "$DEBIANPATH"
        awk '{print \$2}' /proc/mounts 2>/dev/null | grep -E "^$DEBIANPATH(/|\$)" || true
    ) | awk '{ print length, \$0 }' | sort -rn | cut -d' ' -f2- | uniq
)"

failed=0
for mp in \$MOUNTS; do
    if grep -q -F " \$mp " /proc/mounts 2>/dev/null; then
        if ! umount "\$mp" 2>/dev/null; then
            if ! umount -l -f "\$mp" 2>/dev/null; then
                echo "[!] Could not unmount: \$mp" >&2
                failed=1
            fi
        fi
    fi
done
exit \$failed
STOP_EOF
)

asl_exec "$STOP_SCRIPT" || {
    echo "[!] Chroot stop was incomplete. Troubleshooting:"
    echo "    1. Check for running processes in chroot: lsof $DEBIANPATH"
    echo "    2. Kill remaining processes: killall -9 -u root 2>/dev/null"
    echo "    3. Force unmount: umount -l $DEBIANPATH"
    echo "    4. View mounts: grep $DEBIANPATH /proc/mounts"
    exit 1
}

echo "[✓] Chroot stopped and unmounted cleanly."
