# ASL CLI & Utilities Reference

## Main CLI Dispatcher (`asl`)
The `asl` binary in `/usr/local/bin/asl` (and linked to Termux `$PREFIX/bin/asl`) serves as the unified entry point for all ASL operations.

### Subcommands
| Command | Subcommand / Syntax | Description |
| :--- | :--- | :--- |
| **Execution Mode** | `asl exec-mode [root\|shizuku\|proot\|status]` | Inspects or switches execution mode between Root (`su`), Shizuku (`rish`), and PRoot. |
| **Setup Wizard** | `asl wizard` or `asl init` | Guided first-time setup wizard for Gaming, Dev, Security, or Full Workstation presets. |
| **Interactive GUI** | `asl hub` or `asl gui` | Launches the GTK3 Python Control Center dashboard ("ASL Hub"). |
| **Wine Bundles** | `asl wine-bundle [install\|status\|clean]` | Manages offline Wine Mono (.NET) & Wine Gecko (MSHTML) MSI bundles. |
| **Wine Engine Manager**| `asl wine-version [status\|set\|install]` | Switches active Wine engine between Debian system-wine and Proton-GE. |
| **Box64 Dynarec Precision** | `asl game precision [safe\|fast\|status]` | Switch Box64 dynarec profile between Max FPS (Fast) and High Precision/Compatibility (Safe). |
| **Bluetooth Gamepad** | `asl gamepad [status\|sync\|test]` | Synchronizes and tests host `/dev/input` evdev gamepads into chroot. |
| **Dev Suite** | `asl dev-suite [install\|status]` | Installs IDE & dev toolchain (Python, Node, Go, Rust, Neovim, VS Code). |
| **Security Audit** | `asl security-suite [install\|status]` | Deploys containerized defensive security auditing tools (Nmap, Wireshark, etc.). |
| **Storage Cleaner** | `asl clean [all\|apt\|tmp\|cache]` | Purges package archives, temporary files, and Mesa shader caches. |
| **System Repair** | `asl repair [all\|mounts\|permissions\|dpkg]` | Runs automated repair for mounts, lock files, and system permissions. |
| **Game Executable** | `asl game <path_to_exe>` | Runs a Windows executable via `asl-wine-launch`. |
| **DXVK Auto-Installer** | `asl dxvk [enable\|disable\|status]` | Configures Direct3D DXVK / VKD3D overrides for target Wine prefix. |
| **Steam Integration** | `asl steam [args...]` | Launches Steam client or Windows installer with Box64 flags. |
| **Save & Prefix Backup** | `asl backup [save\|restore\|list]` | Manages compressed game save and Wine prefix backups. |
| **24/7 Service Manager** | `asl service [start\|stop\|restart\|check\|loop\|enable\|disable\|status]` | Controls background services, Termux:Boot autostart, and health watchdog. |
| **OmniRoute AI Proxy** | `asl omniroute [start\|stop\|restart\|logs\|status]` | Manages root-isolated OmniRoute AI proxy on port 20128. |
| **Virtual Swap Manager** | `asl swap [status\|create\|enable\|disable\|remove\|auto]` | Controls virtual swap allocation with 5GB safety bounds. |
| **Performance HUD** | `asl hud [on\|off\|toggle\|status]` | Toggles MangoHud & DXVK_HUD telemetry overlay. |
| **Orphan Process Killer** | `asl orphan-killer` | Terminates stranded subsystem processes and background leaks. |
| **Interactive Shell** | `asl shell` or `asl` | Drops into target Linux subsystem rootfs bash shell. |

---

## One-Line Installer Flags (`install.sh`)
The automated installer supports non-interactive execution flags:

### Distribution Selection Flags
- `--modded`: Installs pre-configured Debian Modded rootfs (Turnip Mesa Vulkan, Box64, Wine64, XFCE).
- `--debian` / `--standard`: Installs official Debian Trixie clean base.
- `--ubuntu`: Installs official Ubuntu 24.04 LTS base.
- `--arch`: Installs official Arch Linux base.
- `--alpine`: Installs official Alpine Linux base.
- `--kali`: Installs official Kali Linux base.
- `--distro=<name>` / `--type=<name>`: Specifies target distro edition explicitly.

### Execution Mode Flags
- `--root`: Enforces Root (`su`) kernel chroot mode.
- `--shizuku`: Enforces Shizuku (`rish`) ADB-privileged mode.
- `--proot`: Enforces PRoot user-space emulation mode.
- `--mode=<mode>`: Sets target execution mode.

---

## Core Infrastructure Scripts
All core helper scripts reside in `core/`, `desktop/`, `gaming/`, and `$PREFIX/share/asl/`:

- `core/common.sh`: Shared environment module (`asl_detect_mode`, `asl_exec`, `asl_chroot_exec`, `is_mounted`).
- `core/mount-chroot.sh`: Safe mount manager with `trap cleanup_on_error ERR` rollback handler.
- `core/stop-chroot.sh`: Chroot process termination & unmount manager.
- `core/service-manager.sh`: 24/7 background service manager, boot autostart, and watchdog daemon.
- `core/swap-manager.sh`: Virtual swapfile creation and zRAM detection engine.
- `core/cleaner.sh`: Container cache and storage purger.
- `core/repair.sh`: Self-healing integrity repair suite.
- `core/wizard.sh`: Interactive first-time setup wizard module.
- `desktop/asl-hub-installer.sh`: Python3 + GTK3 desktop launcher installer (`os.posix_spawn` invariant).
- `desktop/remote.sh`: Modular remote bridge dispatcher (LAN SSH, Oracle VPS, Serveo, Ngrok).
- `gaming/wine-box64.sh`: Wine64, Box64, and Dynarec precision profile switcher.
