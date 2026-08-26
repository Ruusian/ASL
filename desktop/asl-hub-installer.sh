#!/bin/bash
# ASL: Native Debian GTK3 Control Center ("ASL Hub") Launcher & Installer
# Deploys the Python3 GTK3 Control Center app and desktop shortcuts into Debian rootfs.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

asl_require_default_debianpath

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

    # Deploy the real ASL CLI into the chroot so the Hub's buttons work.
    # Inside the chroot the CLI must operate on the current rootfs, so we set
    # ASL_CHROOT_SELF=1 (handled in core/common.sh) and provide an asl-cli
    # wrapper for chroot execution.
    echo "[*] Deploying ASL CLI into Linux rootfs..."
    local asl_cli_dir="$DEBIANPATH/usr/local/share/asl-cli"
    mkdir -p "$asl_cli_dir" 2>/dev/null || asl_exec "mkdir -p '$asl_cli_dir'"
    cp "$SCRIPT_DIR/bin/asl" "$asl_cli_dir/asl" 2>/dev/null || asl_exec "cp '$SCRIPT_DIR/bin/asl' '$asl_cli_dir/asl'"
    for subdir in core desktop tools; do
        if [ -d "$SCRIPT_DIR/$subdir" ]; then
            mkdir -p "$asl_cli_dir/$subdir" 2>/dev/null || asl_exec "mkdir -p '$asl_cli_dir/$subdir'"
            for f in "$SCRIPT_DIR/$subdir"/*; do
                if [ -f "$f" ]; then
                    cp "$f" "$asl_cli_dir/$subdir/" 2>/dev/null || asl_exec "cp '$f' '$asl_cli_dir/$subdir/'"
                fi
            done
        fi
    done
    chmod 755 "$asl_cli_dir/asl" 2>/dev/null || asl_exec "chmod 755 '$asl_cli_dir/asl'"

    local tmp_cli="$HOME/.asl_cli.tmp"
    cat << 'CLI_EOF' > "$tmp_cli"
#!/bin/bash
export ASL_CHROOT_SELF=1
export DEBIANPATH=/
export ASL_EXEC_MODE=direct
exec /bin/bash /usr/local/share/asl-cli/asl "$@"
CLI_EOF
    cp "$tmp_cli" "$DEBIANPATH/usr/local/bin/asl-cli" 2>/dev/null || asl_exec "cp '$tmp_cli' '$DEBIANPATH/usr/local/bin/asl-cli'"
    chmod 755 "$DEBIANPATH/usr/local/bin/asl-cli" 2>/dev/null || asl_exec "chmod 755 '$DEBIANPATH/usr/local/bin/asl-cli'"
    rm -f "$tmp_cli"

    # Verify deployed app compiles
    if asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; python3 -m py_compile /usr/local/bin/asl-control-center" 2>/dev/null; then
        echo "[✓] Deployed app passed syntax check."
    else
        echo "[!] WARNING: deployed app failed py_compile check."
    fi

    ln -sf /usr/local/bin/asl-control-center "$DEBIANPATH/usr/local/bin/asl-gui" 2>/dev/null || asl_exec "ln -sf /usr/local/bin/asl-control-center '$DEBIANPATH/usr/local/bin/asl-gui'"
    ln -sf /usr/local/bin/asl-control-center "$DEBIANPATH/usr/local/bin/asl-hub" 2>/dev/null || asl_exec "ln -sf /usr/local/bin/asl-control-center '$DEBIANPATH/usr/local/bin/asl-hub'"

    # Install GTK3 dependencies inside Debian chroot.
    # NOTE: keep this a single line with no quotes at all — multi-line or
    # quoted commands take the base64 path in asl_chroot_exec, which needs
    # Termux's base64 binary (absent on this device). Double quotes would
    # also be stripped by the su -c wrapper, breaking the command.
    echo "[*] Ensuring python3-gi & GTK3 packages are installed in Linux rootfs..."
    asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; dpkg -s python3-gi >/dev/null 2>&1 || (apt-get update && apt-get install -y python3-gi gir1.2-gtk-3.0 python3)" 2>/dev/null || true

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
Keywords=ASL;Control;Center;GPU;Performance;
DESKEOF

    cp "$tmp_desk" "$DEBIANPATH/usr/share/applications/asl-hub.desktop" 2>/dev/null || asl_exec "cp '$tmp_desk' '$DEBIANPATH/usr/share/applications/asl-hub.desktop'"
    chmod 644 "$DEBIANPATH/usr/share/applications/asl-hub.desktop" 2>/dev/null || asl_exec "chmod 644 '$DEBIANPATH/usr/share/applications/asl-hub.desktop'"

    mkdir -p "$DEBIANPATH/root/Desktop" 2>/dev/null || asl_exec "mkdir -p '$DEBIANPATH/root/Desktop'"
    cp "$tmp_desk" "$DEBIANPATH/root/Desktop/asl-hub.desktop" 2>/dev/null || asl_exec "cp '$tmp_desk' '$DEBIANPATH/root/Desktop/asl-hub.desktop'"
    chmod +x "$DEBIANPATH/root/Desktop/asl-hub.desktop" 2>/dev/null || asl_exec "chmod +x '$DEBIANPATH/root/Desktop/asl-hub.desktop'"

    rm -f "$tmp_desk"

    echo "[✓] ASL Hub GTK3 Control Center deployed onto Linux desktop."
}

uninstall_asl_hub_deb() {
    echo "[*] Removing ASL Hub GTK3 Control Center from Linux rootfs..."
    ensure_chroot_mounted || return 1

    local target_app="$DEBIANPATH/usr/local/bin/asl-control-center"
    local link_names=("asl-gui" "asl-hub")
    local desktop_paths=(
        "$DEBIANPATH/usr/share/applications/asl-hub.desktop"
        "$DEBIANPATH/root/Desktop/asl-hub.desktop"
    )

    # Remove main app binary
    if [ -f "$target_app" ]; then
        rm -f "$target_app" 2>/dev/null || asl_exec "rm -f '$target_app'" && echo "[✓] Removed $target_app" || echo "[!] Failed to remove $target_app"
    else
        echo "[ ] App binary not found at $target_app (already removed?)"
    fi

    # Remove symlinks
    for link in "${link_names[@]}"; do
        local link_path="$DEBIANPATH/usr/local/bin/$link"
        if [ -e "$link_path" ] || [ -L "$link_path" ]; then
            rm -f "$link_path" 2>/dev/null || asl_exec "rm -f '$link_path'" && echo "[✓] Removed symlink $link_path" || echo "[!] Failed to remove $link_path"
        fi
    done

    # Remove desktop files
    for desk in "${desktop_paths[@]}"; do
        if [ -f "$desk" ]; then
            rm -f "$desk" 2>/dev/null || asl_exec "rm -f '$desk'" && echo "[✓] Removed $desk" || echo "[!] Failed to remove $desk"
        fi
    done

    # Remove the deployed ASL CLI
    rm -f "$DEBIANPATH/usr/local/bin/asl-cli" 2>/dev/null || asl_exec "rm -f '$DEBIANPATH/usr/local/bin/asl-cli'" || true
    rm -rf "$DEBIANPATH/usr/local/share/asl-cli" 2>/dev/null || asl_exec "rm -rf '$DEBIANPATH/usr/local/share/asl-cli'" || true
    echo "[✓] Removed deployed ASL CLI."

    # Remove config state (Termux-side, no root needed)
    local conf_dir="${HOME}/.config"
    if [ -d "$conf_dir" ]; then
        local conf_file="$conf_dir/asl-hub.conf"
        if [ -f "$conf_file" ]; then
            rm -f "$conf_file" && echo "[✓] Removed config $conf_file" || echo "[!] Failed to remove $conf_file"
        fi
    fi

    echo "[✓] ASL Hub GTK3 Control Center uninstalled."
}

case "${1:-install}" in
    install|setup)
        install_asl_hub_deb
        ;;
    uninstall|remove)
        uninstall_asl_hub_deb
        ;;
    *)
        echo "Usage: asl-hub-installer.sh [install|uninstall]"
        ;;
esac
