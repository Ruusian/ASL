#!/bin/bash
# ASL: Native Debian GTK3 Control Center ("ASL Hub") Launcher & Installer
# Deploys the Python3 GTK3 Control Center app and desktop shortcuts into Debian rootfs.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-}" != "proot" ]; then
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

    local tmp_app="$HOME/.asl_hub_app.tmp"
    local tmp_desk="$HOME/.asl_hub_desk.tmp"
    local target_app="$DEBIANPATH/usr/local/bin/asl-control-center"

    mkdir -p "$DEBIANPATH/usr/local/bin" 2>/dev/null || asl_exec "mkdir -p '$DEBIANPATH/usr/local/bin'"

    cat << 'PYEOF' > "$tmp_app"
#!/usr/bin/env python3
import os
import sys
import shutil
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, Pango

class ASLHubWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="ASL Hub - Android Subsystem for Linux")
        self.set_default_size(800, 560)
        self.set_border_width(12)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(main_box)

        # Header
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title("ASL Hub Control Center")
        header.set_subtitle("Debian 13 Trixie ARM64 System Dashboard")
        self.set_titlebar(header)

        # Stack & Switcher for tabs
        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        stack.set_transition_duration(200)

        switcher = Gtk.StackSwitcher()
        switcher.set_stack(stack)
        main_box.pack_start(switcher, False, False, 0)
        main_box.pack_start(stack, True, True, 0)

        # 1. System & GPU Tab
        stack.add_titled(self.create_system_tab(), "system", "System & GPU")

        # 2. Gaming & Wine Tab
        stack.add_titled(self.create_gaming_tab(), "gaming", "Gaming & Wine")

        # 3. Gamepad Tab
        stack.add_titled(self.create_gamepad_tab(), "gamepad", "Gamepad")

        # 4. Dev Suite Tab
        stack.add_titled(self.create_dev_tab(), "dev", "Dev Suite")

        # 5. Security Suite Tab
        stack.add_titled(self.create_sec_tab(), "sec", "Security Audit")

        # 6. Maintenance Tab
        stack.add_titled(self.create_maint_tab(), "maint", "Maintenance & Repair")

        # Log Output Box
        log_frame = Gtk.Frame(label="Command Execution Log")
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_min_content_height(120)
        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_monospace(True)
        log_scroll.add(self.log_view)
        log_frame.add(log_scroll)
        main_box.pack_start(log_frame, False, False, 0)

        self.log("ASL Hub GTK3 Control Center initialized.")

    def log(self, text):
        buf = self.log_view.get_buffer()
        end_iter = buf.get_end_iter()
        buf.insert(end_iter, text + "\n")
        self.log_view.scroll_to_iter(end_iter, 0.0, False, 0.0, 0.0)

    # Architecture invariant: posix_spawn instead of Popen/fork
    def run_cmd(self, cmd_args):
        try:
            self.log(f"$ {' '.join(cmd_args)}")
            exec_path = shutil.which(cmd_args[0]) or cmd_args[0]
            pid = os.posix_spawn(exec_path, [exec_path] + cmd_args[1:], os.environ)
            GLib.child_watch_add(pid, self.on_cmd_done, cmd_args[0])
        except Exception as e:
            self.log(f"Error launching process: {e}")

    def on_cmd_done(self, pid, status, cmd_name):
        self.log(f"[*] Process {cmd_name} (PID {pid}) finished with status {status}.")

    def create_system_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Graphics & Acceleration Management</b>")
        grid.attach(lbl, 0, 0, 2, 1)

        btn_hud_on = Gtk.Button(label="Enable MangoHud Overlay")
        btn_hud_on.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl hud on"]))
        grid.attach(btn_hud_on, 0, 1, 1, 1)

        btn_hud_off = Gtk.Button(label="Disable MangoHud Overlay")
        btn_hud_off.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl hud off"]))
        grid.attach(btn_hud_off, 1, 1, 1, 1)

        btn_gpu_auto = Gtk.Button(label="Auto-Install GPU Acceleration Drivers")
        btn_gpu_auto.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl gpu-install"]))
        grid.attach(btn_gpu_auto, 0, 2, 2, 1)

        btn_doctor = Gtk.Button(label="Run ASL Doctor Diagnostics")
        btn_doctor.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl doctor"]))
        grid.attach(btn_doctor, 0, 3, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_gaming_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_mono = Gtk.Button(label="Install Wine Mono & Gecko Offline Bundles")
        btn_mono.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl wine-bundle install"]))
        grid.attach(btn_mono, 0, 0, 2, 1)

        btn_ver = Gtk.Button(label="Switch to Proton-GE Engine")
        btn_ver.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl wine-version set proton-ge"]))
        grid.attach(btn_ver, 0, 1, 1, 1)

        btn_sys = Gtk.Button(label="Switch to System Wine Engine")
        btn_sys.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl wine-version set system-wine"]))
        grid.attach(btn_sys, 1, 1, 1, 1)

        btn_dxvk = Gtk.Button(label="Auto-Install DXVK & VKD3D DirectX Translators")
        btn_dxvk.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl dxvk"]))
        grid.attach(btn_dxvk, 0, 2, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_gamepad_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_sync = Gtk.Button(label="Sync Bluetooth & USB Gamepads (/dev/input)")
        btn_sync.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl gamepad sync"]))
        grid.attach(btn_sync, 0, 0, 2, 1)

        btn_test = Gtk.Button(label="Test Gamepad Inputs (jstest/evtest)")
        btn_test.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl gamepad test"]))
        grid.attach(btn_test, 0, 1, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_dev_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_py = Gtk.Button(label="Install Python3 Suite")
        btn_py.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl dev-suite install python"]))
        grid.attach(btn_py, 0, 0, 1, 1)

        btn_node = Gtk.Button(label="Install Node.js & Web Tooling")
        btn_node.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl dev-suite install webdev"]))
        grid.attach(btn_node, 1, 0, 1, 1)

        btn_nvim = Gtk.Button(label="Install Neovim IDE")
        btn_nvim.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl dev-suite install neovim"]))
        grid.attach(btn_nvim, 0, 1, 1, 1)

        btn_code = Gtk.Button(label="Install VS Code Server")
        btn_code.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl dev-suite install vscode"]))
        grid.attach(btn_code, 1, 1, 1, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_sec_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_sec_net = Gtk.Button(label="Install Network Audit Suite (Nmap, Netcat, Socat)")
        btn_sec_net.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl security-suite install basic"]))
        grid.attach(btn_sec_net, 0, 0, 2, 1)

        btn_sec_full = Gtk.Button(label="Install Full Defensive Security Suite")
        btn_sec_full.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl security-suite install audit"]))
        grid.attach(btn_sec_full, 0, 1, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_maint_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_clean = Gtk.Button(label="Purge Caches & Temp Storage (asl clean)")
        btn_clean.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl clean all"]))
        grid.attach(btn_clean, 0, 0, 2, 1)

        btn_repair = Gtk.Button(label="Automated System & Mount Repair (asl repair)")
        btn_repair.connect("clicked", lambda w: self.run_cmd(["/bin/bash", "-c", "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; asl repair all"]))
        grid.attach(btn_repair, 0, 1, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

if __name__ == "__main__":
    app = ASLHubWindow()
    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
PYEOF

    cp "$tmp_app" "$target_app" 2>/dev/null || asl_exec "cp '$tmp_app' '$target_app'"
    chmod 755 "$target_app" 2>/dev/null || asl_exec "chmod 755 '$target_app'"
    ln -sf /usr/local/bin/asl-control-center "$DEBIANPATH/usr/local/bin/asl-gui" 2>/dev/null || asl_exec "ln -sf /usr/local/bin/asl-control-center '$DEBIANPATH/usr/local/bin/asl-gui'"
    ln -sf /usr/local/bin/asl-control-center "$DEBIANPATH/usr/local/bin/asl-hub" 2>/dev/null || asl_exec "ln -sf /usr/local/bin/asl-control-center '$DEBIANPATH/usr/local/bin/asl-hub'"
    rm -f "$tmp_app"

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
