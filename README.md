# 🚀 Android Subsystem for Linux (ASL)

[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Termux-brightgreen.svg)](https://termux.dev)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64-blue.svg)](#)
[![Requirement](https://img.shields.io/badge/Requirements-Root%20%7C%20Shizuku%20%7C%20PRoot-blue.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GPU Acceleration](https://img.shields.io/badge/GPU-Mesa%20Turnip%20%7C%20Zink%20%7C%20VirGL-orange.svg)](#)

**Android Subsystem for Linux (ASL)** is a high-performance Linux subsystem management engine, gaming container framework, GTK3 desktop control suite, and Android host bridge for ARM64 devices.

Modeled after **WSL (Windows Subsystem for Linux)** on PC, **ASL** transforms your Android smartphone or tablet into a full Linux workstation and gaming environment, supporting **Root (`su`)**, **Shizuku (`rish`)**, and **PRoot (Zero-Root)** environments.

---

```text
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                   ANDROID SUBSYSTEM FOR LINUX (ASL)                     │
 ├─────────────────────────────────────────────────────────────────────────┤
 │                                                                         │
 │  ┌───────────────────────────────────────────────────────────────────┐  │
 │  │       Debian 13 Trixie ARM64 Subsystem + ASL Hub GTK3 Suite       │  │
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
Select your preferred Linux distribution interactively during setup (Debian Modded, Debian Trixie, Ubuntu 24.04, Arch Linux, Alpine, or Kali Linux), or pass non-interactive flags:

```bash
# ASL Modded Rootfs (Pre-configured Turnip Vulkan, Box64, Wine64, XFCE Desktop & ASL Hub):
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash -s -- --modded

# Standard Clean Debian Trixie Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash -s -- --debian

# Ubuntu 24.04 LTS Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash -s -- --ubuntu

# Arch Linux Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash -s -- --arch

# Kali Linux Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian5/ASL/master/install.sh | bash -s -- --kali
```

### ⚡ Execution Modes (Root / Shizuku / PRoot)
ASL automatically detects your device capabilities or lets you select your execution mode:
- **Root (`su`)**: Maximum performance native kernel chroot with direct GPU node access (`--root`).
- **Shizuku (`rish`)**: ADB-privileged execution mode for non-rooted devices with Shizuku enabled (`--shizuku`).
- **PRoot**: User-space syscall translation for non-rooted devices without Shizuku (`--proot`).

Switch modes anytime via CLI:
```bash
asl exec-mode [root|shizuku|proot|status]
```

After installation, launch the interactive console anytime:
```bash
asl
```

---

## 🔥 Key Features & Capabilities

### 🛡️ 1. Zero-Crash Isolated Subsystem Core
- **100% Native Kernel Performance**: Native root kernel privileges (`su`) mount the chroot directly without system call interception overhead.
- **Strict Mount Isolation**: Enforces private bind mounts (`--make-rprivate` and `--make-rslave`) without mounting host Android system partitions (`/system`, `/vendor`, `/apex`). Eliminates SELinux panics, mount deadlocks, and OS kernel crashes.

### 🎛️ 2. Native Debian GTK3 Control Center ("ASL Hub")
- **Desktop & CLI GUI**: Provides a full GTK3 desktop app launcher installed directly on the Debian desktop (`/root/Desktop/asl-hub.desktop`) and accessible via `asl hub` or `asl gui`.
- **Multithreading Invariant**: Built with Python 3 + GTK3 using `os.posix_spawn` process creation, adhering to Architecture Invariant #1 (preventing multithreading GTK3 deadlocks).

### 🎮 3. Direct3D 11/12 Hardware Acceleration & Gaming Engine
- **Turnip Mesa Vulkan Drivers**: Native Turnip driver profile support for Qualcomm Adreno 6xx/7xx GPUs and Zink OpenGL-over-Vulkan.
- **MangoHud & DXVK_HUD Performance Overlay**: Real-time FPS, CPU/GPU temperature, and VRAM telemetry overlay (`asl hud on`).
- **Wine Mono & Gecko Offline Bundles**: Package offline `.msi` installers for .NET Framework and MSHTML engine (`asl wine-bundle`).
- **Wine & Proton-GE Version Manager**: Switch between standard Debian Wine and custom Proton-GE gaming engines (`asl wine-version`).
- **Bluetooth Gamepad Passthrough**: Bind `/dev/input/event*` nodes into chroot for wireless controllers (`asl gamepad`).

### 💻 4. Dev Suite & Security Auditing Suite
- **Developer Suite**: One-click installation for Python 3, Node.js, Neovim, Go, Rust, and VS Code Server (`asl dev-suite`).
- **Containerized Security Suite**: Defensive network auditing toolsuite including Nmap, Wireshark/TShark, Netcat, Socat, and Hydra (`asl security-suite`).

### 🧹 5. Storage Cleaner & Automated Integrity Repair
- **Storage Cleaner**: Purges APT package archives, temporary `/tmp` files, and Mesa shader caches (`asl clean`).
- **Automated Integrity Repair**: Self-healing recovery for stale mount points, permission errors, and DPKG lock states (`asl repair`).

---

## 📖 Guide to the `docs/` Directory

All technical specifications, architecture invariants, CLI subcommands, and operational guides are documented inside the [`docs/`](docs/) directory. Use this guide to find the information you need:

| Document | Purpose & Target Audience | Key Contents |
| :--- | :--- | :--- |
| 🏗️ **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** | System Architects & Developers | Mount isolation mechanisms, process lifecycle invariants (`os.posix_spawn`), GPU driver architecture, dynamic `/etc/profile.d/asl_env.sh` sync. |
| 🎮 **[`docs/GAMING_GUIDE.md`](docs/GAMING_GUIDE.md)** | Gamers & Power Users | Wine prefix isolation, Turnip/Zink Vulkan drivers, MangoHud telemetry overlay, Proton-GE manager, DXVK/VKD3D auto-installer, Steam setup. |
| ⚡ **[`docs/PERFORMANCE_TUNING.md`](docs/PERFORMANCE_TUNING.md)** | Performance Engineers | CPU governor boost, sysctl kernel parameters (`swappiness`, `dirty_ratio`), PulseAudio low-latency buffers, Box64 dynarec flags. |
| 🛠️ **[`docs/CLI_AND_UTILITIES.md`](docs/CLI_AND_UTILITIES.md)** | Command Line & Script Users | Comprehensive subcommand reference table for `asl`, parameter details, utility script index in `core/`, `desktop/`, and `gaming/`. |
| 🗺️ **[`docs/ROADMAP_AND_TRACKING.md`](docs/ROADMAP_AND_TRACKING.md)** | Contributors & Testers | Completed feature list, upcoming roadmap enhancements, architectural invariants to maintain across edits. |

### How to Use Documentation in Development:
1. **Adding a Feature**: Consult `docs/ROADMAP_AND_TRACKING.md` to check architectural invariants before making edits.
2. **Modifying Process Execution**: Review `docs/ARCHITECTURE.md` to ensure `os.posix_spawn` is maintained in GTK3 multithreading contexts.
3. **Adding CLI Commands**: Update `docs/CLI_AND_UTILITIES.md` whenever adding subcommands to `bin/asl`.

---

## 📦 Repository Structure

```text
ASL/
├── install.sh            # Automated setup script with distro selection & driver setup
├── bin/
│   ├── asl               # Main CLI entrypoint & interactive console dashboard
│   └── superkit          # Alternative entrypoint symlink
├── core/
│   ├── mount-chroot.sh   # Safe isolated chroot mount manager
│   ├── stop-chroot.sh    # Safe unmount & process termination manager
│   ├── doctor.sh         # Environment pre-flight check & diagnostics
│   ├── gpu-detect.sh     # Hardware SoC auto-detection & profile selection
│   ├── gpu-profile.sh    # Mesa Turnip / Zink / VirGL environment profile manager
│   ├── hud.sh            # MangoHud & DXVK_HUD telemetry overlay manager
│   ├── wine-bundle.sh    # Wine Mono & Gecko offline MSI bundle installer
│   ├── wine-version.sh   # Wine & Proton-GE version manager
│   ├── gamepad.sh        # Bluetooth & USB gamepad evdev input mapper
│   ├── dev-suite.sh      # Developer suite installer (Python, Node, Go, Rust, VS Code)
│   ├── security-suite.sh # Defensive security audit toolsuite (Nmap, Wireshark, Socat)
│   ├── cleaner.sh        # Storage cache purger & disk space cleaner
│   ├── repair.sh         # Automated integrity repair & system recovery
│   ├── thermal.sh        # SoC & battery thermal sensor diagnostic monitor
│   ├── termux-bridge.sh  # WakeLock, open, clipboard, and notification bridge
│   ├── android-aid.sh    # Android AID GID group mapper
│   └── snapshot.sh       # Point-in-time chroot snapshot & backup manager
├── gaming/
│   └── wine-box64.sh     # Wine64, Box64 & Windows app execution manager
├── desktop/
│   ├── asl-hub-installer.sh # Deploys ASL Hub GTK3 Control Center into Debian rootfs
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
| `asl` | Open the main terminal dashboard |
| `asl overview` | Print concise live system status without dashboard |
| `asl hud [on\|off\|status]` | Toggle MangoHud / DXVK performance telemetry overlay |
| `asl thermal` | Monitor battery and CPU/GPU thermal zone temperatures |
| `asl doctor` | Run environment pre-flight diagnostics |

### 2. GTK3 Dashboard & System Management
| Command | Description |
| :--- | :--- |
| `asl hub` / `asl gui` | Deploy and launch ASL Hub GTK3 Control Center |
| `asl clean [all\|apt\|tmp]`| Purge APT package cache, `/tmp` files, and Mesa shader caches |
| `asl repair [all\|mounts]`| Run automated repair for stale mounts, DPKG locks, and permissions |

### 3. MoBox Gaming & Direct3D Engine
| Command | Description |
| :--- | :--- |
| `asl gpu` | Display active Turnip/Mesa GPU hardware runtime profile |
| `asl mode [gaming\|performance]` | Apply memory compaction & Turnip GPU tuning |
| `asl wine-bundle [install]` | Download & package offline Wine Mono (.NET) & Gecko bundles |
| `asl wine-version [set]` | Switch between standard system Wine and Proton-GE engines |
| `asl gamepad [sync\|test]` | Synchronize Bluetooth `/dev/input` gamepads into chroot |
| `asl dxvk [enable\|status]` | Auto-install DXVK & VKD3D DirectX-to-Vulkan translators |
| `asl setup-gaming` | Auto-install Wine64, Box64, and gaming tooling |
| `asl game <exe>` | Execute Windows application via Box64 + Wine64 |

### 4. Dev Suite & Security Audit Tools
| Command | Description |
| :--- | :--- |
| `asl dev-suite [install]` | Install IDEs and dev tools (`python`, `webdev`, `neovim`, `go`, `rust`, `vscode`) |
| `asl security-suite [install]`| Deploy defensive security auditing suite (`basic`, `audit`, `nmap`, `wireshark`) |

### 5. Termux-X11 Desktop & Remote Services
| Command | Description |
| :--- | :--- |
| `asl desktop start` | Launch hardware-accelerated XFCE4 desktop (includes ASL Hub shortcut) |
| `asl desktop stop` | Terminate current desktop session safely |
| `asl desktop status` | Inspect active desktop session state |
| `asl theme [dark\|light]` | Switch GTK theme presets |
| `asl resolution [720p\|1080p]` | Configure Termux:X11 display resolution |
| `asl remote ssh [start\|stop]` | Manage SSH server (port 2222) |
| `asl remote vnc [start\|stop]` | Manage x11vnc server (port 5900) |
| `asl audio [start\|stop\|test]`| PulseAudio server management |

### 6. Termux & Android Host Bridge
| Command | Description |
| :--- | :--- |
| `asl wakelock [on\|off]` | Control CPU WakeLock state |
| `asl open <file\|url>` | Open file or URL in default Android host app |
| `asl clip [copy\|paste]` | Read or write Android system clipboard |
| `asl toast <msg>` | Send Android toast notification |
| `asl notify <title> <msg>` | Send Android notification banner |
| `asl aid setup` | Map Android host AID GIDs inside chroot |

---

## 🔒 Safety & Isolation Guarantees

Standard chroot scripts often execute `mount --bind / /chroot` or bind Android system folders (`/system`, `/vendor`, `/apex`). On Android 10 through 15+, this causes SELinux violations, mounting deadlocks, broken camera/audio daemons, and kernel panics.

**Android Subsystem for Linux (ASL)** enforces strict mount isolation:
- Shared access is provided strictly for user storage (`/sdcard`), device nodes (`/dev`, restricted to 0660/input-group), and IPC sockets (`/tmp`).
- Mount points use `--make-rprivate` and `--make-rslave` flags to prevent mount events from leaking into the host Android OS.
- No host system partitions (`/system`, `/vendor`, `/apex`) are mounted into the chroot, so host OS stability is not threatened by chroot activity.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for details.
