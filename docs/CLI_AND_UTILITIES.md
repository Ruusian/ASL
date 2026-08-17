# ASL CLI & Utilities Reference

## Main CLI Dispatcher (`asl`)
The `asl` binary in `/usr/local/bin/asl` serves as the unified entry point for all ASL operations.

### Subcommands
| Command | Subcommand / Syntax | Description |
| :--- | :--- | :--- |
| **Interactive GUI** | `asl gui` or `asl -g` | Launches the GTK3 Python graphical manager dashboard (`asl-gui`). |
| **Gaming Hub** | `asl hub` or `asl launcher` | Launches the terminal menu launcher (`asl-gaming-hub`). |
| **Game Executable** | `asl game <path_to_exe>` | Runs a Windows executable via `asl-wine-launch`. |
| **DXVK Auto-Installer** | `asl dxvk [enable\|disable\|status]` | Configures Direct3D DXVK / VKD3D overrides for the target Wine prefix. |
| **Steam Integration** | `asl steam [args...]` | Launches Steam client or Windows installer with Box64 flags. |
| **Save & Prefix Backup** | `asl backup [save\|restore\|list]` | Manages compressed game save and Wine prefix backups. |
| **Gamepad Config** | `asl gamepad` | Opens Wine `joy.cpl` joystick setup tool. |
| **Wine Configuration** | `asl winecfg` | Opens `winecfg` graphical control panel. |
| **Performance Boost** | `asl boost` | Executes CPU governor, OOM score, and memory compaction boost. |
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
