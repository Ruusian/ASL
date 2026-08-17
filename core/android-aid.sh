#!/bin/bash
# ASL: Android AID (Android ID) Group Mapper
# Maps Android system GIDs inside Debian chroot for seamless hardware & media access.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

setup_android_aids() {
    echo "[*] Setting up Android AID GID mappings inside Debian chroot..."
    if ! is_mounted; then
        if ! bash "$SCRIPT_DIR/core/mount-chroot.sh"; then
            echo "[!] Unable to mount the Debian chroot for Android AID setup."
            return 1
        fi
    fi
    if ! asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        set -e
        ensure_group() {
            local name=\"\$1\" gid=\"\$2\" existing_name existing_gid gid_name
            existing_name=\$(getent group \"\$name\" || true)
            existing_gid=\$(getent group \"\$gid\" || true)
            if [ -n \"\$existing_name\" ]; then
                [ \"\${existing_name#*:*:}\" != \"\$existing_name\" ] || exit 1
                [ \"\$(printf %s \"\$existing_name\" | cut -d: -f3)\" = \"\$gid\" ] || { echo \"[!] Group \$name has an unexpected GID.\" >&2; exit 1; }
            elif [ -n \"\$existing_gid\" ]; then
                gid_name=\$(printf %s \"\$existing_gid\" | cut -d: -f1)
                echo \"[!] GID \$gid is already assigned to \$gid_name, not \$name.\" >&2
                exit 1
            else
                groupadd -g \"\$gid\" \"\$name\"
            fi
        }

        ensure_group aid_graphics 1003
        ensure_group aid_input 1004
        ensure_group aid_audio 1005
        ensure_group aid_camera 1006
        ensure_group aid_wifi 1010
        ensure_group aid_sdcard_rw 1015
        ensure_group aid_media_rw 1023
        ensure_group aid_sdcard_r 1028
        ensure_group aid_sdcard_all 1035
        ensure_group aid_gpu_service 1072
        ensure_group aid_shell 2000
        ensure_group aid_inet 3003
        ensure_group aid_everybody 9997

        for g in aid_graphics aid_input aid_audio aid_camera aid_wifi aid_sdcard_rw aid_media_rw aid_sdcard_r aid_sdcard_all aid_gpu_service aid_shell aid_inet aid_everybody; do
            id -nG root | tr \" \" \"\\n\" | grep -qx \"\$g\" || usermod -aG \"\$g\" root
        done

        # Create symlinks from root user folders to shared Android storage
        if [ -d /sdcard ]; then
            [ -d /sdcard/Download ] && [ ! -e /root/Downloads ] && ln -sf /sdcard/Download /root/Downloads || true
            [ -d /sdcard/Documents ] && [ ! -e /root/Documents ] && ln -sf /sdcard/Documents /root/Documents || true
            [ -d /sdcard/Pictures ] && [ ! -e /root/Pictures ] && ln -sf /sdcard/Pictures /root/Pictures || true
            [ -d /sdcard/Music ] && [ ! -e /root/Music ] && ln -sf /sdcard/Music /root/Music || true
        fi
    "; then
        echo "[!] Android AID GID mapping failed."
        return 1
    fi
    echo "[✓] Android AID GID mapping completed."
}

case "${1:-status}" in
    setup|sync)
        setup_android_aids
        ;;
    status)
        if ! is_mounted; then
            echo "Android AID GID Mapping: Chroot unmounted"
        else
            aid_count=$(asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; getent group" 2>/dev/null | grep -c '^aid_' || echo 0)
            aid_count=$(echo "$aid_count" | tr -d '[:space:]')
            echo "Android AID GID Mapping: ACTIVE ($aid_count AID groups mapped)"
        fi
        ;;
    *)
        echo "Usage: asl aid [setup|status]"
        ;;
esac

