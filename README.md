# 🚀 Android Subsystem for Linux (ASL)

<p align="center">
  <img src="https://raw.githubusercontent.com/Ruusian/ASL/master/assets/asl_banner.png" alt="ASL Banner" width="100%" onerror="this.style.display='none'"/>
</p>

<p align="center">
  <b>The Enterprise-Grade Autonomous Linux Subsystem, Gaming Framework & Remote Workstation for Android ARM64</b>
</p>

<p align="center">
  <a href="https://termux.dev"><img src="https://img.shields.io/badge/Platform-Android%20%7C%20Termux-brightgreen.svg?style=for-the-badge&logo=android" alt="Platform"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Architecture-ARM64%20(aarch64)-blue.svg?style=for-the-badge&logo=arm" alt="Architecture"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Execution-Root%20%7C%20Shizuku%20%7C%20PRoot-purple.svg?style=for-the-badge" alt="Execution Modes"/></a>
  <a href="#"><img src="https://img.shields.io/badge/GPU-Mesa%20Turnip%20%7C%20Zink%20%7C%20VirGL-orange.svg?style=for-the-badge&logo=vulkan" alt="GPU Acceleration"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge" alt="License"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Release-v2.5.1%20Stable-success.svg?style=for-the-badge" alt="Release"/></a>
</p>

---

## ⚡ Overview

**Android Subsystem for Linux (ASL)** is an autonomous, high-performance Linux container engine, gaming runtime, GTK3 desktop control center, and remote tunneling workstation designed for ARM64 Android devices.

Modeled after **WSL (Windows Subsystem for Linux)**, **ASL** turns your phone or tablet into a native Linux workstation and x86_64 gaming station with zero SELinux panics or host OS crashes across **Root (`su`)**, **Shizuku (`rish`)**, and **PRoot (Zero-Root)** environments.

---

## 🏛️ System Architecture

```text
 ┌──────────────────────────────────────────────────────────────────────────────────┐
 │                       ANDROID SUBSYSTEM FOR LINUX (ASL)                          │
 ├──────────────────────────────────────────────────────────────────────────────────┤
 │                                                                                  │
 │  ┌────────────────────────────────────────────────────────────────────────────┐  │
 │  │        Debian 13 Trixie / Multi-Distro Subsystem & GTK3 Control Suite      │  │
 │  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │  │
 │  │  │  XFCE4 Desktop   │  │  Box64 + Wine64  │  │ Turnip / Zink / DXVK     │  │  │
 │  │  │  (Termux:X11 :0) │  │  Dynarec Engine  │  │ Direct3D 11/12 Vulkan    │  │  │
 │  │  └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │  │
 │  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │  │
 │  │  │ ASL Hub (GTK3)   │  │ Dev & Security   │  │ OmniRoute AI Gateway     │  │  │
 │  │  │ (posix_spawn)    │  │ Tooling Suites   │  │ (Port 20128 - Netd Bypass│  │  │
 │  │  └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │  │
 │  └──────────────────────────────────────▲─────────────────────────────────────┘  │
 │                                         │ Direct Hardware & Bridge IPC           │
 │  ┌──────────────────────────────────────┴─────────────────────────────────────┐  │
 │  │                      Android Host Bridge & 24/7 Daemons                    │  │
 │  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │  │
 │  │  │ PulseAudio TCP   │  │ LAN SSH (8022)   │  │ Oracle VPS Tunnel Relay  │  │  │
 │  │  │ (127.0.0.1:4713) │  │ Serveo / Ngrok   │  │ (Persistent SSH 2222)    │  │  │
 │  │  └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │  │
 │  └──────────────────────────────────────▲─────────────────────────────────────┘  │
 │                                         │ Kernel Syscalls & Node Bindings        │
 │  ┌──────────────────────────────────────┴─────────────────────────────────────┐  │
 │  │                      Android Linux Kernel & Hardware Nodes                 │  │
 │  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │  │
 │  │  │ Adreno GPU Node  │  │ Bluetooth / USB  │  │ Virtual Swap Pool        │  │  │
 │  │  │ (/dev/kgsl-3d0)  │  │ Evdev Gamepads   │  │ (zRAM + 4GB File Swap)   │  │  │
 │  │  └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │  │
 │  └────────────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🖥️ Live Terminal TUI Console (v2.5.1)

ASL features a flicker-free, 74-column DEC Mode 1049 alternate-screen buffer dashboard with live diagnostics:

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │   ASL - Android Subsystem for Linux v2.5.1                             │
 ├────────────────────────────────────────────────────────────────────────┤
 │   Host:        Linux 4.14.357 (aarch64)                                │
 │   Subsystem:   Debian 13 (Trixie) [MOUNTED]                            │
 │   Exec Mode:   Root (su - native kernel chroot)                        │
 │   GPU Driver:  Qualcomm Adreno 6xx/7xx (Turnip Mesa Vulkan)            │
 │   Audio:       PulseAudio (127.0.0.1:4713) [ACTIVE]                    │
 │   Swap Pool:   4.0 GB Active (zRAM + File Swap)                        │
 ├────────────────────────────────────────────────────────────────────────┤
 │   Remote Access Endpoints:                                             │
 │   * LAN SSH (Host):  ssh -p 8022 u0_a566@192.168.1.100                │
 │   * Oracle VPS:      ssh -J ubuntu@<VPS_IP> -p 2222 user@127.0.0.1   │
 ├────────────────────────────────────────────────────────────────────────┤
 │  [s] Start Subsystem     [x] Stop Subsystem      [d] Start Desktop     │
 │  [g] Launch Game (.exe)  [h] Performance HUD     [v] Remote Bridges    │
 │  [p] Process Manager     [t] Thermal Sensors     [w] Live Watchdog     │
 │  [c] Clean Storage       [r] Self-Repair         [q] Quit              │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Installation

Install or upgrade **ASL** with a single command inside Termux:

```bash
# Recommended Fast CDN Mirror (bypasses GitHub raw 429 rate limits):
curl -fsSL https://cdn.jsdelivr.net/gh/Ruusian/ASL@master/install.sh | bash

