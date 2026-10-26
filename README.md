# Android Subsystem for Linux (ASL)

<p align="center">
  <b>Native root Linux container engine and hardware-accelerated workstation for Android ARM64</b>
</p>

<p align="center">
  <a href="https://github.com/Ruusian/ASL"><img src="https://img.shields.io/badge/GitHub-Ruusian%2FASL-58A6FF?style=flat-square&logo=github&logoColor=white" alt="GitHub"/></a>
  <a href="https://termux.dev"><img src="https://img.shields.io/badge/Platform-Termux%20%7C%20Android-7EE787?style=flat-square&logo=android&logoColor=white" alt="Platform"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Arch-ARM64%20(aarch64)-58A6FF?style=flat-square&logo=arm&logoColor=white" alt="Architecture"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-BC8CFF?style=flat-square&logo=linux&logoColor=white" alt="Root"/></a>
  <a href="#"><img src="https://img.shields.io/badge/GPU-Turnip%20%7C%20Zink%20%7C%20Virgl-FFA657?style=flat-square&logo=vulkan&logoColor=white" alt="GPU"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-E3B341?style=flat-square" alt="License"/></a>
</p>

---

## What Is ASL

ASL mounts a full Linux distribution (Debian, Ubuntu, Arch, Kali, Alpine, Fedora, Void, or OpenSUSE) as a native chroot container on rooted Android devices. It binds hardware GPU nodes directly into the container, runs an XFCE4 desktop with low-latency audio, and maintains persistent remote SSH tunnels — all without syscall translation layers, ptrace overhead, or SELinux panics.

Think of it as **WSL for Android**: a real Linux userland running at bare-metal speed directly on your device's ARM64 Linux kernel.

> **Requirements**: Root access (`su` via **Magisk**, **KernelSU**, or **APatch**) on an ARM64 Android device running Termux.

### How ASL Compares to Other Solutions

| Feature | **ASL** | PRoot | UserLAnd | AndroNix |
| :--- | :--- | :--- | :--- | :--- |
| **Execution Model** | Native kernel chroot (`su`) | ptrace syscall interception | proot wrapper | proot wrapper |
| **Syscall Overhead** | 0% (Bare-metal kernel) | 10–40% penalty per call | 10–40% | 10–40% |
| **Root Required** | Yes (Magisk / KernelSU / APatch) | No (Rootless) | No (Rootless) | No (Rootless) |
| **GPU Acceleration** | Direct `/dev/kgsl-3d0` node pass-through | None | None | None |
| **Desktop Session** | XFCE4 on Termux:X11 + HTML5 noVNC | VNC only | VNC only | VNC only |
| **Background Daemons** | 24/7 Persistent (PPK mitigation) | Killed on app exit | Killed | Killed |
| **Remote Access** | 4-tier SSH relay mesh | Manual setup | None | None |

---

## Quick Install

