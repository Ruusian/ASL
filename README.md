# 🚀 Android Subsystem for Linux (ASL)

<p align="center">
  <b>The Enterprise-Grade Autonomous Linux Subsystem, Workstation & Developer Environment for Android ARM64</b>
</p>

<p align="center">
  <a href="https://termux.dev"><img src="https://img.shields.io/badge/Platform-Android%20%7C%20Termux-brightgreen.svg?style=for-the-badge&logo=android" alt="Platform"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Architecture-ARM64%20(aarch64)-blue.svg?style=for-the-badge&logo=arm" alt="Architecture"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Execution-Root%20Kernel%20Chroot-purple.svg?style=for-the-badge" alt="Execution Modes"/></a>
  <a href="#"><img src="https://img.shields.io/badge/GPU-Mesa%20Turnip%20%7C%20Zink-orange.svg?style=for-the-badge&logo=vulkan" alt="GPU Acceleration"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge" alt="License"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Release-Stable-success.svg?style=for-the-badge" alt="Release"/></a>
</p>

---

## ⚡ Overview

**Android Subsystem for Linux (ASL)** is an autonomous, high-performance Linux container engine, hardware-accelerated workstation, XFCE4 desktop environment, and remote tunneling suite designed for ARM64 Android devices.

Modeled after **WSL (Windows Subsystem for Linux)**, **ASL** turns your phone or tablet into a native Linux workstation with zero SELinux panics or host OS crashes, running on a dedicated, high-performance root-accelerated Linux kernel chroot environment (Magisk / KernelSU / APatch).

---

## 🏛️ System Architecture

```text
 ┌──────────────────────────────────────────────────────────────────────────────────┐
 │                       ANDROID SUBSYSTEM FOR LINUX (ASL)                          │
 ├──────────────────────────────────────────────────────────────────────────────────┤
 │                                                                                  │
 │  ┌────────────────────────────────────────────────────────────────────────────┐  │
 │  │      Dynamic Multi-Distro Subsystem (Debian / Ubuntu / Arch / Kali)        │  │
 │  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │  │
 │  │  │  XFCE4 Desktop   │  │ GPU & Vulkan     │  │ Turnip / Zink Acceleration │  │
 │  │  │  (Termux:X11 :0) │  │ Hardware Layer   │  │ Direct /dev/kgsl-3d0 Node│  │  │
 │  │  └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │  │
 │  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │  │
 │  │  │ OpenClaude CLI   │  │ Dev & Security   │  │ OmniRoute AI Gateway     │  │  │
 │  │  │ AI Agent Suite   │  │ Tooling Suites   │  │ (Port 20128 - Netd Bypass│  │  │
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
 │  │  │ (/dev/kgsl-3d0)  │  │ Evdev Gamepads   │  │ (zRAM + 5GB File Swap)   │  │  │
 │  │  └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │  │
 │  └────────────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🖥️ Live Terminal TUI Console

ASL features a flicker-free, 74-column DEC Mode 1049 alternate-screen buffer dashboard with live diagnostics:

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │   ASL - Android Subsystem for Linux                                    │
 ├────────────────────────────────────────────────────────────────────────┤
 │   Host:        Linux 4.14.357 (aarch64)                                │
 │   Subsystem:   Debian 13 (Trixie) [MOUNTED]                            │
 │   Exec Mode:   Root (su - native kernel chroot)                        │
 │   GPU Driver:  Qualcomm Adreno 6xx/7xx (Turnip Mesa Vulkan)            │
 │   Audio:       PulseAudio (127.0.0.1:4713) [ACTIVE]                    │
 │   Swap Pool:   5.0 GB Active (zRAM + File Swap)                        │
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

## ⚡ Quick Installation (For Rooted Android Devices)

Install or upgrade **ASL** with a single command inside Termux:

```bash
# Recommended Fast CDN Mirror (bypasses GitHub raw 429 rate limits):
curl -fsSL https://cdn.jsdelivr.net/gh/Ruusian/ASL@master/install.sh | bash

# Alternative direct GitHub link:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash
```

### 🐧 Dynamic Distro & Image Flavors
Pass non-interactive distribution flags or select interactively during setup (provisioned dynamically via `proot-distro`):

```bash
# Debian Trixie (Recommended - Turnip Mesa Vulkan, Audio & XFCE4 Desktop pre-configured):
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --debian

# Ubuntu 24.04 LTS Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --ubuntu

# Arch Linux Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --arch

# Alpine Linux Base (Ultra-lightweight):
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --alpine

# Kali Linux Base (Security & Auditing):
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --kali

# Fedora Linux Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --fedora

# Void Linux Base:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --void

