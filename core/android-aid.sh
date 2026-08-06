#!/bin/bash
# AndroidLinux-SuperKit: Android AID (Android ID) Group Mapper
# Maps Android system GIDs inside Debian chroot for seamless hardware & media access.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

setup_android_aids() {
    echo "[*] Setting up Android AID GID mappings inside Debian chroot..."
    if ! grep -q -w "$DEBIANPATH/proc" /proc/mounts 2>/dev/null; then
        bash "$SCRIPT_DIR/core/mount-chroot.sh" >/dev/null 2>&1 || true
    fi
    su -c "chroot '$DEBIANPATH' /bin/bash -c '
        groupadd -g 1003 aid_graphics || true
        groupadd -g 1004 aid_input || true
        groupadd -g 1005 aid_audio || true
        groupadd -g 1006 aid_camera || true
        groupadd -g 1010 aid_wifi || true
        groupadd -g 1015 aid_sdcard_rw || true
        groupadd -g 1023 aid_media_rw || true
        groupadd -g 1028 aid_sdcard_r || true
        groupadd -g 1035 aid_sdcard_all || true
        groupadd -g 1072 aid_gpu_service || true
        groupadd -g 2000 aid_shell || true
        groupadd -g 3003 aid_inet || true

        for g in aid_graphics aid_input aid_audio aid_sdcard_rw aid_media_rw aid_sdcard_r aid_sdcard_all aid_gpu_service aid_shell aid_inet; do
            usermod -aG \"\$g\" root || true
        done
    '" >/dev/null 2>&1
    echo "[✓] Android AID GID mapping completed."
}

case "${1:-setup}" in
    setup|sync)
        setup_android_aids
        ;;
    *)
        echo "Usage: superkit aid [setup]"
        ;;
esac
