# ASL CLI & Utilities Reference

## Main CLI Dispatcher (`asl`)
The `asl` binary in `$PREFIX/bin/asl` (and `$PREFIX/share/asl/bin/asl`) serves as the unified entry point for all ASL operations.

### Subcommands
| Command | Subcommand / Syntax | Description |
| :--- | :--- | :--- |
| **Interactive Dashboard** | `asl` or `asl dashboard` | Launches 74-column DEC 1049 alternate-screen buffer TUI console. |
| **System Overview** | `asl overview` | Displays concise live system status and remote endpoint table. |
| **Execution Mode** | `asl exec-mode [root\|shizuku\|proot\|status]` | Inspects or switches execution mode between Root (`su`), Shizuku (`rish`), and PRoot. |
| **Setup Wizard** | `asl wizard` or `asl init` | Guided first-time setup wizard for Gaming, Dev, Security, or Full Workstation presets. |
| **Interactive GUI Hub** | `asl hub` or `asl gui` | Launches the GTK3 Python Control Center dashboard ("ASL Hub") inside XFCE4. |
| **Wine Bundles** | `asl wine-bundle [install\|status\|clean]` | Manages offline Wine Mono (.NET) & Wine Gecko (MSHTML) MSI bundles. |
| **Wine Engine Manager**| `asl wine-version [status\|set\|install]` | Switches active Wine engine between Debian system-wine and Proton-GE. |
| **Box64 Dynarec Precision** | `asl game precision [safe\|fast\|status]` | Switch Box64 dynarec profile between Max FPS (Fast) and High Precision/Compatibility (Safe). |
| **Bluetooth Gamepad** | `asl gamepad [status\|sync\|test]` | Synchronizes and tests host `/dev/input` evdev gamepads into chroot. |
| **Dev Suite** | `asl dev-suite [install\|status]` | Installs IDE & dev toolchain (Python, Node, Go, Rust, Neovim, VS Code). |
| **Security Audit** | `asl security-suite [install\|status]` | Deploys containerized defensive security auditing tools (Nmap, Wireshark, etc.). |
| **Storage Cleaner** | `asl clean [status\|all\|apt\|tmp\|cache]` | Purges package archives, temporary files, and Mesa shader caches. |
| **System Repair** | `asl repair [all\|mounts\|permissions\|dpkg\|env\|libs]` | Runs automated repair for mounts, lock files, permissions, and D-Bus. |
| **Game Executable** | `asl game <path_to_exe>` | Runs a Windows executable via `asl-wine-launch` and Box64. |
| **DXVK Configuration** | `asl dxvk [enable\|status]` | Configures Direct3D DXVK / VKD3D async shader translation. |
| **Subsystem Backup** | `asl backup` | Creates full compressed archive of the subsystem rootfs. |
| **Subsystem Restore**| `asl restore [archive]` | Restores subsystem rootfs from a backup archive. |
| **Point-in-Time Snapshots** | `asl snapshot [list\|create\|restore\|delete\|export\|import]` | Manages fast point-in-time snapshots and export/import. |
| **24/7 Service Manager** | `asl service [start\|stop\|restart\|check\|loop\|enable\|disable\|status]` | Controls background services, Termux:Boot autostart, and health watchdog. |
| **OmniRoute AI Proxy** | `asl omniroute [start\|stop\|restart\|logs\|status]` | Manages root-isolated OmniRoute AI proxy on port 20128. |
| **Virtual Swap Manager** | `asl swap [status\|setup\|optimize\|cleanup]` | Controls virtual swap allocation with 5GB safety bounds. |
| **Performance HUD** | `asl hud [on\|off\|toggle\|status]` | Toggles MangoHud & DXVK_HUD telemetry overlay. |
| **Thermal Diagnostics**| `asl thermal [watch]` | Monitors SoC, CPU, GPU, and battery thermal sensors. |
| **Process Manager** | `asl ps` | Interactive process viewer and termination manager. |
| **Path Translation** | `asl path [-u\|-a\|-c\|-m] <path>` | Translates paths between Android host and Linux container. |
| **Declarative Config**| `asl config [show\|init\|get\|set]` | Manages system declarative configuration in `/etc/asl.conf`. |
| **Android Host Bridge**| `asl wakelock\|open\|clip\|toast\|shortcut\|storage` | Android host integration bridges. |
| **Interactive Shell** | `asl shell [user]` | Drops into target Linux subsystem rootfs bash login shell. |

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
- `core/stop-chroot.sh`: Subsystem process termination & unmount manager.
- `core/service-manager.sh`: 24/7 background service manager, boot autostart, and watchdog daemon.
- `core/swap-manager.sh`: Virtual swapfile creation, memory compaction, and zRAM detection engine.
- `core/cleaner.sh`: Container cache and storage purger.
- `core/repair.sh`: Self-healing integrity repair suite.
- `core/wizard.sh`: Interactive first-time setup wizard module.
- `core/asl-conf.sh`: Declarative `/etc/asl.conf` configuration manager.
- `core/asl-path.sh`: Host <-> Subsystem path translation utility.
- `core/termux-bridge.sh`: Android host bridge (wakelock, clipboard, notifications, shortcuts).
- `desktop/asl-hub-installer.sh`: Python3 + GTK3 desktop launcher installer (`os.posix_spawn` invariant).
- `desktop/remote.sh`: Modular remote bridge dispatcher (LAN SSH, Oracle VPS, Serveo, Ngrok).
- `gaming/wine-box64.sh`: Wine64, Box64, and Dynarec precision profile switcher.
