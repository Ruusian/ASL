# ASL Changelog

All notable changes to the ASL (Android Subsystem for Linux) project are documented in this file.

## [1.5] - 2026-08-17

### 🚀 Architecture, Robustness & User Experience Enhancements

- **Guided First-Time Setup Wizard (`asl wizard` / `asl init`)**:
  - Implemented `core/wizard.sh` providing guided interactive setup for 4 work presets (Gaming Workstation, Software Developer, Security Auditing, Full Workstation) and Termux:X11 display resolution configuration.
  - Added option 25 `[z]` to terminal dashboard and CLI subcommand dispatching.

- **Shared Environment & Helper Library (`core/common.sh`)**:
  - Consolidated path validation, mount checks, color codes, and status logging into shared helper module.

- **Automated Mount Cleanup Rollback (`core/mount-chroot.sh`)**:
  - Implemented `ERR` signal trap inside mount manager to roll back partial chroot mounts if mounting fails midway.

- **Box64 Dynarec Precision Profile Switcher (`asl game precision`)**:
  - Added `asl game precision [safe|fast|status]` subcommand to toggle between maximum FPS (Fast) and high precision calculation modes (Safe/Accurate).

- **DRM Render Node Hardware Detection (`core/gpu-profile.sh`)**:
  - Added DRM render node detection (`/dev/dri/renderD128`, `/dev/dri/card0`) to extend Turnip Vulkan auto-profiling for newer Snapdragon SoCs.

- **Loopback Default for Remote VNC (`desktop/remote.sh`)**:
  - Updated `x11vnc` default binding to `127.0.0.1:5900` to ensure local isolation unless explicit public access is specified.

- **Non-Interactive Scripting & Diagnostic Log Surfacing (`bin/asl`)**:
  - Supported `--yes` / `-y` flags across CLI commands for automated background execution (Tasker/MacroDroid).
  - Added automatic diagnostic log surfacing from `/tmp/app_launch.log` on application startup failures.


## [1.4] - 2026-08-17

### 🚀 New Features & Desktop GTK3 Control Center

