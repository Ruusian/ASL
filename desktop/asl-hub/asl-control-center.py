#!/usr/bin/env python3
"""ASL Hub - Android Subsystem for Linux GTK3 Control Center.

Deployed into the Debian rootfs by desktop/asl-hub-installer.sh.
Invariant: all child processes MUST be launched via os.posix_spawn —
never os.fork()/subprocess. GTK3 is multithreaded and fork() under
chroot on the 4.14 Myth kernel deadlocks in glibc atfork.
"""
import os
import re
import sys
import shutil
import shlex
import signal
import fcntl
import glob
import time
import gi

APP_VERSION = "2.6.0"

if not os.environ.get("DISPLAY"):
    sys.stderr.write("[!] Error: $DISPLAY environment variable is not set.\n"
                     "    ASL Control Center requires an active X11 display (Termux-X11 / VNC).\n"
                     "    For CLI management, run: asl status\n")
    sys.exit(1)

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, Pango

ASL_ENV = dict(
    os.environ,
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/data/data/com.termux/files/usr/bin",
    DISPLAY=os.environ.get("DISPLAY", ":0"),
    PULSE_SERVER=os.environ.get("PULSE_SERVER", "127.0.0.1"),
    XDG_DATA_DIRS=os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share"),
    TMPDIR="/tmp"
)
MAX_LOG_LINES = 600
KILL_ESCALATION_MS = 5000
STATUS_REFRESH_SEC = 15
CONFIG_PATH = os.path.expanduser("~/.config/asl-hub.conf")
MAX_HISTORY = 25

EXIT_CODE_HINTS = {
    126: "permission denied or not executable",
    127: "command not found",
    130: "interrupted (SIGINT)",
    137: "killed (SIGKILL)",
    143: "terminated (SIGTERM)",
}

GAMEPAD_KEYWORDS = (
    "gamepad", "joystick", "controller", "xbox", "playstation",
    "dualshock", "dualsense", "joycon", "pro controller", "game controller",
)