# Alternative direct GitHub link:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash
```

### 🐧 Distro & Image Flavors
Pass non-interactive distribution flags or select interactively during setup:

```bash
# ASL Modded Rootfs (Turnip Vulkan, Box64, Wine64, XFCE & ASL Hub pre-configured):
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --modded

# Standard Clean Debian Trixie Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --debian

# Ubuntu 24.04 LTS Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --ubuntu

# Arch Linux Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --arch

# Kali Linux Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --kali
```

### ⚡ 3-Tier Execution Modes
- **Root (`su`)**: Maximum performance direct kernel chroot with `/dev/kgsl-3d0` GPU node access (`--root`).
- **Shizuku (`rish`)**: ADB-privileged execution mode for non-rooted devices (`--shizuku`).
- **PRoot**: User-space syscall translation for non-rooted devices (`--proot`).

Inspect or change execution mode anytime:
```bash
asl exec-mode [root|shizuku|proot|status]
```

Launch the interactive console anytime:
```bash
asl
```

---

## 🔥 Key Features & Capabilities

### 🛡️ 1. Zero-Crash Isolated Subsystem Core
- **100% Native Kernel Performance**: Direct kernel chroot mounting with zero translation overhead.
- **Strict Mount Isolation**: Uses `--make-rprivate` and `--make-rslave` bind mounts without mounting Android system partitions (`/system`, `/vendor`, `/apex`), eliminating SELinux deadlocks and OS kernel crashes.
- **Automated Rollback Traps**: Catches mount errors on startup and unmounts partial paths automatically.

### 🎛️ 2. Native Debian GTK3 Control Center ("ASL Hub")
- **Desktop & CLI GUI**: Full GTK3 desktop app launcher installed directly on the Debian desktop (`/root/Desktop/asl-hub.desktop`) and callable via `asl hub` / `asl gui`.
- **Multithreading Invariant**: Built with Python 3 + GTK3 using `os.posix_spawn` process creation to prevent glibc `atfork` multithreading deadlocks.

### 🌐 3. 24/7 Remote Mesh Tunnels & Background Services
- **Oracle Cloud VPS Dedicated Relay**: Always-on persistent reverse SSH tunnel forwarding SSH (2222) to your own remote VPS (`asl remote oracle setup`).
- **LAN SSH Server**: Termux host SSH daemon on port 8022 with password or ED25519 key authentication.
- **Serveo & Ngrok**: Instant public jump-host and multi-token rotation tunneling on demand.
- **24/7 Autostart & Service Watchdog**: Detached double-fork background daemon (`service-manager.sh`) with TCP throughput tuning and automatic service recovery.

### 🎮 4. Direct3D 11/12 Gaming & Box64 Dynarec Engine
- **Turnip Mesa Vulkan & Zink**: Hardware-accelerated OpenGL/Direct3D for Qualcomm Adreno 6xx/7xx and VirGL/Zink fallback for Mali GPUs.
- **Box64 Dynarec Precision Switcher**: Toggle dynamically between high FPS (`asl game precision fast`) and strict IEEE-754 compatibility (`asl game precision safe`).
- **MangoHud & DXVK_HUD Telemetry**: Real-time FPS, CPU/GPU temperature, and VRAM overlay (`asl hud on`).
- **Wine Mono & Gecko Offline Bundles**: Package offline `.msi` installers for .NET and MSHTML runtimes (`asl wine-bundle`).
- **Bluetooth Gamepad Passthrough**: Synchronize `/dev/input/event*` wireless controllers directly into the subsystem (`asl gamepad`).

### 🤖 5. OmniRoute AI Gateway Integration
- **Local AI Proxy**: Embedded OmniRoute AI proxy running on port 20128.
- **Android Netd Bypass**: Executes under root with explicit Termux library bindings to circumvent Android 14 UID network restrictions.

### 💻 6. Developer Suite & Security Auditing Suite
- **Developer Suite**: One-click installation for Python 3, Node.js, Neovim, Go, Rust, and VS Code Server (`asl dev-suite`).
- **Containerized Security Suite**: Defensive network auditing tools including Nmap, Wireshark/TShark, Netcat, Socat, and Hydra (`asl security-suite`).

### 🧹 7. Storage Cleaner & Automated Integrity Repair
- **Storage Cleaner**: Purges APT package archives, temporary `/tmp` files, and Mesa shader caches (`asl clean`).
- **Automated Integrity Repair**: Self-healing recovery for stale mount points, permission errors, and DPKG lock states (`asl repair`).

---

## 🛠️ Complete CLI Command Reference

| Command | Subcommand / Syntax | Description |
| :--- | :--- | :--- |
| **Interactive Dashboard** | `asl` / `asl dashboard` | Open 74-column DEC 1049 alternate-screen buffer TUI console |
| **System Overview** | `asl overview` | Print concise live system status and remote endpoint table |
| **Subsystem Start** | `asl start` | Mount isolated Linux subsystem rootfs and virtual filesystems |
| **Subsystem Stop** | `asl stop` | Safely terminate processes and unmount all bind mounts |
| **Subsystem Status** | `asl status` | Inspect mount points, process count, rootfs size, and uptime |
| **Interactive Shell** | `asl shell [user]` | Drop into subsystem rootfs interactive bash shell |
| **Command Execution** | `asl exec <command>` | Execute single command directly inside Linux subsystem |
| **Package Installer** | `asl install <pkg>` | Install Debian APT packages inside subsystem |
| **Package Search** | `asl search <query>` | Search available APT packages |
| **Execution Mode** | `asl exec-mode [root\|shizuku\|proot]` | Inspect or switch execution mode |
| **Setup Wizard** | `asl wizard` / `asl init` | Guided first-time setup for Gaming, Dev, Security presets |
| **GTK3 Control Center**| `asl hub` / `asl gui` | Launch ASL Hub GTK3 desktop control center |
| **Wine Application** | `asl game <path_to_exe>` | Execute Windows `.exe` via Box64 + Wine64 |
| **Dynarec Precision** | `asl game precision [safe\|fast]` | Switch Box64 dynarec profile (FPS vs Float Precision) |
| **DirectX Overrides** | `asl dxvk [enable\|status]` | Configure DXVK Direct3D async translation |
| **Wine Bundles** | `asl wine-bundle [install\|status\|clean]` | Package offline Wine Mono (.NET) & Gecko MSI bundles |
| **Wine Manager** | `asl wine-version [set\|status\|install]` | Switch between Debian system Wine and Proton-GE engines |
| **Gamepad Passthrough**| `asl gamepad [sync\|test]` | Synchronize host Bluetooth/USB evdev gamepads into chroot |
| **Performance HUD** | `asl hud [on\|off\|toggle\|status]` | Toggle MangoHud & DXVK_HUD telemetry overlay |
| **Thermal Diagnostics**| `asl thermal [watch]` | Monitor battery and CPU/GPU thermal zone sensors |
| **Desktop Session** | `asl desktop [start\|stop\|restart]`| Start/stop hardware-accelerated XFCE4 desktop on Termux:X11 |
| **Remote Dispatcher** | `asl remote [status\|all\|gui]` | Inspect or start all remote access bridges |
| **LAN SSH Server** | `asl remote lan [start\|stop]` | Control LAN SSH server (port 8022) |
| **Oracle VPS Relay** | `asl remote oracle [setup\|start\|stop]` | Control dedicated VPS persistent reverse SSH tunnel |
| **Serveo Tunnel** | `asl remote serveo [start\|stop]` | Control Serveo jump-host reverse tunnel |
| **Ngrok Tunnel** | `asl remote ngrok [start\|stop]` | Control Ngrok multi-token tunnel |
| **24/7 Autoconnect** | `asl remote autoconnect` | Manage background auto-reconnect tunnel daemon |
| **Service Watchdog** | `asl service [start\|stop\|status]`| Manage 24/7 background service manager and TCP tuning |
| **OmniRoute Gateway** | `asl omniroute [start\|stop\|status]`| Manage root-isolated OmniRoute AI gateway (port 20128) |
| **Virtual Swap Pool** | `asl swap [status\|setup\|optimize\|cleanup]` | Manage virtual swap pool (5GB upper limit) |
| **Storage Cleaner** | `asl clean [status\|all\|apt\|tmp\|cache]` | Purge package archives, `/tmp`, and shader caches |
| **Integrity Repair** | `asl repair [all\|mounts\|permissions\|dpkg]` | Self-healing recovery for mounts, locks, and permissions |
| **Pre-flight Doctor** | `asl doctor` | Comprehensive environment pre-flight diagnostics |
| **Declarative Config**| `asl config [show\|init\|get\|set]` | Manage system settings in `/etc/asl.conf` |
| **Path Translation** | `asl path [-u\|-a\|-c\|-m] <path>` | Translate paths between Android host and Linux container |
| **Android Host Bridge**| `asl wakelock\|open\|clip\|toast\|shortcut` | WakeLock, default app opener, clipboard, notifications |

---

## 📖 Comprehensive Documentation Directory (`docs/`)

All in-depth architectural specifications, hardware tuning guides, and developer documentation are located in [`docs/`](docs/):

| Document | Purpose & Description |
| :--- | :--- |
| 🏗️ **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** | Technical subsystem architecture, 3-tier execution model, `os.posix_spawn` invariant, runtime separation. |
| 🎮 **[`docs/GAMING_GUIDE.md`](docs/GAMING_GUIDE.md)** | Direct3D Vulkan gaming, Box64 dynarec precision, Turnip/Zink drivers, MangoHud, Wine configuration. |
| ⚡ **[`docs/PERFORMANCE_TUNING.md`](docs/PERFORMANCE_TUNING.md)** | Kernel sysctl TCP tuning, CPU governor boost, PulseAudio low-latency buffers, virtual swap management. |
| 🛠️ **[`docs/CLI_AND_UTILITIES.md`](docs/CLI_AND_UTILITIES.md)** | Complete CLI subcommand syntax reference, helper scripts, installer flags, environment variables. |
| 🗺️ **[`docs/ROADMAP_AND_TRACKING.md`](docs/ROADMAP_AND_TRACKING.md)** | Feature tracking, completed milestones, architectural invariants, future development roadmap. |
| 📋 **[`CHANGELOG.md`](CHANGELOG.md)** | Detailed chronological release history, security patches, UI modernizations, and recovery logs. |
| 🔧 **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)** | Solutions for common Android mount errors, audio latency, DPKG locks, and display issues. |

---

## 🔒 Safety & Isolation Guarantees

Standard chroot scripts often execute `mount --bind / /chroot` or bind Android system folders (`/system`, `/vendor`, `/apex`). On Android 10 through 15+, this causes SELinux violations, mount deadlocks, broken camera/audio daemons, and kernel panics.

**Android Subsystem for Linux (ASL)** enforces strict isolation invariants:
- Shared access is restricted to user storage (`/sdcard`), device nodes (`/dev`, restricted to 0660/input-group), and IPC sockets (`/tmp`).
- Mount points use `--make-rprivate` and `--make-rslave` flags to prevent mount events from leaking into the host Android OS.
- Zero host system partitions (`/system`, `/vendor`, `/apex`) are mounted into the subsystem.
- Background daemons spawn in detached double-fork subshells (`((nohup bash ... &) &) 2>/dev/null`) to ensure clean terminal exits.

---

## 📄 License & Maintainer

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.

**Lead Author & Maintainer**: [Abhik Sarkar (@Ruusian)](https://github.com/Ruusian)
