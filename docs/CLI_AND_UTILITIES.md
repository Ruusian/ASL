# ASL CLI & Utilities Reference

## Main CLI Dispatcher (`asl`)
The `asl` binary in `/usr/local/bin/asl` serves as the unified entry point for all ASL operations.

### Subcommands
| Command | Subcommand / Syntax | Description |
| :--- | :--- | :--- |
| **Interactive GUI** | `asl hub` or `asl gui` | Launches the GTK3 Python Control Center dashboard ("ASL Hub"). |
| **Wine Bundles** | `asl wine-bundle [install\|status\|clean]` | Manages offline Wine Mono (.NET) & Wine Gecko (MSHTML) MSI bundles. |
| **Wine Engine Manager**| `asl wine-version [status\|set\|install]` | Switches active Wine engine between Debian system-wine and Proton-GE. |
| **Bluetooth Gamepad** | `asl gamepad [status\|sync\|test]` | Synchronizes and tests host `/dev/input` evdev gamepads into chroot. |
| **Dev Suite** | `asl dev-suite [install\|status]` | Installs IDE & dev toolchain (Python, Node, Go, Rust, Neovim, VS Code). |
| **Security Audit** | `asl security-suite [install\|status]` | Deploys containerized defensive security auditing tools (Nmap, Wireshark, etc.). |
| **Storage Cleaner** | `asl clean [all\|apt\|tmp\|cache]` | Purges package archives, temporary files, and Mesa shader caches. |
| **System Repair** | `asl repair [all\|mounts\|permissions\|dpkg]` | Runs automated repair for mounts, lock files, and system permissions. |
| **Game Executable** | `asl game <path_to_exe>` | Runs a Windows executable via `asl-wine-launch`. |
| **DXVK Auto-Installer** | `asl dxvk [enable\|disable\|status]` | Configures Direct3D DXVK / VKD3D overrides for target Wine prefix. |
| **Steam Integration** | `asl steam [args...]` | Launches Steam client or Windows installer with Box64 flags. |
| **Save & Prefix Backup** | `asl backup [save\|restore\|list]` | Manages compressed game save and Wine prefix backups. |
| **Interactive Shell** | `asl shell` or `asl` | Drops into Debian rootfs bash shell. |

---

## Utility Scripts Index
All utility scripts reside in `/usr/local/bin/` inside the Debian rootfs:

- `/usr/local/bin/asl-gui`: Native GTK3 Python application manager (uses `os.posix_spawn` invariant).
- `/usr/local/bin/asl-gaming-hub`: Terminal-based launcher dashboard.
- `/usr/local/bin/asl-wine-launch`: Wine binary & Vulkan/Zink execution wrapper.
- `/usr/local/bin/asl-dxvk-setup`: DXVK / VKD3D registry configuration script.
- `/usr/local/bin/asl-steam`: Steam environment runner.
- `/usr/local/bin/asl-backup`: Game save and prefix archiver.
- `/usr/local/bin/asl-boost`: Power and memory optimization script.
