# ASL Changelog

All notable changes to the ASL (Android Subsystem for Linux) project are documented in this file.

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
