#!/usr/bin/env python3
"""ASL Hub - Android Subsystem for Linux GTK3 Control Center.

Deployed into the Debian rootfs by desktop/asl-hub-installer.sh.
Invariant: all child processes MUST be launched via os.posix_spawn —
never os.fork()/subprocess. GTK3 is multithreaded and fork() under
PRoot/chroot on the 4.14 Myth kernel deadlocks in glibc atfork.
"""
import os
import sys
import shutil
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, Pango

ASL_ENV = dict(os.environ, PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")


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
            pid = os.posix_spawn(exec_path, [exec_path] + cmd_args[1:], ASL_ENV)
            GLib.child_watch_add(pid, self.on_cmd_done, cmd_args[0])
        except Exception as e:
            self.log(f"Error launching process: {e}")

    def on_cmd_done(self, pid, status, cmd_name):
        self.log(f"[*] Process {cmd_name} (PID {pid}) finished with status {status}.")

    def asl_cmd(self, subcmd):
        return ["/bin/bash", "-c", f"asl {subcmd}"]

    def create_system_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Graphics & Acceleration Management</b>")
        grid.attach(lbl, 0, 0, 2, 1)

        btn_hud_on = Gtk.Button(label="Enable MangoHud Overlay")
        btn_hud_on.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("hud on")))
        grid.attach(btn_hud_on, 0, 1, 1, 1)

        btn_hud_off = Gtk.Button(label="Disable MangoHud Overlay")
        btn_hud_off.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("hud off")))
        grid.attach(btn_hud_off, 1, 1, 1, 1)

        btn_gpu_auto = Gtk.Button(label="Auto-Install GPU Acceleration Drivers")
        btn_gpu_auto.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("gpu-install")))
        grid.attach(btn_gpu_auto, 0, 2, 2, 1)

        btn_doctor = Gtk.Button(label="Run ASL Doctor Diagnostics")
        btn_doctor.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("doctor")))
        grid.attach(btn_doctor, 0, 3, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_gaming_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_mono = Gtk.Button(label="Install Wine Mono & Gecko Offline Bundles")
        btn_mono.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("wine-bundle install")))
        grid.attach(btn_mono, 0, 0, 2, 1)

        btn_ver = Gtk.Button(label="Switch to Proton-GE Engine")
        btn_ver.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("wine-version set proton-ge")))
        grid.attach(btn_ver, 0, 1, 1, 1)

        btn_sys = Gtk.Button(label="Switch to System Wine Engine")
        btn_sys.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("wine-version set system-wine")))
        grid.attach(btn_sys, 1, 1, 1, 1)

        btn_dxvk = Gtk.Button(label="Auto-Install DXVK & VKD3D DirectX Translators")
        btn_dxvk.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("dxvk")))
        grid.attach(btn_dxvk, 0, 2, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_gamepad_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_sync = Gtk.Button(label="Sync Bluetooth & USB Gamepads (/dev/input)")
        btn_sync.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("gamepad sync")))
        grid.attach(btn_sync, 0, 0, 2, 1)

        btn_test = Gtk.Button(label="Test Gamepad Inputs (jstest/evtest)")
        btn_test.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("gamepad test")))
        grid.attach(btn_test, 0, 1, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_dev_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_py = Gtk.Button(label="Install Python3 Suite")
        btn_py.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("dev-suite install python")))
        grid.attach(btn_py, 0, 0, 1, 1)

        btn_node = Gtk.Button(label="Install Node.js & Web Tooling")
        btn_node.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("dev-suite install webdev")))
        grid.attach(btn_node, 1, 0, 1, 1)

        btn_nvim = Gtk.Button(label="Install Neovim IDE")
        btn_nvim.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("dev-suite install neovim")))
        grid.attach(btn_nvim, 0, 1, 1, 1)

        btn_code = Gtk.Button(label="Install VS Code Server")
        btn_code.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("dev-suite install vscode")))
        grid.attach(btn_code, 1, 1, 1, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_sec_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_sec_net = Gtk.Button(label="Install Network Audit Suite (Nmap, Netcat, Socat)")
        btn_sec_net.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("security-suite install basic")))
        grid.attach(btn_sec_net, 0, 0, 2, 1)

        btn_sec_full = Gtk.Button(label="Install Full Defensive Security Suite")
        btn_sec_full.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("security-suite install audit")))
        grid.attach(btn_sec_full, 0, 1, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_maint_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        btn_clean = Gtk.Button(label="Purge Caches & Temp Storage (asl clean)")
        btn_clean.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("clean all")))
        grid.attach(btn_clean, 0, 0, 2, 1)

        btn_repair = Gtk.Button(label="Automated System & Mount Repair (asl repair)")
        btn_repair.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("repair all")))
        grid.attach(btn_repair, 0, 1, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box


if __name__ == "__main__":
    app = ASLHubWindow()
    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
