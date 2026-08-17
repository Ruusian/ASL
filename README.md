# 🚀 Android Subsystem for Linux (ASL)

[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Termux-brightgreen.svg)](https://termux.dev)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64-blue.svg)](#)
[![Requirement](https://img.shields.io/badge/Requirements-Root%20(su)%20%2B%20Termux-red.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GPU Acceleration](https://img.shields.io/badge/GPU-Mesa%20Turnip%20%7C%20Zink%20%7C%20VirGL-orange.svg)](#)

**Android Subsystem for Linux (ASL)** is a high-performance, root-accelerated Linux chroot management subsystem, gaming container framework, and Android host bridge for ARM64 devices.

Modeled after **WSL (Windows Subsystem for Linux)** on PC, **ASL** transforms your Android smartphone or tablet into a full Linux workstation and gaming environment using **Root (`su`)** and **Termux**.

---

```text
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                   ANDROID SUBSYSTEM FOR LINUX (ASL)                     │
 ├─────────────────────────────────────────────────────────────────────────┤
 │                                                                         │
 │  ┌───────────────────────────────────────────────────────────────────┐  │
 │  │                  Debian Trixie ARM64 Subsystem                    │  │
 │  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────────┐  │  │
 │  │  │ XFCE Desktop │  │ Box64 / Wine │  │ Turnip / Zink / DXVK    │  │  │
 │  │  └──────────────┘  └──────────────┘  └─────────────────────────┘  │  │
 │  └───────────────────────────────────▲───────────────────────────────┘  │
 │                                      │ Direct Hardware Acceleration     │
 │  ┌───────────────────────────────────┴───────────────────────────────┐  │
 │  │                 Android Kernel & Hardware Layers                  │  │
 │  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────────┐  │  │
 │  │  │ /dev/kgsl-3d0│  │ Audio / Pulse│  │ Storage & Android AID   │  │  │
 │  │  └──────────────┘  └──────────────┘  └─────────────────────────┘  │  │
 │  └───────────────────────────────────────────────────────────────────┘  │
 └─────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Installation

Install or update **ASL** with a single command inside Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash
```

> ⚠️ **Trust note:** Piping a remote script into `bash` executes it with your current
> privileges. Review [`install.sh`](install.sh) before running — it installs Termux
> packages, requires root (`su`), and downloads a prebuilt rootfs (checksum-verified
> for the modded edition; see the `SHA256SUMS` sidecar). For an auditable install,
> clone the repo first: `git clone https://github.com/Ruusian5/ASL && cd ASL && bash install.sh`.

### 🐧 Distro & Image Options
Select your preferred Debian rootfs edition interactively during setup, or pass non-interactive flags:

```bash
# ASL Modded Rootfs (Pre-configured Turnip Vulkan, Box64, Wine64, XFCE Desktop):
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash -s -- --modded

# Standard Clean Base Rootfs (Official Debian Trixie via proot-distro):
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash -s -- --standard
```

After installation, launch the interactive 3D console anytime:
```bash
asl
```

---

## 🔥 Key Features & Capabilities

### 🛡️ 1. Zero-Crash Isolated Subsystem Core
- **100% Native Kernel Performance**: Unlike PRoot (which intercepts system calls via `ptrace`), ASL mounts Linux chroots directly using native root kernel privileges (`su`).
- **Strict Mount Isolation**: Enforces private bind mounts (`--make-rprivate` and `--make-rslave`) without mounting host Android system partitions (`/system`, `/vendor`, `/apex`, `/linkerconfig`). Eliminates SELinux panics, mount deadlocks, and host OS kernel crashes.

### 🎮 2. Direct3D 11/12 Hardware Acceleration & Gaming Engine
- **Turnip Mesa Vulkan Drivers**: Native Turnip driver profile support for Qualcomm Adreno 6xx/7xx GPUs and Zink OpenGL-over-Vulkan. DXVK can be installed per Wine prefix with Winetricks; VKD3D is not installed or configured automatically.
- **VirGL Fallback Support**: Automatic fallback driver selection for Mali, PowerVR, and generic GPU hardware.
- **Tuned Box64 + Wine64 Pipeline**: Pre-configured Box64 dynarec stability flags (`/etc/box64.box64rc`), automated Wine process lifecycle management (`wineserver -k`), and working directory auto-resolution.
- **VFS Cache & Memory Optimization**: Tuned VM swappiness, dirty ratio, VFS cache pressure, and `/dev/shm` tmpfs Mesa shader caching to eliminate micro-stuttering.

### 📱 3. Deep Android Host & Termux Bridge
- **Android AID (Android ID) Mapping**: Automatically maps host GIDs (`aid_graphics`, `aid_audio`, `aid_sdcard_rw`, `aid_gpu_service`, `aid_inet`) inside the Linux chroot so applications have direct hardware access to GPU device nodes, audio sockets, and `/sdcard`.
- **Root Manager Integration**: Magisk / KernelSU / APatch action module (`module/action.sh`) for starting or stopping ASL directly from root manager dashboards.
- **Bi-Directional Host Services**:
  - 🔒 **CPU WakeLock**: Prevents Android deep sleep during long builds or background operations (`asl wakelock on`).
  - 🔗 **Host File & URL Launcher**: Opens Linux files or web links directly in native Android apps (`asl open <path|url>`).
  - 📋 **System Clipboard Bridge**: Syncs clipboard contents between Linux and Android (`asl clip copy/paste`).
  - 🔔 **Android System Toasts & Notifications**: Triggers native Android system toasts and notifications from Linux scripts (`asl toast "Task Done"`).

### 🌡️ 4. Multi-Zone Thermal & Battery Monitoring
- Real-time diagnostic reporting for battery temperature and SoC thermal sensors (`CPU`, `GPU`, `TSENS`, `quiet-therm`) across Qualcomm Snapdragon, Samsung Exynos, and MediaTek platforms (`asl thermal`).

### 📸 5. Point-in-Time Filesystem Snapshots & Backups
- **Instant Snapshots**: Create instant snapshots (`asl snapshot create <name>`) and safely restore chroot state in seconds.
- **Rollback Safety**: Includes automated rollback protection and disk headroom validation prior to backup operations.

### 🖥️ 6. Interactive 3D TUI Console
- Feature-rich terminal interface with 3D drop-shadow banners, categorized card grid layout, real-time telemetry (RAM, Swap, CPU temp, battery, load, host IP, X11 status, WakeLock), and single-letter hotkeys.

---

## 📚 Dedicated Documentation & Tracking

Detailed tracking, guides, and technical specifications are available in the [`docs/`](docs/) directory:

- 🏗️ **[Architecture & Invariants](docs/ARCHITECTURE.md):** Deep-dive into chroot mounting, hardware driver stack, and process spawning invariants (`os.posix_spawn`).
- 🎮 **[Gaming & Wine Isolation Guide](docs/GAMING_GUIDE.md):** Wine prefix auto-resolution, DXVK/VKD3D setup, FSR resolution scaling, Steam runner, and backup tools.
- ⚡ **[Performance & Audio Tuning](docs/PERFORMANCE_TUNING.md):** CPU governor boost, PulseAudio low-latency buffers, Box64 dynarec profiles, and RAM compaction.
- 🛠️ **[CLI & Utilities Reference](docs/CLI_AND_UTILITIES.md):** Full `asl` CLI subcommand table and utility scripts.
- 🗺️ **[Roadmap & Feature Tracking](docs/ROADMAP_AND_TRACKING.md):** Progress tracking, planned enhancements, and architectural invariants.

---

## 📦 Repository Structure

```text
ASL/
├── install.sh            # Automated setup script with distro selection & driver setup
├── bin/
│   ├── asl               # Main 3D CLI entrypoint & interactive TUI dashboard
│   └── superkit          # Alternative entrypoint symlink
├── core/
│   ├── mount-chroot.sh   # Safe isolated chroot mount manager
│   ├── stop-chroot.sh    # Safe unmount & process termination manager
│   ├── doctor.sh         # Environment pre-flight check & diagnostics
│   ├── gpu-detect.sh     # Hardware SoC auto-detection & profile selection
│   ├── gpu-profile.sh    # Mesa Turnip / Zink / VirGL environment profile manager
│   ├── thermal.sh        # SoC & battery thermal sensor diagnostic monitor
│   ├── termux-bridge.sh  # WakeLock, open, clipboard, and notification bridge
│   ├── android-aid.sh    # Android AID GID group mapper
│   └── snapshot.sh       # Point-in-time chroot snapshot & backup manager
├── gaming/
│   └── wine-box64.sh     # Wine64, Box64 & Windows app execution manager (DXVK via Winetricks)
├── desktop/
│   ├── start-desktop.sh  # Termux:X11 desktop session & PulseAudio launcher
│   ├── theme.sh          # GTK theme & icon set switcher
│   └── remote.sh         # OpenSSH (port 2222) & x11vnc (port 5900) bridge
└── module/
    ├── action.sh         # KernelSU / Magisk / APatch UI action handler
    └── module.prop       # Root module metadata properties
```

---

## 🛠️ Complete Command Reference

### 1. Interactive Console & Telemetry
| Command | Description |
| :--- | :--- |
| `asl` | Open the main 3D terminal dashboard |
| `asl overview` | Print concise live system status without dashboard |
| `asl thermal` | Monitor battery and CPU/GPU thermal zone temperatures |
| `asl doctor` | Run environment pre-flight diagnostics |

### 2. Core Linux Subsystem Operations
| Command | Description |
| :--- | :--- |
| `asl start` | Safely mount Linux chroot environment |
| `asl shell` | Enter root bash session inside chroot |
| `asl exec <cmd>` | Execute a command inside chroot |
| `asl status` | Inspect mount points, chroot storage, and process state |
| `asl stop` | Safely terminate GUI sessions and unmount chroot |
| `asl install <pkgs>` | Install packages inside chroot via `apt-get` |
| `asl search <query>` | Search available apt repositories |
| `asl service <action> <svc>` | Manage background services (`start|stop|restart|status`) |
| `asl snapshot create <name>` | Create instant point-in-time snapshot |
| `asl snapshot list` | List available chroot snapshots |
| `asl snapshot restore <name>`| Restore chroot state from snapshot |
| `asl backup` | Create compressed backup archive |
| `asl restore <file>` | Restore chroot from backup archive |
| `asl aid setup` | Map Android host AID GIDs inside chroot |

### 3. MoBox Gaming & Direct3D Engine
| Command | Description |
| :--- | :--- |
| `asl gpu` | Display active Turnip/Mesa GPU hardware runtime profile |
| `asl mode [gaming\|performance\|balanced]` | Apply memory compaction & Turnip GPU tuning |
| `asl setup-gaming` | Auto-install Wine64, Box64, and gaming tooling; install DXVK per Wine prefix via Winetricks (VKD3D is not auto-installed) |
| `asl game` | Open interactive gaming menu |
| `asl game run <exe>` | Execute Windows application via Box64 + Wine64 |

### 4. Termux-X11 Desktop & Remote Services
| Command | Description |
| :--- | :--- |
| `asl desktop start` | Launch hardware-accelerated XFCE4 desktop |
| `asl desktop status` | Inspect active desktop session state |
| `asl desktop stop` | Terminate current desktop session safely |
| `asl desktop restart` | Force-stop and restart desktop environment |
| `asl desktop sync-apps` | Sync Debian app shortcuts to Termux |
| `asl theme [dark\|light\|nord\|dracula]` | Switch GTK theme presets |
| `asl resolution [720p\|1080p\|native]` | Configure Termux:X11 display resolution |
| `asl remote ssh [start\|stop\|status]` | Manage SSH server (port 2222) |
| `asl remote vnc [start\|stop\|status]` | Manage x11vnc server (port 5900) |
| `asl audio [start\|stop\|test]` | PulseAudio server management |

### 5. Termux & Android Host Bridge
| Command | Description |
| :--- | :--- |
| `asl wakelock [on\|off\|status]` | Control CPU WakeLock state |
| `asl open <file\|url>` | Open file or URL in default Android host app |
| `asl clip [copy\|paste]` | Read or write Android system clipboard |
| `asl toast <msg>` | Send Android toast notification |
| `asl notify <title> <msg>` | Send Android notification banner |

---

## 🔒 Safety & Isolation Guarantees

Standard chroot scripts often execute `mount --bind / /chroot` or bind Android system folders (`/system`, `/vendor`, `/apex`). On Android 10 through 15+, this causes SELinux violations, mounting deadlocks, broken camera/audio daemons, and kernel panics.

**Android Subsystem for Linux (ASL)** enforces strict mount isolation:
- Shared access is provided strictly for user storage (`/sdcard`), device nodes (`/dev`, restricted to 0660/input-group), and IPC sockets (`/tmp`).
- Mount points use `--make-rprivate` and `--make-rslave` flags to prevent mount events from leaking into the host Android OS.
- No host system partitions (`/system`, `/vendor`, `/apex`) are mounted into the chroot, so host OS stability is not threatened by chroot activity.

> ⚠️ **Note:** ASL runs with root privileges and tunes a few *host-wide* kernel parameters (`vm.swappiness`, `vm.vfs_cache_pressure`, `vm.dirty_ratio`, `vm.dirty_background_ratio`, `vm.max_map_count`) for performance. These are backed up and restored on `asl stop`, but they are host-level changes, not chroot-scoped — treat ASL as a powerful tool with root access, not as a sandbox.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for details.

