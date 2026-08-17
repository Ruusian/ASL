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
import signal
import fcntl
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, Pango

ASL_ENV = dict(os.environ, PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
MAX_LOG_LINES = 500


class ASLHubWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="ASL Hub - Android Subsystem for Linux")
        self.set_default_size(860, 620)
        self.set_border_width(12)

        self.active_pid = None
        self.active_cmd = None
        self.action_buttons = []

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(main_box)

        # Header
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title("ASL Hub Control Center")
        header.set_subtitle("Debian 13 Trixie ARM64 System Dashboard")
        btn_about = Gtk.Button(label="About")
        btn_about.connect("clicked", self.show_about)
        header.pack_end(btn_about)
        self.set_titlebar(header)

        # Stack & Switcher for tabs
        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        stack.set_transition_duration(200)

        switcher = Gtk.StackSwitcher()
        switcher.set_stack(stack)
        main_box.pack_start(switcher, False, False, 0)
        main_box.pack_start(stack, True, True, 0)

        stack.add_titled(self.create_system_tab(), "system", "System & GPU")
        stack.add_titled(self.create_gaming_tab(), "gaming", "Gaming & Wine")
        stack.add_titled(self.create_gamepad_tab(), "gamepad", "Gamepad")
        stack.add_titled(self.create_dev_tab(), "dev", "Dev Suite")
        stack.add_titled(self.create_sec_tab(), "sec", "Security Audit")
        stack.add_titled(self.create_maint_tab(), "maint", "Maintenance & Repair")

        # Log Output Box
        log_frame = Gtk.Frame(label="Command Execution Log")
        log_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_min_content_height(140)
        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_monospace(True)
        self.log_view.modify_font(Pango.FontDescription("Monospace 9"))
        log_scroll.add(self.log_view)
        log_box.pack_start(log_scroll, True, True, 0)

        # Stop button row
        stop_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.btn_stop = Gtk.Button(label="Stop Running Command")
        self.btn_stop.set_sensitive(False)
        self.btn_stop.connect("clicked", self.stop_active)
        stop_row.pack_start(self.btn_stop, False, False, 0)
        self.status_label = Gtk.Label(label="Idle")
        self.status_label.set_halign(Gtk.Align.START)
        stop_row.pack_start(self.status_label, True, True, 6)
        log_box.pack_start(stop_row, False, False, 0)

        log_frame.add(log_box)
        main_box.pack_start(log_frame, False, False, 0)

        self.log("ASL Hub GTK3 Control Center initialized.")
        if not shutil.which("asl"):
            self.log("WARNING: 'asl' not found in PATH. Buttons may fail.")

    # ── Logging ──────────────────────────────────────────────────────────

    def log(self, text):
        buf = self.log_view.get_buffer()
        end_iter = buf.get_end_iter()
        buf.insert(end_iter, text + "\n")
        # Cap log length
        line_count = buf.get_line_count()
        if line_count > MAX_LOG_LINES:
            start = buf.get_start_iter()
            cut = buf.get_iter_at_line(line_count - MAX_LOG_LINES)
            buf.delete(start, cut)
        end_iter = buf.get_end_iter()
        self.log_view.scroll_to_iter(end_iter, 0.0, False, 0.0, 0.0)

    # ── Process management (posix_spawn invariant) ───────────────────────

    def run_cmd(self, cmd_args):
        """Spawn a command with output captured into the log."""
        if self.active_pid is not None:
            self.log(f"[!] Busy: '{self.active_cmd}' is still running. Stop it first.")
            return

        try:
            self.log(f"$ {' '.join(cmd_args)}")
            exec_path = shutil.which(cmd_args[0]) or cmd_args[0]

            r_fd, w_fd = os.pipe()
            file_actions = [
                (os.POSIX_SPAWN_DUP2, w_fd, 1),
                (os.POSIX_SPAWN_DUP2, w_fd, 2),
                (os.POSIX_SPAWN_CLOSE, r_fd),
                (os.POSIX_SPAWN_CLOSE, w_fd),
            ]

            pid = os.posix_spawn(exec_path, [exec_path] + cmd_args[1:],
                                 ASL_ENV, file_actions=file_actions)
            os.close(w_fd)

            # Non-blocking read on the pipe
            flags = fcntl.fcntl(r_fd, fcntl.F_GETFL)
            fcntl.fcntl(r_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

            self.active_pid = pid
            self.active_cmd = cmd_args[0]
            self.set_busy(True)

            GLib.io_add_watch(r_fd, GLib.PRIORITY_DEFAULT,
                              GLib.IO_IN | GLib.IO_HUP, self.on_output)
            GLib.child_watch_add(pid, self.on_cmd_done, cmd_args[0])
        except Exception as e:
            self.log(f"Error launching process: {e}")
            self.set_busy(False)

    def on_output(self, fd, condition):
        """GLib IO watch callback — reads captured stdout/stderr."""
        try:
            if condition & GLib.IO_IN:
                data = os.read(fd, 8192)
                if data:
                    for line in data.decode('utf-8', errors='replace').splitlines():
                        self.log(f"  {line}")
                    return True
            if condition & GLib.IO_HUP:
                # Drain remaining data
                try:
                    while True:
                        data = os.read(fd, 8192)
                        if not data:
                            break
                        for line in data.decode('utf-8', errors='replace').splitlines():
                            self.log(f"  {line}")
                except (BlockingIOError, OSError):
                    pass
                os.close(fd)
                return False
        except OSError:
            os.close(fd)
            return False
        return True

    def on_cmd_done(self, pid, status, cmd_name):
        try:
            exit_code = os.waitstatus_to_exitcode(status)
        except ValueError:
            exit_code = -1
        if exit_code == 0:
            self.log(f"[OK] {cmd_name} finished successfully.")
        else:
            self.log(f"[FAIL] {cmd_name} exited with code {exit_code}.")
        self.active_pid = None
        self.active_cmd = None
        self.set_busy(False)

    def stop_active(self, widget):
        if self.active_pid is not None:
            try:
                os.kill(self.active_pid, signal.SIGTERM)
                self.log(f"[*] Sent SIGTERM to PID {self.active_pid}.")
            except ProcessLookupError:
                self.log("[*] Process already exited.")

    def set_busy(self, busy):
        for btn in self.action_buttons:
            btn.set_sensitive(not busy)
        self.btn_stop.set_sensitive(busy)
        self.status_label.set_text(
            f"Running: {self.active_cmd}" if busy else "Idle")

    # ── Helpers ──────────────────────────────────────────────────────────

    def asl_cmd(self, subcmd):
        return ["/bin/bash", "-c", f"asl {subcmd}"]

    def add_button(self, grid, col, row, width, label, cmd_args, confirm=None):
        btn = Gtk.Button(label=label)
        if confirm:
            btn.connect("clicked", lambda w: self.confirm_and_run(cmd_args, confirm))
        else:
            btn.connect("clicked", lambda w: self.run_cmd(cmd_args))
        grid.attach(btn, col, row, width, 1)
        self.action_buttons.append(btn)
        return btn

    def confirm_and_run(self, cmd_args, message):
        dialog = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=message)
        response = dialog.run()
        dialog.destroy()
        if response == Gtk.ResponseType.OK:
            self.run_cmd(cmd_args)

    def show_about(self, widget):
        about = Gtk.AboutDialog(transient_for=self, modal=True)
        about.set_program_name("ASL Hub")
        about.set_version("1.1")
        about.set_comments("Android Subsystem for Linux Control Center\n"
                           "Debian 13 Trixie ARM64 System Dashboard")
        about.set_license_type(Gtk.License.MIT_X11)
        about.run()
        about.destroy()

    # ── System status (pure Python reads, no spawn) ──────────────────────

    def refresh_status(self, widget=None):
        info = []
        # Disk usage
        try:
            st = os.statvfs('/')
            total = st.f_blocks * st.f_frsize
            free = st.f_bavail * st.f_frsize
            used_pct = int(100 * (1 - free / total)) if total else 0
            info.append(f"Disk: {used_pct}% used ({free // (1024**3)} GB free)")
        except OSError:
            info.append("Disk: unknown")
        # Memory
        try:
            with open('/proc/meminfo') as f:
                meminfo = f.read()
            mem_total = mem_avail = 0
            for line in meminfo.splitlines():
                if line.startswith('MemTotal:'):
                    mem_total = int(line.split()[1])
                elif line.startswith('MemAvailable:'):
                    mem_avail = int(line.split()[1])
            if mem_total:
                info.append(f"RAM: {mem_avail // 1024} MB free / {mem_total // 1024} MB")
        except (OSError, ValueError):
            pass
        self.log("  ".join(info) if info else "Status unavailable")

    # ── Tabs ─────────────────────────────────────────────────────────────

    def create_system_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Graphics & Acceleration Management</b>")
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Enable MangoHud Overlay",
                        self.asl_cmd("hud on"))
        self.add_button(grid, 1, 1, 1, "Disable MangoHud Overlay",
                        self.asl_cmd("hud off"))
        self.add_button(grid, 0, 2, 2, "Auto-Install GPU Acceleration Drivers",
                        self.asl_cmd("gpu-install"))
        self.add_button(grid, 0, 3, 2, "Run ASL Doctor Diagnostics",
                        self.asl_cmd("doctor"))

        # Status row
        status_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        btn_refresh = Gtk.Button(label="Refresh System Status")
        btn_refresh.connect("clicked", self.refresh_status)
        status_row.pack_start(btn_refresh, False, False, 0)
        grid.attach(status_row, 0, 4, 2, 1)

        box.pack_start(grid, False, False, 10)
        return box

    def create_gaming_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        self.add_button(grid, 0, 0, 2, "Install Wine Mono & Gecko Offline Bundles",
                        self.asl_cmd("wine-bundle install"))
        self.add_button(grid, 0, 1, 1, "Switch to Proton-GE Engine",
                        self.asl_cmd("wine-version set proton-ge"))
        self.add_button(grid, 1, 1, 1, "Switch to System Wine Engine",
                        self.asl_cmd("wine-version set system-wine"))
        self.add_button(grid, 0, 2, 2, "Auto-Install DXVK & VKD3D DirectX Translators",
                        self.asl_cmd("dxvk"))

        box.pack_start(grid, False, False, 10)
        return box

    def create_gamepad_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        self.add_button(grid, 0, 0, 2, "Sync Bluetooth & USB Gamepads (/dev/input)",
                        self.asl_cmd("gamepad sync"))
        self.add_button(grid, 0, 1, 2, "Test Gamepad Inputs (jstest/evtest)",
                        self.asl_cmd("gamepad test"))

        box.pack_start(grid, False, False, 10)
        return box

    def create_dev_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        self.add_button(grid, 0, 0, 1, "Install Python3 Suite",
                        self.asl_cmd("dev-suite install python"))
        self.add_button(grid, 1, 0, 1, "Install Node.js & Web Tooling",
                        self.asl_cmd("dev-suite install webdev"))
        self.add_button(grid, 0, 1, 1, "Install Neovim IDE",
                        self.asl_cmd("dev-suite install neovim"))
        self.add_button(grid, 1, 1, 1, "Install VS Code Server",
                        self.asl_cmd("dev-suite install vscode"))

        box.pack_start(grid, False, False, 10)
        return box

    def create_sec_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        self.add_button(grid, 0, 0, 2, "Install Network Audit Suite (Nmap, Netcat, Socat)",
                        self.asl_cmd("security-suite install basic"))
        self.add_button(grid, 0, 1, 2, "Install Full Defensive Security Suite",
                        self.asl_cmd("security-suite install audit"))

        box.pack_start(grid, False, False, 10)
        return box

    def create_maint_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(15)
        grid.set_row_spacing(10)

        self.add_button(grid, 0, 0, 2, "Purge Caches & Temp Storage (asl clean)",
                        self.asl_cmd("clean all"),
                        confirm="This will purge all ASL caches and temporary files. Continue?")
        self.add_button(grid, 0, 1, 2, "Automated System & Mount Repair (asl repair)",
                        self.asl_cmd("repair all"))

        box.pack_start(grid, False, False, 10)
        return box


if __name__ == "__main__":
    app = ASLHubWindow()
    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()
