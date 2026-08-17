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

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

# Restore host sysctl tuning that mount-chroot.sh applied (even if unmounted already)
SYSCTL_BACKUP="/data/local/tmp/asl_sysctl_orig"
if [ "${ASL_EXEC_MODE:-root}" = "root" ]; then
    if asl_exec "test -s '$SYSCTL_BACKUP'" 2>/dev/null; then
        echo "[*] Restoring host sysctl tuning..."
        asl_exec "
            while IFS='=' read -r key val; do
                [ -n \"\$key\" ] && [ -n \"\$val\" ] && sysctl -w \"\$key=\$val\" 2>/dev/null || true
            done < '$SYSCTL_BACKUP'
            rm -f '$SYSCTL_BACKUP'
        " || true
    fi
fi

if ! is_mounted "$DEBIANPATH"; then
    echo "[✓] Debian chroot is already unmounted."
    exit 0
fi

echo "[*] Stopping Linux chroot environment at $DEBIANPATH..."

asl_exec "
    mount --make-rprivate \"$DEBIANPATH\" 2>/dev/null || true

    # wineserver -k can block indefinitely under Box64. Signal only processes
    # whose root is this chroot; /proc itself is shared with the Android host.
    chroot_pkill() {
        sig="\$1"
        for proc in /proc/[0-9]*; do
            [ -d "\$proc" ] || continue
            root=\$(readlink "\$proc/root" 2>/dev/null || true)
            [ "\$root" = "$DEBIANPATH" ] || continue
            comm=\$(cat "\$proc/comm" 2>/dev/null || true)
            case "\$comm" in
                wine|wine64|wine-preloader|wine64-preloader|wineserver|wineserver-wrapper|box64)
                    kill -"\$sig" "\${proc#/proc/}" 2>/dev/null || true
                    ;;
            esac
        done
    }
    chroot_pkill TERM
    sleep 1
    chroot_pkill KILL


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

    MOUNTS=\"\$(
        (
            echo \"$DEBIANPATH/proc/sys/fs/binfmt_misc\"
            echo \"$DEBIANPATH/dev/input\"
            echo \"$DEBIANPATH/dev/pts\"
            echo \"$DEBIANPATH/dev/shm\"
            echo \"$DEBIANPATH/data/data/com.termux/files/usr/tmp\"
            echo \"$DEBIANPATH/var/lock\"
            echo \"$DEBIANPATH/sdcard\"
            echo \"$DEBIANPATH/tmp\"
            echo \"$DEBIANPATH/run\"
            echo \"$DEBIANPATH/sys\"
            echo \"$DEBIANPATH/proc\"
            echo \"$DEBIANPATH/dev\"
            echo \"$DEBIANPATH\"
            awk '{print \$2}' /proc/mounts 2>/dev/null | grep -E \"^$DEBIANPATH(/|\$)\" || true
        ) | awk '{ print length, \$0 }' | sort -rn | cut -d' ' -f2- | uniq
    )\"

    failed=0
    failed_mounts=""
    for mp in \$MOUNTS; do
        if grep -q -F " \$mp " /proc/mounts 2>/dev/null; then
            if ! umount \"\$mp\" 2>/dev/null; then
                if ! umount -l -f \"\$mp\" 2>/dev/null; then
                    echo \"[!] Could not unmount: \$mp\" >&2
                    failed_mounts=\"\$failed_mounts\\n  - \$mp\"
                    failed=1
                fi
            fi
        fi
    done
    exit \$failed
" || {
    echo "[!] Chroot stop was incomplete. Troubleshooting:"
    echo "    1. Check for running processes in chroot: lsof $DEBIANPATH"
    echo "    2. Kill remaining processes: killall -9 -u root 2>/dev/null"
    echo "    3. Force unmount: umount -l $DEBIANPATH"
    echo "    4. View mounts: grep $DEBIANPATH /proc/mounts"
    exit 1
}

echo "[✓] Chroot stopped and unmounted cleanly."