Open Termux and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash
```

The installer detects your hardware platform, provisions dependencies, and prompts you to select a distribution. You can also pass flags directly: `--debian`, `--ubuntu`, `--arch`, `--kali`, `--alpine`, `--fedora`, `--void`, or `--opensuse`.

After installation:

```bash
asl doctor     # Run non-mutating environment diagnostics
asl start      # Mount the Linux subsystem
asl shell      # Enter the interactive Linux shell
```

---

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                        ANDROID KERNEL (ARM64)                                │
│   Qualcomm Adreno GPU  ·  /dev/kgsl-3d0  ·  Octa-Core Kryo  ·  zRAM        │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │ Native su chroot (zero translation)
┌──────────────────────────────────▼───────────────────────────────────────────┐
│                         ASL CONTAINER ENGINE                                 │
│                                                                              │
│  Mount Isolation          GPU Pass-Through          Display & Audio           │
│  ├ --make-rprivate        ├ Adreno: Turnip Vulkan   ├ Termux:X11 (:0)        │
│  ├ --make-rslave          ├ Adreno: Zink OpenGL 4.6 ├ PulseAudio TCP (4713)  │
│  ├ Private /proc /sys     ├ Mali/Exynos: Virgl 3D   ├ noVNC Web Desktop      │
│  └ No /system /vendor     └ MangoHud telemetry      └ Resolution scaling     │
│                  /apex pollution                                             │
│                                                                              │
│  Service Manager          Remote Mesh               System Tools             │
│  ├ Daemon lifecycle       ├ Custom VPS Tunnel        ├ Snapshot backup        │
│  ├ PPK watchdog           ├ Serveo relay             ├ Thermal monitor        │
│  ├ Double-fork detach     ├ Ngrok multi-token        ├ CPU governor modes     │
│  └ Auto-restart           ├ LAN SSH (8022)           ├ Swap manager           │
│                           └ Autoconnect + keys       └ Orphan killer          │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Mount Namespace Isolation

ASL provisions private mount namespaces using `--make-rprivate` and `--make-rslave`. The container never binds or pollutes Android's `/system`, `/vendor`, or `/apex` partitions. Automated rollback traps ensure that any mount interruption cleanly unwinds partial mounts, preventing SELinux deadlocks and host kernel panics.

### Hardware GPU Acceleration

* **Qualcomm Snapdragon (Adreno 6xx / 7xx / 8xx)**: Direct `/dev/kgsl-3d0` node pass-through interfaces with open-source Mesa Turnip (Vulkan 1.3) and Zink (OpenGL 4.6 over Vulkan) for bare-metal 3D rendering.
* **ARM Mali (MediaTek Dimensity / Samsung Exynos) & PowerVR**: Fallback to Virgl hardware-assisted 3D rendering via host IPC.
* **Performance Overlay**: Configure real-time DXVK / MangoHud telemetry via `asl hud on`.

### Desktop Environments

* **Termux:X11 (Primary)**: Low-latency shared-memory X11 display server rendering XFCE4 directly on display `:0`, paired with native PulseAudio audio streaming over TCP `127.0.0.1:4713` (<15ms latency).
* **HTML5 Web Desktop (Remote)**: TigerVNC + noVNC + WebSockify serves the desktop as an interactive web session on port `6080`.

Adjust screen resolution and DPI scaling on the fly:

```bash
asl resolution 1080p 1.25    # 1080p resolution with 125% DPI scale
asl resolution status        # Check current resolution
```

### Remote Access Mesh

ASL provides a 4-tier remote bridge architecture:

| Tier | Relay Type | Port | Description |
| :--- | :--- | :--- | :--- |
| **1** | Custom VPS Relay | Custom | Persistent reverse SSH tunnel (configured via `~/.asl/remote.conf`) |
| **2** | Serveo Relay | Dynamic | Zero-configuration public SSH jump host |
| **3** | Ngrok Relay | Dynamic | Multi-token fallback tunnel |
| **4** | LAN SSH | 8022 | Direct local network terminal access |

To configure your own VPS relay:

```bash
cp desktop/remote/remote.conf.example ~/.asl/remote.conf
# Edit ~/.asl/remote.conf with your VPS host, user, and SSH key
```

### Performance & Thermal Controls

```bash
asl mode performance   # Lock all CPU cores to maximum performance governor
asl mode gpu           # GPU-optimized compute profile
asl mode balanced      # Standard schedutil governor
asl mode powersave     # Low-power governor
asl thermal            # Inspect real-time SoC and battery thermal readings
```

### Subsystem Snapshots & Backups

Create, list, and restore full rootfs snapshots without losing data:

```bash
asl snapshot create my-backup --compress   # Create compressed .tar.zst snapshot
asl snapshot list                         # List available snapshots
asl snapshot restore my-backup            # Restore container state
```

---

## CLI Reference

### Subsystem Lifecycle

| Command | Description |
| :--- | :--- |
| `asl` | Launch interactive TUI console |
| `asl start` | Mount Linux container rootfs and virtual filesystems |
| `asl stop` | Terminate container processes and unmount cleanly |
| `asl restart` | Restart subsystem mounts |
| `asl status` | Display mount points, process count, rootfs size, and uptime |
| `asl shell [user]` | Open interactive shell inside the container |
| `asl exec <cmd>` | Execute a single command inside the container |
| `asl doctor` | Non-mutating environment diagnostic health check |

### Desktop & Display

| Command | Description |
| :--- | :--- |
| `asl desktop start` | Start XFCE4 desktop on Termux:X11 display `:0` |
| `asl desktop stop` | Stop active XFCE4 desktop session |
| `asl resolution <res>` | Set display resolution (`1080p`, `720p`, `native`) and scale |
| `asl host list` | List desktop applications installed in container |
| `asl host launch <app>` | Launch container application directly |

### Hardware & Power

| Command | Description |
| :--- | :--- |
| `asl gpu` | Inspect active GPU profile and driver state |
| `asl hud [on\|off]` | Toggle MangoHud / DXVK performance overlay |
| `asl mode <profile>` | Switch CPU governor: `performance`, `balanced`, `powersave`, `gpu` |
| `asl thermal` | Display real-time CPU and battery temperatures |
| `asl cputop [secs]` | Real-time sustained process CPU & memory monitor |
| `asl benchmark` | Run CPU compute, memory bandwidth, and 3D rasterization benchmarks |
| `asl gamepad sync` | Synchronize host `/dev/input` evdev gamepad nodes into container |

### Maintenance & Remote

| Command | Description |
| :--- | :--- |
| `asl snapshot` | Manage rootfs snapshots (create, restore, list, delete) |
| `asl clean` | Purge APT package archives, temporary caches, and shader caches |
| `asl clean-orphans` | Terminate orphaned background processes inside container |
| `asl repair` | Self-healing recovery for stale mounts and package manager locks |
| `asl remote` | Manage reverse SSH tunnels (Custom VPS, Serveo, Ngrok, LAN) |
| `asl ppk off` | Disable Android 12+ Phantom Process Killer limits |
| `asl dns sync` | Synchronize Android system DNS into `/etc/resolv.conf` |

---

## Project Structure

```text
ASL/
├── bin/
│   └── asl                    # Main CLI dispatcher
├── core/
│   ├── mount-chroot.sh        # Chroot mount with namespace isolation
│   ├── stop-chroot.sh         # Safe unmount and process termination
│   ├── service-manager.sh     # Daemon lifecycle and watchdog
│   ├── gpu-profile.sh         # Adreno / Mali / Virgl GPU detection & profiles
│   ├── hud.sh                 # MangoHud and DXVK environment manager
│   ├── doctor.sh              # Environment diagnostic engine
│   ├── wizard.sh              # Interactive setup wizard
│   ├── swap-manager.sh        # Virtual swap pool management
│   ├── snapshot.sh            # Rootfs archive and restore
│   ├── thermal.sh             # SoC temperature monitoring
│   ├── cputop.sh              # Real-time sustained CPU usage monitor
│   ├── benchmark.sh           # Hardware performance benchmarking
│   ├── repair.sh              # Self-healing recovery
│   ├── cleaner.sh             # Cache and scratch file cleanup
│   ├── orphan-killer.sh       # Orphan process cleanup
│   ├── gamepad.sh             # Bluetooth & USB gamepad input mapping
│   ├── dev-suite.sh           # Development toolchain installer
│   ├── security-suite.sh      # Security auditing toolchain installer
│   ├── kernel-check.sh        # Kernel feature inspection
│   └── common.sh              # Shared helper functions
├── desktop/
│   ├── start-desktop.sh       # XFCE4 desktop on Termux:X11
│   ├── asl-web-desktop.sh     # noVNC HTML5 web desktop (port 6080)
│   ├── remote.sh              # Remote tunnel dispatcher
│   └── remote/
│       ├── lan.sh              # LAN SSH on port 8022
│       ├── serveo.sh           # Serveo public relay
│       ├── ngrok.sh            # Ngrok multi-token tunnel
│       ├── autoconnect.sh      # Tunnel reconnection watchdog
│       └── remote.conf.example # Example configuration for custom VPS
├── install.sh                  # One-line automated installer
├── COMMAND_REFERENCE.md        # Detailed command reference
├── TROUBLESHOOTING.md          # Diagnostic and repair guide
├── GETTING_STARTED.md          # Setup walkthrough
└── LICENSE                     # MIT License
```

---

## Modular Configuration & User Hooks

ASL supports untracked local configurations and lifecycle hooks under `~/.asl/`:

* `~/.asl/remote.conf`: Custom VPS reverse tunnel endpoints and port mappings (see `desktop/remote/remote.conf.example`).
* `~/.asl/server_mode.conf`: Android component targets to revive in headless Server Mode.
* `~/.asl/hooks/post-start.sh`: Executed automatically after subsystem services are started.
* `~/.asl/hooks/post-stop.sh`: Executed automatically after subsystem services are stopped.

---

## Documentation

* [`GETTING_STARTED.md`](GETTING_STARTED.md) — Step-by-step setup walkthrough
* [`COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md) — Comprehensive command syntax
* [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — Common error resolutions
* [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — Kernel mounting and namespace isolation design
* [`docs/PERFORMANCE_TUNING.md`](docs/PERFORMANCE_TUNING.md) — GPU, CPU governor, and memory optimization

---

## License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.

**Author & Maintainer**: [Abhik Sarkar (@Ruusian)](https://github.com/Ruusian)