- **Native Debian GTK3 Control Center ("ASL Hub")**:
  - Installed `/usr/local/bin/asl-control-center` inside Debian rootfs with shortcuts in `/usr/share/applications/asl-hub.desktop` and directly on `/root/Desktop/asl-hub.desktop`.
  - Built with GTK3 Python using `os.posix_spawn` process creation to strictly prevent multithreading GTK3 deadlocks (Architecture Invariant #1).
  - Provides full GUI control over GPU profiles, MangoHud, Wine/Proton engines, Gamepad passthrough, Dev Suite, Security Suite, and System Maintenance.

- **Offline Wine Mono & Gecko Bundle Installer (`asl wine-bundle`)**:
  - Implemented `core/wine-bundle.sh` to package offline `.msi` installers for games requiring .NET framework or MSHTML.

- **Wine & Proton-GE Version Manager (`asl wine-version`)**:
  - Implemented `core/wine-version.sh` for seamless switching between system Wine and Proton-GE engines.

- **Bluetooth Gamepad Passthrough (`asl gamepad`)**:
  - Implemented `core/gamepad.sh` for evdev device detection (`/dev/input/event*`) and chroot input node mapping.

- **IDE & Dev Environment Suite (`asl dev-suite`)**:
  - Implemented `core/dev-suite.sh` with one-click presets for VS Code Server, Neovim, Python3, Node.js, Go, and Rust.

- **Defensive Security & Audit Suite (`asl security-suite`)**:
  - Implemented `core/security-suite.sh` for containerized network auditing (Nmap, Wireshark/TShark, Netcat, Socat, Hydra).

- **Storage Cleaner & Integrity Repair (`asl clean` & `asl repair`)**:
  - Implemented `core/cleaner.sh` and `core/repair.sh` for safe storage cache purging, DPKG lock recovery, and mount point repair.

---

## [1.3] - 2026-08-17

### 🚀 New Features

- **MangoHud & DXVK_HUD Performance Overlay Manager (`asl hud`)**:
  - Introduced `core/hud.sh` and `asl hud [on|off|toggle|status]` CLI subcommands.
  - Automatically exports `DXVK_HUD` and `MANGOHUD` environment configurations into GPU profiles and Wine/Box64 gaming launches.
  - Real-time FPS, CPU/GPU temperature, RAM/VRAM telemetry overlay.

---

## [1.2] - 2026-08-17

### 🔒 Security & Subshell Execution Fixes

- **CRITICAL**: Replaced unsafe `eval "nohup $EXEC_CMD ..."` calls in `bin/asl` and `gaming/wine-box64.sh` with explicit bash subshell execution (`nohup /bin/bash -c "$EXEC_CMD"`).
- **HIGH**: Added robust string path escaping with `printf '%q'` for snapshot export/import operations in `core/snapshot.sh` and XML theme configuration files in `desktop/theme.sh`.
- **HIGH**: Added regex escaping for `/`, `&`, and `|` in `desktop/theme.sh` (`esc_val=$(printf '%s\n' "$val" | sed -e 's/[\/&|]/\\&/g')`) to prevent `sed` XML replacement corruption.

### ⚙️ Mount Isolation & Robustness Improvements

- **CRITICAL**: Standardized mount point matching across all scripts (`bin/asl`, `core/*.sh`, `desktop/*.sh`, `gaming/*.sh`, `module/action.sh`, `install.sh`) using exact space-padded `/proc/mounts` column matching (`grep -q -F " $target " /proc/mounts`).
- **HIGH**: Implemented dynamic reverse path-length depth unmounting in `core/stop-chroot.sh` (`awk '{ print length, $0 }' | sort -rn`) to ensure child virtual filesystems (`binfmt_misc`, `/dev/pts`, `/dev/shm`, `/tmp`) are unmounted before parent directories.
- **MEDIUM**: Added missing chroot mount verification before prebuilt GPU driver auto-installation in `core/gpu-profile.sh`.

---

## [1.1] - 2026-08-16

### 🔒 Security Fixes

- **CRITICAL**: Fixed unquoted variables in `core/mount-chroot.sh` (Lines 78-96)
  - Changed all `$DEBIANPATH` references to `"$DEBIANPATH"` to prevent shell word splitting and injection attacks
  - Impact: Eliminates potential code injection vectors when paths contain special characters

### ⚙️ Robustness Improvements

- **MEDIUM**: Added process existence validation before termination in `bin/asl` process_manager
  - Added `kill -0 "$target_pid"` check to prevent race conditions when PIDs are recycled
  - Impact: Prevents accidental termination of unrelated processes

- **MEDIUM**: Added command size validation in `bin/asl` run_in_chroot function
  - Implemented 40KB limit check for base64-encoded commands
  - Impact: Gracefully handles oversized commands with clear error messages

### 🐛 Code Quality

- **LOW**: Fixed file descriptor management in `desktop/start-desktop.sh`
  - Changed from implicit stdin to explicit FD 3 in read loop (`read -r -u 3` with `done 3< "$STATE_FILE"`)
  - Impact: Cleaner FD handling, prevents conflicts with stdin redirection

### 📖 User Experience Enhancements

- **LOW**: Enhanced error messages in `core/mount-chroot.sh`
  - Added actionable troubleshooting steps when Debian rootfs is not found
  - Added installation command suggestions

- **LOW**: Enhanced error messages in `core/stop-chroot.sh`
  - Added 4-step diagnostic guide when unmount operations fail
  - Provides specific commands for force unmount and process detection

### ✅ Verified Secure

- Confirmed `core/snapshot.sh` safe_name() regex properly prevents path traversal attacks
- Verified package name validation regex follows Debian standards (supports packages like gcc++-11)
- Confirmed hardcoded `/data/local/tmp/chrootDebian` path is intentional for security

### 📋 Documentation

- Added comprehensive [BUG_REPORT.md](BUG_REPORT.md) documenting all 9 identified issues and resolutions
- Added detailed [FIXES_APPLIED.md](FIXES_APPLIED.md) with code examples and testing procedures

---

## [1.0] - Previous Release

Initial stable release with core functionality for ASL chroot management.

---

## How to Report Issues

Found a bug? Please open an issue on [GitHub](https://github.com/Ruusian5/ASL/issues) with:
1. ASL version (`asl --version`)
2. Device info (Android version, Termux version)
3. Steps to reproduce
4. Expected vs actual behavior

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

**Maintained by**: [@Ruusian5](https://github.com/Ruusian5)