# Custom OCI / Docker Container Image:
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash -s -- --distro=ubuntu:24.04
```

### ⚡ Step-by-Step Getting Started Guide

1. **Verify Environment**:
   ```bash
   asl doctor
   ```
2. **Mount the Linux Subsystem**:
   ```bash
   asl start
   ```
3. **Launch the XFCE4 Hardware-Accelerated Desktop**:
   ```bash
   asl desktop start
   ```
   *(If running for the first time, ASL will automatically install and configure XFCE4, Termux:X11, D-Bus, and audio tools).*
4. **Enter Linux Shell**:
   ```bash
   asl shell
   ```
5. **Open Interactive Management Console**:
   ```bash
   asl
   ```

---

## 🔥 Key Features & Capabilities

### 🛡️ 1. Zero-Crash Isolated Subsystem Core
- **100% Native Kernel Performance**: Direct kernel chroot mounting with zero translation overhead.
- **Strict Mount Isolation**: Uses `--make-rprivate` and `--make-rslave` bind mounts without mounting Android system partitions (`/system`, `/vendor`, `/apex`), eliminating SELinux deadlocks and OS kernel crashes.
- **Automated Rollback Traps**: Catches mount errors on startup and unmounts partial paths automatically.

### 🎮 2. Direct GPU Acceleration & Input Engine
- **Turnip Mesa Vulkan & Zink**: Hardware-accelerated OpenGL/Direct3D for Qualcomm Adreno 6xx/7xx/8xx GPUs with direct `/dev/kgsl-3d0` node bindings.
- **MangoHud Telemetry**: Real-time FPS, CPU/GPU temperature, and VRAM overlay (`asl hud on`).
- **Bluetooth Gamepad Passthrough**: Synchronize `/dev/input/event*` wireless controllers directly into the subsystem (`asl gamepad sync`).

### 🖥️ 3. Automated XFCE4 Desktop & Termux:X11 Integration
- **Automated Bootstrapping**: One-click desktop provisioning via `asl desktop setup` or auto-prompt during `asl desktop start`.
- **Display Server Integration**: Native integration with Termux:X11 display `:0`, PulseAudio audio forwarding, and D-Bus IPC.
- **Resolution Control**: Configure display resolution and UI scaling on the fly (`asl resolution 1080p 1.25`).

### 🌐 4. 24/7 Remote Mesh Tunnels & Background Services
- **Oracle Cloud VPS Dedicated Relay**: Always-on persistent reverse SSH tunnel forwarding SSH (2222) to your own remote VPS (`asl remote oracle setup`).
- **LAN SSH Server**: Termux host SSH daemon on port 8022 with password authentication.
- **Serveo & Ngrok**: Instant public jump-host and multi-token rotation tunneling on demand.
- **24/7 Autostart & Service Watchdog**: Detached double-fork background daemon (`service-manager.sh`) with TCP throughput tuning and automatic service recovery.

### 🤖 5. OmniRoute AI Gateway & OpenClaude Environment
- **Local AI Proxy**: Embedded OmniRoute AI proxy running on port 20128.
- **Android Netd Bypass**: Executes under root with explicit Termux library bindings to circumvent Android 14 UID network restrictions.
- **OpenClaude Native CLI**: Pre-configured AI coding agent environment with memory and tools.

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
| **DNS Synchronization** | `asl dns [sync\|status]` | Synchronize active Android nameservers into chroot `/etc/resolv.conf` |
| **Phantom Process Killer** | `asl ppk [off\|on\|status]` | Disable or inspect Android 12+ child process limits |
| **Diagnostic Doctor** | `asl doctor` | Run non-mutating environment checks |
| **Setup Wizard** | `asl wizard` / `asl init` | Guided first-time setup for Desktop, Graphics, Dev, Security presets |
| **GPU Acceleration** | `asl gpu [profile\|apply]` | Configure Turnip/Zink GPU acceleration profiles |
| **Turbo Governor** | `asl turbo` / `asl gpu` | Apply maximum CPU/GPU performance governor |
| **Gamepad Passthrough**| `asl gamepad [sync\|test]` | Synchronize host Bluetooth/USB evdev gamepads into chroot |
| **Performance HUD** | `asl hud [on\|off\|toggle\|status]` | Toggle MangoHud telemetry overlay |
| **Thermal Diagnostics**| `asl thermal [watch]` | Monitor battery and CPU/GPU thermal zone sensors |
| **Desktop Session** | `asl desktop [start\|stop\|setup\|restart]`| Start/stop/setup hardware-accelerated XFCE4 desktop on Termux:X11 |
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
| **Declarative Config**| `asl config [show\|init\|get\|set]` | Manage system settings in `/etc/asl.conf` |
| **Path Translation** | `asl path [-u\|-a\|-c\|-m] <path>` | Translate paths between Android host and Linux container |
| **Android Host Bridge**| `asl wakelock\|open\|clip\|toast\|shortcut` | WakeLock, default app opener, clipboard, notifications |

---

## 📖 Comprehensive Documentation Directory (`docs/`)

All in-depth architectural specifications, hardware tuning guides, and developer documentation are located in [`docs/`](docs/):

| Document | Purpose & Description |
| :--- | :--- |
| 🏗️ **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** | Technical subsystem architecture, execution model, runtime separation, container isolation. |
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
