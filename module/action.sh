#!/system/bin/sh
# AndroidLinux-SuperKit: Magisk / KernelSU / APatch Action Script
# Allows starting/stopping ASL container directly from Magisk/KSU Manager UI.

MODDIR=${0%/*}
SUPERKIT_BIN="/data/data/com.termux/files/home/AndroidLinux-SuperKit/bin/superkit"
DEBIANPATH="/data/local/tmp/chrootDebian"

is_chroot_active() {
    grep -q -w "$DEBIANPATH/proc" /proc/mounts 2>/dev/null
}

update_prop_status() {
    local status="$1"
    if [ -f "$MODDIR/module.prop" ]; then
        sed -i "s|^description=.*|description=\[ $status \] Root-Accelerated Debian Chroot + Box64 Gaming Container|" "$MODDIR/module.prop"
    fi
}

if is_chroot_active; then
    echo "- Stopping ASL Chroot..."
    if [ -x "$SUPERKIT_BIN" ]; then
        /system/bin/sh -c "$SUPERKIT_BIN stop"
    else
        umount -l "$DEBIANPATH/proc" 2>/dev/null
        umount -l "$DEBIANPATH/sys" 2>/dev/null
        umount -l "$DEBIANPATH/dev/pts" 2>/dev/null
        umount -l "$DEBIANPATH/dev" 2>/dev/null
        umount -l "$DEBIANPATH/sdcard" 2>/dev/null
    fi
    update_prop_status "stopped🙁"
    echo "- ASL Chroot stopped successfully."
else
    echo "- Starting ASL Chroot..."
    if [ -x "$SUPERKIT_BIN" ]; then
        /system/bin/sh -c "$SUPERKIT_BIN start"
        update_prop_status "running😉"
        echo "- ASL Chroot started successfully."
    else
        echo "[!] SuperKit CLI binary not found at $SUPERKIT_BIN"
        update_prop_status "error⚠️"
    fi
fi
