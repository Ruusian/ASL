#!/system/bin/sh
# ASL: Magisk / KernelSU / APatch Action Script
# Allows starting/stopping ASL container directly from Magisk/KSU Manager UI.

MODDIR=${0%/*}
ASL_BASH="/data/data/com.termux/files/usr/bin/bash"
ASL_BIN="/data/data/com.termux/files/home/ASL/bin/asl"
DEBIANPATH="/data/local/tmp/chrootDebian"

export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/sbin:/system/bin:/system/xbin:$PATH"

is_chroot_active() {
    grep -q -w "$DEBIANPATH/proc" /proc/mounts 2>/dev/null
}

update_prop_status() {
    local status="$1"
    if [ -f "$MODDIR/module.prop" ]; then
        sed -i "s|^description=.*|description=\[ $status \] Root-Accelerated Debian Chroot + Box64 Gaming Container|" "$MODDIR/module.prop"
    fi
}

run_asl() {
    if [ -x "$ASL_BASH" ] && [ -x "$ASL_BIN" ]; then
        "$ASL_BASH" "$ASL_BIN" "$@"
    else
        return 127
    fi
}

umount_chroot() {
    pkill -9 -f asl-start-xfce 2>/dev/null
    chroot "$DEBIANPATH" /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; pkill -9 -f "xfwm4|xfdesktop|xfce4-panel|xfsettingsd|dbus-run-session|dbus-daemon|wine|wine64|wineserver|box64" 2>/dev/null' 2>/dev/null
    for mp in \
        "$DEBIANPATH/sdcard" \
        "$DEBIANPATH/var/lock" \
        "$DEBIANPATH/dev/shm" \
        "$DEBIANPATH/dev/pts" \
        "$DEBIANPATH/dev" \
        "$DEBIANPATH/proc/sys/fs/binfmt_misc" \
        "$DEBIANPATH/proc" \
        "$DEBIANPATH/sys" \
        "$DEBIANPATH/run" \
        "$DEBIANPATH/data/data/com.termux/files/usr/tmp" \
        "$DEBIANPATH/tmp" \
        "$DEBIANPATH"; do
        umount -l "$mp" 2>/dev/null
    done
}

if is_chroot_active; then
    echo "- Stopping ASL Chroot..."
    if run_asl stop; then
        update_prop_status "stopped🙁"
        echo "- ASL Chroot stopped successfully."
    else
        echo "[!] ASL CLI unavailable; falling back to direct unmount..."
        umount_chroot
        update_prop_status "stopped🙁"
        echo "- ASL Chroot stopped (manual unmount)."
    fi
else
    echo "- Starting ASL Chroot..."
    if run_asl start; then
        update_prop_status "running😉"
        echo "- ASL Chroot started successfully."
    else
        echo "[!] ASL CLI binary not found at $ASL_BIN"
        update_prop_status "error⚠️"
    fi
fi