class ASLHubWindow(Gtk.Window):
    def apply_custom_css(self):
        try:
            css_provider = Gtk.CssProvider()
            css_data = b"""
            window {
                background-color: #1a1b26;
                color: #c0caf5;
                font-family: 'Cantarell', 'Inter', 'Noto Sans', sans-serif;
                font-size: 10pt;
            }
            headerbar {
                background-image: linear-gradient(to bottom, #1f2335, #1a1b26);
                border-bottom: 1px solid #3b4261;
                padding: 6px;
            }
            headerbar label.title {
                color: #7dcfff;
                font-weight: bold;
                font-size: 11pt;
            }
            headerbar label.subtitle {
                color: #9aa5ce;
                font-size: 9pt;
            }
            notebook header {
                background-color: #16161e;
                border-bottom: 1px solid #3b4261;
                padding: 2px 4px 0 4px;
            }
            notebook tab {
                padding: 6px 12px;
                border-radius: 6px 6px 0 0;
                background-color: #1f2335;
                color: #a9b1d6;
                margin-right: 2px;
            }
            notebook tab:checked {
                background-color: #24283b;
                color: #7aa2f7;
                font-weight: bold;
                border-bottom: 2px solid #7aa2f7;
            }
            button {
                background-image: linear-gradient(to bottom, #24283b, #1f2335);
                color: #c0caf5;
                border: 1px solid #3b4261;
                border-radius: 6px;
                padding: 5px 10px;
                font-weight: 500;
            }
            button:hover {
                background-image: linear-gradient(to bottom, #2ac3de, #7dcfff);
                color: #15161e;
                border-color: #7dcfff;
            }
            button.suggested-action {
                background-image: linear-gradient(to bottom, #9ece6a, #73daca);
                color: #15161e;
                font-weight: bold;
                border-color: #9ece6a;
            }
            button.destructive-action {
                background-image: linear-gradient(to bottom, #f7768e, #db4b4b);
                color: #ffffff;
                font-weight: bold;
                border-color: #f7768e;
            }
            frame {
                border: 1px solid #3b4261;
                border-radius: 8px;
                background-color: #24283b;
                padding: 6px;
            }
            frame > label {
                color: #7aa2f7;
                font-weight: bold;
            }
            textview text {
                background-color: #15161e;
                color: #7aa2f7;
                font-family: 'JetBrains Mono', 'Monospace', monospace;
                padding: 8px;
            }
            progressbar progress {
                background-color: #7aa2f7;
                border-radius: 4px;
            }
            progressbar trough {
                background-color: #16161e;
                border-radius: 4px;
                border: 1px solid #3b4261;
            }
            entry {
                background-color: #15161e;
                color: #c0caf5;
                border: 1px solid #3b4261;
                border-radius: 6px;
                padding: 4px 8px;
            }
            entry:focus {
                border-color: #7aa2f7;
            }
            """
            css_provider.load_from_data(css_data)
            screen = Gdk.Screen.get_default()
            if screen:
                Gtk.StyleContext.add_provider_for_screen(
                    screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                )
        except Exception:
            pass

    def __init__(self):
        super().__init__(title="ASL Hub - Android Subsystem for Linux")
        self.set_default_size(920, 680)
        self.set_border_width(10)
        self.apply_custom_css()

        self.active_pid = None
        self.active_cmd = None
        self.kill_timer = None
        self.action_buttons = []
        self.cmd_history = []
        self.fd_state = {}
        self.search_matches = []
        self.search_idx = 0

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.add(main_box)

        # Header
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title("ASL Hub Control Center")
        header.set_subtitle(f"Debian 13 Trixie ARM64 — ASL v{APP_VERSION}")

        btn_about = Gtk.Button(label="About")
        btn_about.connect("clicked", self.show_about)
        header.pack_end(btn_about)

        btn_doctor = Gtk.Button(label="Doctor")
        btn_doctor.set_tooltip_text("Run comprehensive ASL diagnostic checks")
        btn_doctor.connect("clicked", lambda w: self.run_cmd(self.asl_cmd("doctor")))
        header.pack_end(btn_doctor)

        btn_shell = Gtk.Button(label="Shell")
        btn_shell.set_tooltip_text("Open terminal emulator inside ASL")
        btn_shell.connect("clicked", self.open_shell)
        header.pack_end(btn_shell)

        self.set_titlebar(header)

        # Keyboard shortcuts
        accel = Gtk.AccelGroup()
        accel.connect(Gdk.KEY_q, Gdk.ModifierType.CONTROL_MASK, 0,
                      lambda *a: self.destroy())
        accel.connect(Gdk.KEY_w, Gdk.ModifierType.CONTROL_MASK, 0,
                      lambda *a: self.destroy())
        accel.connect(Gdk.KEY_l, Gdk.ModifierType.CONTROL_MASK, 0,
                      lambda *a: self.clear_log(None))
        accel.connect(Gdk.KEY_s, Gdk.ModifierType.CONTROL_MASK, 0,
                      lambda *a: self.save_log(None))
        accel.connect(Gdk.KEY_f, Gdk.ModifierType.CONTROL_MASK, 0,
                      lambda *a: self.toggle_search())
        self.add_accel_group(accel)

        # Live status panel
        status_frame = Gtk.Frame(label="Live System Metrics")
        self.status_grid = Gtk.Grid()
        self.status_grid.set_column_spacing(20)
        self.status_grid.set_row_spacing(4)
        self.status_grid.set_border_width(6)
        self.status_labels = {}
        for i, key in enumerate(("mounts", "gpu", "audio", "display", "disk", "ram")):
            lbl = Gtk.Label(label="—")
            lbl.set_halign(Gtk.Align.START)
            lbl.set_use_markup(True)
            self.status_labels[key] = lbl
            self.status_grid.attach(lbl, i % 3, i // 3, 1, 1)
        status_frame.add(self.status_grid)
        main_box.pack_start(status_frame, False, False, 0)

        # Stack & Switcher for tabs
        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        stack.set_transition_duration(180)

        switcher = Gtk.StackSwitcher()
        switcher.set_stack(stack)
        main_box.pack_start(switcher, False, False, 0)
        main_box.pack_start(stack, True, True, 0)

        tabs = [
            (self.create_system_tab(), "system", "System & GPU", "video-display"),
            (self.create_audio_tab(), "audio", "Audio & Media", "audio-volume-high"),
            (self.create_remote_tab(), "remote", "Remote Tunnels", "network-transmit-receive"),
            (self.create_gamepad_tab(), "gamepad", "Gamepad", "input-gaming"),
            (self.create_dev_tab(), "dev", "Dev Suite", "applications-development"),
            (self.create_sec_tab(), "sec", "Security Audit", "changes-prevent"),
            (self.create_maint_tab(), "maint", "Maintenance", "system-run"),
            (self.create_services_tab(), "services", "AI & Services", "preferences-system-windows"),
        ]
        for widget, name, title, icon in tabs:
            stack.add_titled(widget, name, title)
            stack.child_set_property(widget, "icon-name", icon)

        # Custom command row
        hist_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        hist_lbl = Gtk.Label(label="ASL Command:")
        hist_row.pack_start(hist_lbl, False, False, 0)
        self.history_entry = Gtk.Entry()
        self.history_entry.set_hexpand(True)
        self.history_entry.set_placeholder_text(
            "Type ASL command (e.g. status, doctor, mode gpu) and press Enter")
        self.history_entry.connect("activate", self.run_entry_command)
        self.history_completion = Gtk.EntryCompletion()
        self.history_store = Gtk.ListStore(str)
        self.history_completion.set_model(self.history_store)
        self.history_completion.set_text_column(0)
        self.history_completion.set_minimum_key_length(1)
        self.history_entry.set_completion(self.history_completion)
        hist_row.pack_start(self.history_entry, True, True, 0)
        btn_rerun = Gtk.Button(label="Run")
        btn_rerun.set_tooltip_text("Execute command in chroot")
        btn_rerun.connect("clicked", self.run_entry_command)
        hist_row.pack_start(btn_rerun, False, False, 0)
        main_box.pack_start(hist_row, False, False, 0)

        # Log Output Box
        log_frame = Gtk.Frame(label="Command Execution Console")
        log_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)

        # Search bar
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text(
            "Search log... (Enter = next, Shift+Enter = previous)")
        self.search_entry.connect("search-changed", self.on_search_changed)
        self.search_entry.connect("activate", self.on_search_activate)
        self.search_entry.connect("key-press-event", self.on_search_key_press)
        self.search_entry.set_no_show_all(True)
        self._shift_held = False
        log_box.pack_start(self.search_entry, False, False, 0)

        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_min_content_height(130)
        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_monospace(True)
        self.log_view.modify_font(Pango.FontDescription("Monospace 9"))
        log_scroll.add(self.log_view)
        log_box.pack_start(log_scroll, True, True, 0)

        # Themed text tags
        buf = self.log_view.get_buffer()
        dark = self._is_dark_theme()
        c_ok = "#81c784" if dark else "#2e7d32"
        c_fail = "#e57373" if dark else "#c62828"
        c_warn = "#ffb74d" if dark else "#e65100"
        c_info = "#64b5f6" if dark else "#1565c0"
        self.tag_cmd = buf.create_tag("cmd", weight=Pango.Weight.BOLD)
        self.tag_ok = buf.create_tag("ok", foreground=c_ok, weight=Pango.Weight.BOLD)
        self.tag_fail = buf.create_tag("fail", foreground=c_fail, weight=Pango.Weight.BOLD)
        self.tag_warn = buf.create_tag("warn", foreground=c_warn)
        self.tag_info = buf.create_tag("info", foreground=c_info)
        self.tag_search = buf.create_tag("search", background="#ffee58", foreground="#000000")
        self.tag_time = buf.create_tag("time", style=Pango.Style.ITALIC)

        # Control row
        ctrl_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.btn_stop = Gtk.Button(label="Stop")
        self.btn_stop.set_sensitive(False)
        self.btn_stop.set_tooltip_text("Send SIGTERM to running command (escalates to SIGKILL after 5s)")
        self.btn_stop.connect("clicked", self.stop_active)
        ctrl_row.pack_start(self.btn_stop, False, False, 0)

        btn_save = Gtk.Button(label="Save Log")
        btn_save.set_tooltip_text("Save output log to file (Ctrl+S)")
        btn_save.connect("clicked", self.save_log)
        ctrl_row.pack_start(btn_save, False, False, 0)

        btn_clear = Gtk.Button(label="Clear")
        btn_clear.set_tooltip_text("Clear console output (Ctrl+L)")
        btn_clear.connect("clicked", self.clear_log)
        ctrl_row.pack_start(btn_clear, False, False, 0)

        self.spinner = Gtk.Spinner()
        ctrl_row.pack_start(self.spinner, False, False, 4)

        self.status_label = Gtk.Label(label="Idle")
        self.status_label.set_halign(Gtk.Align.START)
        ctrl_row.pack_start(self.status_label, True, True, 6)

        btn_refresh = Gtk.Button(label="Refresh Status")
        btn_refresh.connect("clicked", lambda w: self.refresh_status())
        ctrl_row.pack_start(btn_refresh, False, False, 0)

        log_box.pack_start(ctrl_row, False, False, 0)
        log_frame.add(log_box)
        main_box.pack_start(log_frame, False, False, 0)

        self.log(f"ASL Hub GTK3 Control Center v{APP_VERSION} initialized.", "info")
        self.log("Shortcuts: Ctrl+Q quit, Ctrl+F search log, Ctrl+L clear, Ctrl+S save.", "info")
        if not (shutil.which("asl-cli") or shutil.which("asl")):
            self.log("WARNING: 'asl-cli' / 'asl' not found in PATH.", "warn")

        self.load_state()
        self.rebuild_history_combo()
        self.refresh_status()
        self.refresh_gamepads()
        GLib.timeout_add_seconds(STATUS_REFRESH_SEC, self.auto_refresh)
        GLib.timeout_add_seconds(60, self.periodic_save)

    def _is_dark_theme(self):
        settings = Gtk.Settings.get_default()
        if settings and settings.get_property("gtk-application-prefer-dark-theme"):
            return True
        theme = (settings.get_property("gtk-theme-name") or "").lower() if settings else ""
        return "dark" in theme or "black" in theme

    def auto_refresh(self):
        self.refresh_status()
        self.refresh_gamepads()
        return True

    # ── State persistence ───────────────────────────────────────────────

    def load_state(self):
        try:
            with open(CONFIG_PATH) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("size="):
                        w, h = line.split("=", 1)[1].split("x")
                        self.resize(int(w), int(h))
                    elif line.startswith("pos="):
                        x, y = line.split("=", 1)[1].split("x")
                        self.move(int(x), int(y))
                    elif line.startswith("history="):
                        entry = line.split("=", 1)[1]
                        if entry and entry not in self.cmd_history:
                            self.cmd_history.append(entry)
        except (OSError, ValueError):
            pass
        self.cmd_history = self.cmd_history[:MAX_HISTORY]

    def save_state(self):
        try:
            os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
            w, h = self.get_size()
            x, y = self.get_position()
            with open(CONFIG_PATH, 'w') as f:
                f.write(f"size={w}x{h}\n")
                f.write(f"pos={x}x{y}\n")
                for entry in self.cmd_history:
                    f.write(f"history={entry}\n")
        except OSError:
            pass

    def periodic_save(self):
        self.save_state()
        return True

    # ── Logging ─────────────────────────────────────────────────────────

    def log(self, text, tag=None):
        buf = self.log_view.get_buffer()
        end_iter = buf.get_end_iter()
        stamp = time.strftime("[%H:%M:%S] ")
        buf.insert_with_tags_by_name(end_iter, stamp, "time")
        if tag:
            buf.insert_with_tags_by_name(end_iter, text + "\n", tag)
        else:
            buf.insert(end_iter, text + "\n")
        line_count = buf.get_line_count()
        if line_count > MAX_LOG_LINES:
            start = buf.get_start_iter()
            cut = buf.get_iter_at_line(line_count - MAX_LOG_LINES)
            buf.delete(start, cut)
        end_iter = buf.get_end_iter()
        self.log_view.scroll_to_iter(end_iter, 0.0, False, 0.0, 0.0)

    def clear_log(self, widget):
        buf = self.log_view.get_buffer()
        buf.set_text("")
        self.log("Log cleared.", "info")

    def save_log(self, widget):
        dialog = Gtk.FileChooserDialog(
            title="Save Log", transient_for=self,
            action=Gtk.FileChooserAction.SAVE)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_SAVE, Gtk.ResponseType.OK)
        dialog.set_do_overwrite_confirmation(True)
        dialog.set_current_name("asl-hub-log.txt")
        if dialog.run() == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            buf = self.log_view.get_buffer()
            text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), True)
            try:
                with open(path, 'w') as f:
                    f.write(text)
                self.log(f"[*] Log saved to {path}", "info")
            except OSError as e:
                self.log(f"[FAIL] Could not save log: {e}", "fail")
        dialog.destroy()

    # ── Search (Ctrl+F) ──────────────────────────────────────────────────

    def toggle_search(self):
        if self.search_entry.get_visible():
            self.search_entry.hide()
            buf = self.log_view.get_buffer()
            start, end = buf.get_bounds()
            buf.remove_tag(self.tag_search, start, end)
        else:
            self.search_entry.show()
            self.search_entry.grab_focus()

    def on_search_changed(self, entry):
        buf = self.log_view.get_buffer()
        start, end = buf.get_bounds()
        buf.remove_tag(self.tag_search, start, end)
        self.search_matches = []
        self.search_idx = 0
        needle = entry.get_text()
        if not needle:
            return
        full = buf.get_text(start, end, True)
        for m in re.finditer(re.escape(needle), full, re.IGNORECASE):
            self.search_matches.append((m.start(), m.end()))
            m_start = buf.get_iter_at_offset(m.start())
            m_end = buf.get_iter_at_offset(m.end())
            buf.apply_tag(self.tag_search, m_start, m_end)
        if self.search_matches:
            self.jump_to_match(0)

    def on_search_key_press(self, entry, event):
        self._shift_held = bool(event.state & Gdk.ModifierType.SHIFT_MASK)
        return False

    def on_search_activate(self, entry):
        if not self.search_matches:
            return
        self.jump_to_match(self.search_idx + (1 if not self._shift_held else -1))

    def jump_to_match(self, idx):
        if not self.search_matches:
            return
        idx %= len(self.search_matches)
        self.search_idx = idx
        start_off, end_off = self.search_matches[idx]
        buf = self.log_view.get_buffer()
        m_start = buf.get_iter_at_offset(start_off)
        self.log_view.scroll_to_iter(m_start, 0.0, False, 0.0, 0.0)
        self.status_label.set_text(
            f"Match {idx + 1}/{len(self.search_matches)}")

    # ── Command history ──────────────────────────────────────────────────

    def add_to_history(self, cmd_args):
        entry = shlex.join(cmd_args)
        if entry in self.cmd_history:
            self.cmd_history.remove(entry)
        self.cmd_history.insert(0, entry)
        self.cmd_history = self.cmd_history[:MAX_HISTORY]
        self.rebuild_history_combo()

    def rebuild_history_combo(self):
        self.history_store.clear()
        for entry in self.cmd_history:
            self.history_store.append([entry])

    def run_entry_command(self, widget):
        text = self.history_entry.get_text().strip()
        if not text:
            self.log("[!] No command entered.", "warn")
            return
        # If user entered bare subcommand like 'status' or 'doctor', wrap in asl_cmd
        if not text.startswith("/") and not text.startswith("asl"):
            cmd_args = self.asl_cmd(text)
        else:
            try:
                cmd_args = shlex.split(text)
            except ValueError as e:
                self.log(f"[FAIL] Could not parse command: {e}", "fail")
                return
        self.run_cmd(cmd_args)

    # ── Process execution (posix_spawn invariant) ────────────────────────

    def run_cmd(self, cmd_args):
        if self.active_pid is not None:
            self.log(f"[!] Busy: '{self.active_cmd}' is still running. Stop it first.", "warn")
            return

        try:
            display_cmd = cmd_args[2] if (len(cmd_args) == 3 and cmd_args[0] == "/bin/bash" and cmd_args[1] == "-c") else ' '.join(cmd_args)
            self.log(f"$ {display_cmd}", "cmd")
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

            flags = fcntl.fcntl(r_fd, fcntl.F_GETFL)
            fcntl.fcntl(r_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

            self.active_pid = pid
            self.active_cmd = display_cmd.split()[0]
            self.add_to_history(cmd_args)
            self.set_busy(True)

            GLib.io_add_watch(r_fd, GLib.PRIORITY_DEFAULT,
                              GLib.IO_IN | GLib.IO_HUP, self.on_output)
            GLib.child_watch_add(pid, self.on_cmd_done, self.active_cmd)
        except Exception as e:
            self.log(f"Error launching process: {e}", "fail")
            self.set_busy(False)

    def launch_gui_detached(self, exec_args):
        """Launch an independent GUI application without stdout capture."""
        try:
            exec_path = shutil.which(exec_args[0], path=ASL_ENV.get("PATH"))
            if not exec_path:
                self.log(f"[!] Application '{exec_args[0]}' is not installed.", "warn")
                return
            devnull = os.open(os.devnull, os.O_RDWR)
            file_actions = [
                (os.POSIX_SPAWN_DUP2, devnull, 0),
                (os.POSIX_SPAWN_DUP2, devnull, 1),
                (os.POSIX_SPAWN_DUP2, devnull, 2),
                (os.POSIX_SPAWN_CLOSE, devnull),
            ]
            pid = os.posix_spawn(exec_path, [exec_path] + exec_args[1:],
                                 ASL_ENV, file_actions=file_actions)
            os.close(devnull)
            self.log(f"[*] Launched {exec_args[0]} (PID {pid}).", "info")
        except Exception as e:
            self.log(f"[FAIL] Could not launch {exec_args[0]}: {e}", "fail")

    def _decode_chunk(self, fd, data):
        carry = self.fd_state.get(fd, b"")
        raw = carry + data
        for trim in range(0, 4):
            try:
                text = raw[:len(raw) - trim].decode('utf-8') if trim else raw.decode('utf-8')
                self.fd_state[fd] = raw[len(raw) - trim:] if trim else b""
                return text
            except UnicodeDecodeError:
                continue
        self.fd_state[fd] = b""
        return raw.decode('utf-8', errors='replace')

    def on_output(self, fd, condition):
        try:
            if condition & GLib.IO_IN:
                data = os.read(fd, 8192)
                if data:
                    for line in self._decode_chunk(fd, data).splitlines():
                        self.log(f"  {line}")
                    return True
            if condition & GLib.IO_HUP:
                try:
                    while True:
                        data = os.read(fd, 8192)
                        if not data:
                            break
                        for line in self._decode_chunk(fd, data).splitlines():
                            self.log(f"  {line}")
                except (BlockingIOError, OSError):
                    pass
                leftover = self.fd_state.pop(fd, b"")
                if leftover:
                    self.log(f"  {leftover.decode('utf-8', errors='replace')}")
                os.close(fd)
                return False
        except OSError:
            self.fd_state.pop(fd, None)
            os.close(fd)
            return False
        return True

    def on_cmd_done(self, pid, status, cmd_name):
        try:
            exit_code = os.waitstatus_to_exitcode(status)
        except ValueError:
            exit_code = -1
        if exit_code == 0:
            self.log(f"[OK] {cmd_name} completed successfully.", "ok")
            self.notify("ASL Hub", f"{cmd_name} finished successfully.")
        else:
            hint = EXIT_CODE_HINTS.get(exit_code)
            if exit_code < 0:
                hint = f"killed by signal {-exit_code}"
            suffix = f" ({hint})" if hint else ""
            self.log(f"[FAIL] {cmd_name} exited with code {exit_code}{suffix}.", "fail")
            self.notify("ASL Hub", f"{cmd_name} failed (code {exit_code}).")
        self.active_pid = None
        self.active_cmd = None
        if self.kill_timer is not None:
            GLib.source_remove(self.kill_timer)
            self.kill_timer = None
        self.set_busy(False)
        self.refresh_status()

    def open_shell(self, widget):
        terminals = (
            ("xfce4-terminal", ["--command=/bin/bash"]),
            ("x-terminal-emulator", ["-e", "/bin/bash"]),
            ("gnome-terminal", ["--", "/bin/bash"]),
            ("xterm", ["-e", "/bin/bash"]),
        )
        for term, args in terminals:
            path = shutil.which(term)
            if path:
                try:
                    os.posix_spawn(path, [path] + args, ASL_ENV)
                    self.log(f"[*] Opened shell in {term}.", "info")
                except OSError as e:
                    self.log(f"[FAIL] Could not launch {term}: {e}", "fail")
                return
        self.log("[!] No terminal emulator found.", "warn")

    def notify(self, summary, body):
        if self.is_active():
            return
        notify_send = shutil.which("notify-send")
        if not notify_send:
            return
        try:
            os.posix_spawn(notify_send, [notify_send, summary, body], ASL_ENV)
        except OSError:
            pass

    def stop_active(self, widget):
        if self.active_pid is None:
            return
        try:
            os.kill(self.active_pid, signal.SIGTERM)
            self.log(f"[*] Sent SIGTERM to PID {self.active_pid}.", "info")
        except ProcessLookupError:
            self.log("[*] Process already exited.", "info")
            return
        if self.kill_timer is None:
            self.kill_timer = GLib.timeout_add(KILL_ESCALATION_MS, self.escalate_kill)

    def escalate_kill(self):
        self.kill_timer = None
        if self.active_pid is not None:
            try:
                os.kill(self.active_pid, signal.SIGKILL)
                self.log(f"[!] Escalated to SIGKILL for PID {self.active_pid}.", "warn")
            except ProcessLookupError:
                pass
        return False

    def set_busy(self, busy):
        for btn in self.action_buttons:
            btn.set_sensitive(not busy)
        self.btn_stop.set_sensitive(busy)
        if busy:
            self.spinner.start()
            self.status_label.set_text(f"Running: {self.active_cmd}")
        else:
            self.spinner.stop()
            self.status_label.set_text("Idle")

    # ── Helpers ──────────────────────────────────────────────────────────

    def asl_cmd(self, subcmd):
        cli = shutil.which("asl-cli") or shutil.which("asl") or "/usr/local/bin/asl-cli"
        return ["/bin/bash", "-c", f"{cli} {subcmd}"]

    def add_button(self, grid, col, row, width, label, cmd_args, confirm=None, suggested=False, destructive=False):
        btn = Gtk.Button(label=label)
        if suggested:
            btn.get_style_context().add_class("suggested-action")
        if destructive:
            btn.get_style_context().add_class("destructive-action")

        if len(cmd_args) == 3 and cmd_args[0] == "/bin/bash" and cmd_args[1] == "-c":
            btn.set_tooltip_text(f"Runs: {cmd_args[2]}")
        else:
            btn.set_tooltip_text(f"Runs: {' '.join(cmd_args)}")

        if confirm:
            btn.connect("clicked", lambda w: self.confirm_and_run(cmd_args, confirm))
        else:
            btn.connect("clicked", lambda w: self.run_cmd(cmd_args))

        grid.attach(btn, col, row, width, 1)
        self.action_buttons.append(btn)
        return btn

    def add_gui_button(self, grid, col, row, width, label, exec_args, tooltip=None):
        btn = Gtk.Button(label=label)
        btn.set_tooltip_text(tooltip or f"Launches: {' '.join(exec_args)}")
        btn.connect("clicked", lambda w: self.launch_gui_detached(exec_args))
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
        about.set_program_name("ASL Hub Control Center")
        about.set_version(APP_VERSION)
        about.set_comments("Android Subsystem for Linux GUI Management Console\n"
                           "Debian 13 Trixie ARM64 System Dashboard")
        about.set_license_type(Gtk.License.MIT_X11)
        about.run()
        about.destroy()

    # ── Live system status (pure Python reads, zero fork) ────────────────

    def refresh_status(self):
        self.status_labels["mounts"].set_markup(f"<b>Mounts:</b> {self._check_mounts()}")
        self.status_labels["gpu"].set_markup(f"<b>GPU:</b> {self._check_gpu()}")
        self.status_labels["audio"].set_markup(f"<b>Audio:</b> {self._check_audio()}")
        display = os.environ.get("DISPLAY", "")
        self.status_labels["display"].set_markup(
            f"<b>Display:</b> {display}" if display else "<b>Display:</b> None")
        self.status_labels["disk"].set_markup(f"<b>Disk:</b> {self._check_disk()}")
        self.status_labels["ram"].set_markup(f"<b>RAM:</b> {self._check_ram()}")

    def _check_mounts(self):
        try:
            with open('/proc/mounts') as f:
                mounts = f.read()
            needed = {'/proc': False, '/dev': False, '/sys': False}
            for line in mounts.splitlines():
                parts = line.split()
                if len(parts) >= 2 and parts[1] in needed:
                    needed[parts[1]] = True
            missing = [k for k, v in needed.items() if not v]
            return "<span color='#81c784'>OK</span>" if not missing else f"<span color='#f7768e'>missing {', '.join(missing)}</span>"
        except OSError:
            return "unknown"

    def _check_gpu(self):
        try:
            if os.environ.get("GALLIUM_DRIVER") == "zink":
                return "Turnip/Zink (Vulkan)"
            if os.path.exists('/etc/profile.d/asl_env.sh'):
                with open('/etc/profile.d/asl_env.sh') as f:
                    env = f.read()
                if 'MESA_LOADER_DRIVER_OVERRIDE=zink' in env or 'GALLIUM_DRIVER=zink' in env:
                    return "Turnip/Zink (Vulkan)"
                if 'GALLIUM_DRIVER=virpipe' in env:
                    return "VirGL (Hardware)"
                if 'LIBGL_ALWAYS_SOFTWARE=1' in env:
                    return "Software (llvmpipe)"
            if os.path.exists('/dev/kgsl-3d0') or os.path.exists('/dev/dri/renderD128'):
                return "Adreno GPU"
            return "Profile Set"
        except OSError:
            return "No Profile"

    def _check_audio(self):
        try:
            for p in glob.glob('/proc/[0-9]*/cmdline'):
                try:
                    with open(p, 'rb') as f:
                        if b'pulseaudio' in f.read():
                            return "<span color='#81c784'>Running</span>"
                except OSError:
                    continue
            return "<span color='#ffb74d'>Stopped</span>"
        except Exception:
            return "unknown"

    def _check_disk(self):
        try:
            st = os.statvfs('/')
            total = st.f_blocks * st.f_frsize
            free = st.f_bavail * st.f_frsize
            if not total:
                return "unknown"
            used_pct = int(100 * (1 - free / total))
            return f"{used_pct}% used ({free // (1024**3)} GB free)"
        except OSError:
            return "unknown"

    def _check_ram(self):
        try:
            mem_total = mem_avail = 0
            with open('/proc/meminfo') as f:
                for line in f:
                    if line.startswith('MemTotal:'):
                        mem_total = int(line.split()[1])
                    elif line.startswith('MemAvailable:'):
                        mem_avail = int(line.split()[1])
            if mem_total:
                free_mb = mem_avail // 1024
                tot_mb = mem_total // 1024
                pct = int(100 * (1 - mem_avail / mem_total))
                return f"{free_mb} MB free / {tot_mb} MB ({pct}%)"
            return "unknown"
        except (OSError, ValueError):
            return "unknown"

    # ── Gamepad detection ────────────────────────────────────────────────

    def refresh_gamepads(self):
        devices = []
        for ev_path in sorted(glob.glob('/dev/input/event*')):
            ev_name = os.path.basename(ev_path)
            try:
                with open(f"/sys/class/input/{ev_name}/device/name") as f:
                    dev_name = f.read().strip()
            except OSError:
                continue
            if self._is_gamepad(ev_name, dev_name):
                devices.append(f"{ev_path}: {dev_name}")
        buf = self.gamepad_view.get_buffer()
        if devices:
            buf.set_text("\n".join(devices))
        else:
            buf.set_text("No gamepads/joysticks detected in /dev/input/.\nClick 'Sync Bluetooth & USB Gamepads' to probe Android devices.")

    def _is_gamepad(self, ev_name, dev_name):
        lower = dev_name.lower()
        if any(k in lower for k in GAMEPAD_KEYWORDS):
            return True
        try:
            with open(f"/sys/class/input/{ev_name}/device/capabilities/abs") as f:
                val = int(f.read().strip(), 16)
            has_xy = (val & 0x3) == 0x3
            has_hat = (val >> 16) & 0xF
            extra_axes = bin((val >> 2) & 0x3F).count('1')
            if has_xy and (has_hat or extra_axes >= 2):
                return True
        except (OSError, ValueError):
            pass
        return False

    # ── Tab: System & GPU ────────────────────────────────────────────────

    def create_system_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        lbl = Gtk.Label()
        lbl.set_markup("<b>GPU Acceleration &amp; Performance Profiles</b>")
        lbl.set_halign(Gtk.Align.START)
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Turbo GPU Profile (Performance Governor)",
                        self.asl_cmd("mode gpu"), suggested=True)
        self.add_button(grid, 1, 1, 1, "Balanced Profile (Default Schedutil)",
                        self.asl_cmd("mode balanced"))

        self.add_button(grid, 0, 2, 1, "Enable MangoHud Overlay",
                        self.asl_cmd("hud on"))
        self.add_button(grid, 1, 2, 1, "Disable MangoHud Overlay",
                        self.asl_cmd("hud off"))

        self.add_button(grid, 0, 3, 1, "Auto-Install GPU Drivers (Vulkan/Zink)",
                        self.asl_cmd("gpu-install"))
        self.add_button(grid, 1, 3, 1, "Probe GPU & Driver Capabilities",
                        self.asl_cmd("gpu"))

        self.add_gui_button(grid, 0, 4, 1, "Launch 3D GPU Render Test (glxgears)",
                            ["glxgears"], tooltip="Launch native hardware OpenGL 3D rendering stress test")
        self.add_button(grid, 1, 4, 1, "CPU Thermal & Clock Diagnostics",
                        self.asl_cmd("thermal"))

        lbl_res = Gtk.Label()
        lbl_res.set_markup("<b>Display Resolution &amp; Scaling Presets</b>")
        lbl_res.set_halign(Gtk.Align.START)
        grid.attach(lbl_res, 0, 5, 2, 1)

        self.add_button(grid, 0, 6, 1, "Set 720p Display (1280x720)",
                        self.asl_cmd("resolution 720p"))
        self.add_button(grid, 1, 6, 1, "Set 1080p Display (1920x1080)",
                        self.asl_cmd("resolution 1080p"))
        self.add_button(grid, 0, 7, 2, "Reset to Native Device Display Resolution",
                        self.asl_cmd("resolution native"))

        box.pack_start(grid, False, False, 6)
        return box

    # ── Tab: Audio & Media ───────────────────────────────────────────────

    def create_audio_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        lbl = Gtk.Label()
        lbl.set_markup("<b>PulseAudio Server &amp; Sound Management</b>")
        lbl.set_halign(Gtk.Align.START)
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Start PulseAudio Sound Server",
                        self.asl_cmd("audio start"), suggested=True)
        self.add_button(grid, 1, 1, 1, "Stop PulseAudio Sound Server",
                        self.asl_cmd("audio stop"))

        self.add_button(grid, 0, 2, 1, "Play Audio Test Tone (Speaker Check)",
                        self.asl_cmd("audio test"))
        self.add_gui_button(grid, 1, 2, 1, "Open PulseAudio Volume Control GUI",
                            ["pavucontrol"], tooltip="Open native GTK Volume Mixer (pavucontrol)")

        lbl_desk = Gtk.Label()
        lbl_desk.set_markup("<b>Desktop &amp; Application Integration</b>")
        lbl_desk.set_halign(Gtk.Align.START)
        grid.attach(lbl_desk, 0, 3, 2, 1)

        self.add_button(grid, 0, 4, 1, "Sync Android & Linux Desktop Apps",
                        self.asl_cmd("desktop sync-apps"))
        self.add_button(grid, 1, 4, 1, "Restart Desktop Environment Session",
                        self.asl_cmd("desktop restart"),
                        confirm="Restart XFCE Desktop session? Running GUI applications will close.")

        box.pack_start(grid, False, False, 6)
        return box

    # ── Tab: Remote Tunnels ──────────────────────────────────────────────

    def create_remote_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Remote Access &amp; Auto-Connect Tunnels</b>")
        lbl.set_halign(Gtk.Align.START)
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Start All Tunnels (LAN + Oracle + Serveo)",
                        self.asl_cmd("remote all"), suggested=True)
        self.add_button(grid, 1, 1, 1, "Start Auto-Connect Daemon",
                        self.asl_cmd("remote autoconnect start"))

        self.add_button(grid, 0, 2, 1, "LAN SSH Server Start",
                        self.asl_cmd("remote lan start"))
        self.add_button(grid, 1, 2, 1, "LAN SSH Server Stop",
                        self.asl_cmd("remote lan stop"))

        lbl2 = Gtk.Label()
        lbl2.set_markup("<b>Oracle VPS Private Relay Host</b>")
        lbl2.set_halign(Gtk.Align.START)
        grid.attach(lbl2, 0, 3, 2, 1)

        self.add_button(grid, 0, 4, 1, "Start Oracle VPS Tunnel",
                        self.asl_cmd("remote oracle start"))
        self.add_button(grid, 1, 4, 1, "Stop Oracle VPS Tunnel",
                        self.asl_cmd("remote oracle stop"))
        self.add_button(grid, 0, 5, 1, "Show VPS Configuration",
                        self.asl_cmd("remote oracle config"))
        self.add_button(grid, 1, 5, 1, "Generate Dedicated SSH Keypair",
                        self.asl_cmd("remote oracle gen-key"))
        self.add_button(grid, 0, 6, 1, "Push Public Key to VPS",
                        self.asl_cmd("remote oracle push-pubkey"))
        self.add_button(grid, 1, 6, 1, "Remove Oracle VPS Config & Keys",
                        self.asl_cmd("remote oracle remove"),
                        confirm="Completely remove Oracle VPS configuration and keys?", destructive=True)

        lbl3 = Gtk.Label()
        lbl3.set_markup("<b>Serveo &amp; Ngrok Cloud Tunnels</b>")
        lbl3.set_halign(Gtk.Align.START)
        grid.attach(lbl3, 0, 7, 2, 1)

        self.add_button(grid, 0, 8, 1, "Start Serveo SSH Tunnel",
                        self.asl_cmd("remote serveo start"))
        self.add_button(grid, 1, 8, 1, "Stop Serveo SSH Tunnel",
                        self.asl_cmd("remote serveo stop"))
        self.add_button(grid, 0, 9, 1, "Start Ngrok Tunnel",
                        self.asl_cmd("remote ngrok start"))
        self.add_button(grid, 1, 9, 1, "Rotate Ngrok Token",
                        self.asl_cmd("remote ngrok rotate"))

        box.pack_start(grid, False, False, 6)
        return box

    # ── Tab: Gamepad ─────────────────────────────────────────────────────

    def create_gamepad_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        self.add_button(grid, 0, 0, 1, "Sync Bluetooth & USB Gamepads (/dev/input)",
                        self.asl_cmd("gamepad sync"), suggested=True)
        self.add_button(grid, 1, 0, 1, "Test Gamepad Inputs (jstest/evtest)",
                        self.asl_cmd("gamepad test"))

        box.pack_start(grid, False, False, 6)

        dev_frame = Gtk.Frame(label="Detected Controllers & Input Devices")
        dev_scroll = Gtk.ScrolledWindow()
        dev_scroll.set_min_content_height(120)
        self.gamepad_view = Gtk.TextView()
        self.gamepad_view.set_editable(False)
        self.gamepad_view.set_monospace(True)
        dev_scroll.add(self.gamepad_view)
        dev_frame.add(dev_scroll)
        box.pack_start(dev_frame, True, True, 0)

        btn_rescan = Gtk.Button(label="Rescan Input Devices")
        btn_rescan.connect("clicked", lambda w: self.refresh_gamepads())
        box.pack_start(btn_rescan, False, False, 0)

        return box

    # ── Tab: Dev Suite ───────────────────────────────────────────────────

    def create_dev_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Developer Toolchains &amp; IDEs</b>")
        lbl.set_halign(Gtk.Align.START)
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Check Dev Suite Status",
                        self.asl_cmd("dev-suite status"), suggested=True)
        self.add_button(grid, 1, 1, 1, "Install Python3 Development Suite",
                        self.asl_cmd("dev-suite install python"))

        self.add_button(grid, 0, 2, 1, "Install Node.js & Web Tooling",
                        self.asl_cmd("dev-suite install webdev"))
        self.add_button(grid, 1, 2, 1, "Install Neovim IDE & Git Tools",
                        self.asl_cmd("dev-suite install neovim"))

        self.add_button(grid, 0, 3, 1, "Install Golang Toolchain",
                        self.asl_cmd("dev-suite install go"))
        self.add_button(grid, 1, 3, 1, "Install Rust & Cargo Toolchain",
                        self.asl_cmd("dev-suite install rust"))

        self.add_button(grid, 0, 4, 1, "Install VS Code Server",
                        self.asl_cmd("dev-suite install vscode"))
        self.add_button(grid, 1, 4, 1, "Install Complete Dev Suite (All)",
                        self.asl_cmd("dev-suite install all"))

        box.pack_start(grid, False, False, 6)
        return box

    # ── Tab: Security Audit ──────────────────────────────────────────────

    def create_sec_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Defensive Network &amp; Security Auditing</b>")
        lbl.set_halign(Gtk.Align.START)
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Run Network & Port Security Audit",
                        self.asl_cmd("security-suite audit"), suggested=True)
        self.add_button(grid, 1, 1, 1, "Check Security Toolset Status",
                        self.asl_cmd("security-suite status"))

        self.add_button(grid, 0, 2, 1, "Install Basic Network Tools (Nmap, Netcat, Socat)",
                        self.asl_cmd("security-suite install basic"))
        self.add_button(grid, 1, 2, 1, "Install Full Security Audit Suite (Wireshark/Tshark)",
                        self.asl_cmd("security-suite install full"))

        box.pack_start(grid, False, False, 6)
        return box

    # ── Tab: Maintenance & Snapshots ─────────────────────────────────────

    def create_maint_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        lbl = Gtk.Label()
        lbl.set_markup("<b>Storage Cleanup &amp; System Health</b>")
        lbl.set_halign(Gtk.Align.START)
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Purge Caches & Temp (asl clean)",
                        self.asl_cmd("clean all"),
                        confirm="Purge package and temp caches?")
        self.add_button(grid, 1, 1, 1, "Deep System Clean (asl clean deep)",
                        self.asl_cmd("clean deep"),
                        confirm="Perform deep cleanup of apt caches and logs?", destructive=True)

        self.add_button(grid, 0, 2, 1, "Automated System & Mount Repair",
                        self.asl_cmd("repair all"), suggested=True)
        self.add_button(grid, 1, 2, 1, "Fix Android Storage & Audio Permissions",
                        self.asl_cmd("aid fix"))

        self.add_button(grid, 0, 3, 1, "Kill Orphaned Subsystem Processes",
                        self.asl_cmd("clean-orphans"))
        self.add_button(grid, 1, 3, 1, "Optimize ZRAM & Memory Swappiness",
                        self.asl_cmd("swap optimize"))

        lbl_snap = Gtk.Label()
        lbl_snap.set_markup("<b>Rootfs Snapshot &amp; Backup</b>")
        lbl_snap.set_halign(Gtk.Align.START)
        grid.attach(lbl_snap, 0, 4, 2, 1)

        self.add_button(grid, 0, 5, 1, "List Existing Snapshots",
                        self.asl_cmd("snapshot list"))
        self.add_button(grid, 1, 5, 1, "Create New System Snapshot",
                        self.asl_cmd("snapshot create quick_backup"))

        box.pack_start(grid, False, False, 6)
        return box

    # ── Tab: AI & Background Services ────────────────────────────────────

    def create_services_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(8)

        lbl = Gtk.Label()
        lbl.set_markup("<b>OmniRoute Local AI Model Proxy</b>")
        lbl.set_halign(Gtk.Align.START)
        grid.attach(lbl, 0, 0, 2, 1)

        self.add_button(grid, 0, 1, 1, "Start OmniRoute AI Proxy",
                        self.asl_cmd("omniroute start"), suggested=True)
        self.add_button(grid, 1, 1, 1, "Stop OmniRoute AI Proxy",
                        self.asl_cmd("omniroute stop"))
        self.add_button(grid, 0, 2, 1, "Check OmniRoute Status",
                        self.asl_cmd("omniroute status"))
        self.add_button(grid, 1, 2, 1, "View OmniRoute Proxy Logs",
                        self.asl_cmd("omniroute logs"))

        lbl_svc = Gtk.Label()
        lbl_svc.set_markup("<b>Subsystem Boot &amp; Daemon Services</b>")
        lbl_svc.set_halign(Gtk.Align.START)
        grid.attach(lbl_svc, 0, 3, 2, 1)

        self.add_button(grid, 0, 4, 1, "Check Running Background Services",
                        self.asl_cmd("service check"))
        self.add_button(grid, 1, 4, 1, "Restart Background Services",
                        self.asl_cmd("service restart"))
        self.add_button(grid, 0, 5, 1, "Enable Boot Autostart Service",
                        self.asl_cmd("service enable"))
        self.add_button(grid, 1, 5, 1, "Disable Boot Autostart Service",
                        self.asl_cmd("service disable"))

        box.pack_start(grid, False, False, 6)
        return box

    def on_destroy(self, widget):
        self.save_state()
        Gtk.main_quit()


if __name__ == "__main__":
    app = ASLHubWindow()
    app.connect("destroy", app.on_destroy)
    app.show_all()
    Gtk.main()
