#!/bin/bash
# ASL: Native Debian GTK3 Control Center ("ASL Hub") Launcher & Installer
# Deploys the Python3 GTK3 Control Center app and desktop shortcuts into Debian rootfs.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_chroot_mounted() {
    if ! is_mounted; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

install_asl_hub_deb() {
    echo "[*] Deploying ASL Hub GTK3 Control Center into Linux rootfs..."
    ensure_chroot_mounted || return 1

    local src_app="$SCRIPT_DIR/desktop/asl-hub/asl-control-center.py"
    local tmp_desk="$HOME/.asl_hub_desk.tmp"
    local target_app="$DEBIANPATH/usr/local/bin/asl-control-center"

    if [ ! -f "$src_app" ]; then
        echo "Error: app source not found at $src_app"
        exit 1
    fi

    mkdir -p "$DEBIANPATH/usr/local/bin" 2>/dev/null || asl_exec "mkdir -p '$DEBIANPATH/usr/local/bin'"

    cp "$src_app" "$target_app" 2>/dev/null || asl_exec "cp '$src_app' '$target_app'"
    chmod 755 "$target_app" 2>/dev/null || asl_exec "chmod 755 '$target_app'"

    # Verify deployed app compiles
    if asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; python3 -m py_compile /usr/local/bin/asl-control-center" 2>/dev/null; then
        echo "[✓] Deployed app passed syntax check."
    else
        echo "[!] WARNING: deployed app failed py_compile check."
    fi

    ln -sf /usr/local/bin/asl-control-center "$DEBIANPATH/usr/local/bin/asl-gui" 2>/dev/null || asl_exec "ln -sf /usr/local/bin/asl-control-center '$DEBIANPATH/usr/local/bin/asl-gui'"
    ln -sf /usr/local/bin/asl-control-center "$DEBIANPATH/usr/local/bin/asl-hub" 2>/dev/null || asl_exec "ln -sf /usr/local/bin/asl-control-center '$DEBIANPATH/usr/local/bin/asl-hub'"

    # Install GTK3 dependencies inside Debian chroot
    echo "[*] Ensuring python3-gi & GTK3 packages are installed in Linux rootfs..."
    asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        if command -v apt-get >/dev/null 2>&1; then
            if ! python3 -c \"import gi; gi.require_version('Gtk', '3.0')\" 2>/dev/null; then
                apt-get update && apt-get install -y python3-gi gir1.2-gtk-3.0 python3
            fi
        fi
    " || true

    # Deploy Desktop Shortcut (.desktop)
    echo "[*] Creating Desktop launchers in /usr/share/applications & /root/Desktop..."
    cat << 'DESKEOF' > "$tmp_desk"
[Desktop Entry]
Name=ASL Hub
Comment=Android Subsystem for Linux Control Center
Exec=/usr/local/bin/asl-control-center
Icon=preferences-system
Terminal=false
Type=Application
Categories=System;Settings;GTK;
Keywords=ASL;Control;Center;Wine;GPU;
DESKEOF

    cp "$tmp_desk" "$DEBIANPATH/usr/share/applications/asl-hub.desktop" 2>/dev/null || asl_exec "cp '$tmp_desk' '$DEBIANPATH/usr/share/applications/asl-hub.desktop'"
    chmod 644 "$DEBIANPATH/usr/share/applications/asl-hub.desktop" 2>/dev/null || asl_exec "chmod 644 '$DEBIANPATH/usr/share/applications/asl-hub.desktop'"

    mkdir -p "$DEBIANPATH/root/Desktop" 2>/dev/null || asl_exec "mkdir -p '$DEBIANPATH/root/Desktop'"
    cp "$tmp_desk" "$DEBIANPATH/root/Desktop/asl-hub.desktop" 2>/dev/null || asl_exec "cp '$tmp_desk' '$DEBIANPATH/root/Desktop/asl-hub.desktop'"
    chmod +x "$DEBIANPATH/root/Desktop/asl-hub.desktop" 2>/dev/null || asl_exec "chmod +x '$DEBIANPATH/root/Desktop/asl-hub.desktop'"

    rm -f "$tmp_desk"

    echo "[✓] ASL Hub GTK3 Control Center deployed onto Linux desktop."
}

case "${1:-install}" in
    install|setup)
        install_asl_hub_deb
        ;;
    *)
        echo "Usage: asl-hub-installer.sh [install]"
        ;;
esac
