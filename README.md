# Android Subsystem for Linux (ASL)

<p align="center">
  <b>Native root Linux container engine and hardware-accelerated workstation for Android ARM64</b>
</p>

<p align="center">
  <a href="https://github.com/Ruusian/ASL"><img src="https://img.shields.io/badge/GitHub-Ruusian%2FASL-58A6FF?style=flat-square&logo=github&logoColor=white" alt="GitHub"/></a>
  <a href="https://termux.dev"><img src="https://img.shields.io/badge/Platform-Termux%20%7C%20Android-7EE787?style=flat-square&logo=android&logoColor=white" alt="Platform"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Arch-ARM64-58A6FF?style=flat-square&logo=arm&logoColor=white" alt="Architecture"/></a>
  <a href="#"><img src="https://img.shields.io/badge/GPU-Turnip%20Vulkan%20%7C%20Zink-FFA657?style=flat-square&logo=vulkan&logoColor=white" alt="GPU"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-BC8CFF?style=flat-square&logo=linux&logoColor=white" alt="Root"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-E3B341?style=flat-square" alt="License"/></a>
</p>

---

## What Is ASL

ASL mounts a full Linux distribution (Debian, Ubuntu, Arch, Kali, Alpine, Fedora, Void, or OpenSUSE) as a native chroot container on rooted Android devices. It binds hardware GPU nodes directly into the container, runs an XFCE4 desktop with audio, and maintains persistent remote SSH tunnels — all without emulation, translation layers, or SELinux panics.

Think of it as **WSL for Android**: a real Linux userland running at bare-metal speed on your phone's ARM64 kernel.

### How It Differs from PRoot / UserLAnd / AndroNix

| | **ASL** | PRoot | UserLAnd | AndroNix |
| :--- | :--- | :--- | :--- | :--- |
| **Execution** | Native kernel chroot (`su`) | ptrace syscall translation | proot wrapper | proot wrapper |
| **Syscall overhead** | 0% | 10–40% per call | 10–40% | 10–40% |
| **Root required** | Yes (Magisk / KernelSU / APatch) | No | No | No |
| **GPU hardware** | Direct `/dev/kgsl-3d0` pass-through | None | None | None |
| **Desktop** | XFCE4 on Termux:X11 + HTML5 noVNC | VNC only | VNC only | VNC only |
| **Background daemons** | Persistent 24/7 with PPK bypass | Killed on app close | Killed | Killed |
| **Remote access** | 4-tier SSH relay mesh (Oracle VPS, Serveo, Ngrok, LAN) | Manual setup | None | None |

---

## Quick Install

Requires: **Termux** + **root** (Magisk, KernelSU, or APatch) on an ARM64 Android device.

```bash
curl -fsSL https://raw.githubusercontent.com/Ruusian/ASL/master/install.sh | bash
```

The installer detects your environment, installs dependencies, and walks you through distro selection. Pass `--debian`, `--ubuntu`, `--arch`, `--kali`, `--alpine`, `--fedora`, `--void`, or `--opensuse` to skip the prompt.

After install:

```bash
asl doctor     # Verify environment health
asl start      # Mount the Linux subsystem
asl shell      # Drop into an interactive Linux shell
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
│  ├ --make-rprivate        ├ /dev/kgsl-3d0           ├ Termux:X11 (:0)        │
│  ├ --make-rslave          ├ Mesa Turnip Vulkan 1.3  ├ PulseAudio TCP (4713)  │
│  ├ Private /proc /sys     ├ Zink OpenGL 4.6         ├ noVNC Web Desktop      │
│  └ No /system /vendor     └ MangoHud telemetry      └ Resolution scaling     │
│                  /apex pollution                                             │
│                                                                              │
│  Service Manager          Remote Mesh               System Tools             │
│  ├ Daemon lifecycle       ├ Oracle VPS (2222)        ├ Snapshot backup        │
│  ├ PPK watchdog           ├ Serveo relay             ├ Thermal monitor        │
│  ├ Double-fork detach     ├ Ngrok multi-token        ├ CPU governor modes     │
│  └ Auto-restart           ├ LAN SSH (8022)           ├ Swap manager           │
│                           └ Autoconnect + keys       └ Orphan killer          │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Mount Isolation

ASL creates private mount namespaces (`--make-rprivate`, `--make-rslave`) that prevent the container from touching Android's `/system`, `/vendor`, or `/apex` partitions. Automated rollback traps catch mount errors on startup and cleanly unwind partial mounts. This eliminates the SELinux deadlocks and kernel panics that plague naive chroot setups.

### GPU Hardware Acceleration

Direct `/dev/kgsl-3d0` node pass-through gives the container native access to Qualcomm Adreno 6xx/7xx/8xx GPUs through open-source Mesa Turnip (Vulkan 1.3) and Zink (OpenGL 4.6 over Vulkan). Enable real-time MangoHud telemetry with `asl hud on`.

### Desktop Environment

Two display modes:

- **Termux:X11** (primary): Low-latency shared-memory X11 server rendering XFCE4 directly on display `:0`. PulseAudio streams sound over TCP `127.0.0.1:4713`.
- **Web Desktop** (remote): TigerVNC + noVNC + WebSockify serves the desktop as an HTML5 canvas on port `6080`, accessible from any browser on the network.

Control resolution and DPI scaling:

```bash
asl resolution 1080p 1.25    # Set 1080p at 125% scale
asl resolution status        # Show current resolution
```

### Remote Access Mesh

ASL maintains a 4-tier SSH relay mesh through modular tunnel scripts:

| Tier | Tunnel | Port | Use Case |
| :--- | :--- | :--- | :--- |
| 1 | Oracle Cloud VPS | 2222 | Primary persistent relay with static IP |
| 2 | Serveo | Dynamic | Zero-config public jump host |
| 3 | Ngrok | Dynamic | Multi-token fallback relay |
| 4 | LAN SSH | 8022 | Local network direct access |

All tunnels run as double-fork detached daemons with TCP BBR congestion control and automatic reconnection via `autoconnect.sh`.

### Performance Profiles

Control CPU governor and power behavior:

```bash
asl mode performance   # Max CPU frequency (all cores → performance governor)
asl mode gpu           # GPU-optimized profile
asl mode balanced      # Default schedutil governor
asl mode powersave     # Minimum power draw
asl mode status        # Show current profile and governor
```

### Thermal Monitoring

```bash
asl thermal            # Real-time SoC temperature readings
```

### Snapshot & Backup

Full rootfs archive and restore:

```bash
asl snapshot           # Create timestamped rootfs snapshot (tar.gz)
asl backup             # Archive current subsystem state
asl restore            # Restore from a previous snapshot
```

---

## CLI Reference

| Command | Description |
| :--- | :--- |
| `asl` | Interactive TUI management console |
| `asl start` | Mount isolated Linux subsystem |
| `asl stop` | Safely unmount and terminate processes |
| `asl restart` | Stop then start |
| `asl status` | Mount points, process count, rootfs size, uptime |
| `asl shell [user]` | Interactive bash shell inside the container |
| `asl exec <cmd>` | Run a single command inside the container |
| `asl doctor` | Non-mutating environment health check |
| `asl wizard` | Guided first-time setup |
| `asl desktop start` | Launch XFCE4 desktop on Termux:X11 |
| `asl install <pkg>` | Install APT packages inside the container |
| `asl search <query>` | Search available APT packages |
| `asl dns sync` | Sync Android nameservers into `/etc/resolv.conf` |
| `asl ppk off` | Disable Android 12+ Phantom Process Killer |
| `asl gpu` | GPU driver status and diagnostics |
| `asl hud on` | Enable MangoHud real-time GPU/FPS overlay |
| `asl mode <profile>` | CPU governor: `performance`, `balanced`, `powersave`, `gpu` |
| `asl resolution <res>` | Set display resolution and DPI scale |
| `asl thermal` | SoC temperature monitoring |
| `asl benchmark` | Run performance benchmarks |
| `asl snapshot` | Create rootfs snapshot |
| `asl backup` / `restore` | Archive and restore subsystem state |
| `asl remote` | Manage SSH tunnel mesh (Oracle, Serveo, Ngrok, LAN) |
| `asl omniroute <sub>` | OmniRoute AI gateway: `start`, `stop`, `restart`, `update`, `logs` |
| `asl dsh <sub>` | DeepSeek Harness: `start`, `stop`, `restart`, `logs`, `token` |
| `asl gamepad sync` | Sync USB/Bluetooth gamepad input devices |
| `asl dev-suite` | Install developer tools (Python, Node.js, Neovim, Go, Rust) |
| `asl security-suite` | Install security tools (Nmap, Wireshark, Netcat, Hydra) |
| `asl clean` | Purge APT caches, temp files, shader caches |
| `asl clean-orphans` | Kill orphaned processes inside the container |
| `asl repair` | Self-healing recovery for stale mounts and DPKG locks |
| `asl aid` | Display Android AID/GID group mappings |
| `asl kernel-check` | Inspect kernel version and feature support |
| `asl host list` | List installed desktop application launchers |
| `asl host launch <app>` | Launch a desktop application from the container |
| `asl overview` | Concise system status and remote endpoint table |

Full command documentation: [`COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md)

---

## Project Structure

```text
ASL/
├── bin/
│   └── asl                    # Main CLI dispatcher (~2300 lines)
├── core/
│   ├── mount-chroot.sh        # Chroot mount with namespace isolation
│   ├── stop-chroot.sh         # Safe unmount and process termination
│   ├── service-manager.sh     # Daemon lifecycle and watchdog
│   ├── gpu-detect.sh          # Adreno GPU detection and driver binding
│   ├── gpu-profile.sh         # GPU performance profiles
│   ├── hud.sh                 # MangoHud telemetry overlay
│   ├── doctor.sh              # Environment diagnostic engine
│   ├── wizard.sh              # Interactive first-time setup
│   ├── swap-manager.sh        # Virtual swap pool management
│   ├── snapshot.sh            # Rootfs archive and restore
│   ├── thermal.sh             # SoC temperature monitoring
│   ├── benchmark.sh           # Performance benchmarking
│   ├── repair.sh              # Self-healing recovery
│   ├── cleaner.sh             # Cache and temp file purge
│   ├── orphan-killer.sh       # Orphaned process cleanup
│   ├── gamepad.sh             # USB/Bluetooth gamepad sync
│   ├── dev-suite.sh           # Developer toolchain installer
│   ├── security-suite.sh      # Security tool installer
│   ├── kernel-check.sh        # Kernel feature inspection
│   ├── android-aid.sh         # Android AID/GID mapping
│   ├── termux-bridge.sh       # Termux ↔ container IPC bridge
│   ├── asl-ui-guard.sh        # UI landscape lock and guard
│   ├── rotation-guard.sh      # Screen rotation control
│   └── common.sh              # Shared utilities and constants
├── desktop/
│   ├── start-desktop.sh       # XFCE4 desktop on Termux:X11
│   ├── asl-web-desktop.sh     # noVNC HTML5 web desktop (port 6080)
│   ├── remote.sh              # Remote tunnel dispatcher
│   └── remote/
│       ├── oracle.sh           # Oracle Cloud VPS reverse SSH
│       ├── serveo.sh           # Serveo public relay
│       ├── ngrok.sh            # Ngrok multi-token tunnels
│       ├── lan.sh              # LAN SSH (port 8022)
│       ├── autoconnect.sh      # Auto-reconnection watchdog
│       ├── keys.sh             # SSH key management
│       └── tunnel-manager.sh   # Unified tunnel lifecycle
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CLI_AND_UTILITIES.md
│   ├── PERFORMANCE_TUNING.md
│   └── ROADMAP_AND_TRACKING.md
├── install.sh                  # One-line automated installer
├── GETTING_STARTED.md
├── TROUBLESHOOTING.md
├── COMMAND_REFERENCE.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── SECURITY.md
└── LICENSE
```

---

## Safety & Isolation

- **Private mount namespaces** prevent container mounts from leaking into the Android host.
- **No `/system`, `/vendor`, or `/apex` binding** eliminates SELinux policy conflicts and kernel panics.
- **Automated rollback traps** unwind partial mounts on any startup failure.
- **Android 12+ PPK mitigation** (`max_phantom_processes=2147483647`) keeps background daemons alive.
- **DNS synchronization** dynamically mirrors Android's active nameservers into the container's `/etc/resolv.conf`.

---

## Documentation

| Document | Contents |
| :--- | :--- |
| [`GETTING_STARTED.md`](GETTING_STARTED.md) | First-time setup walkthrough |
| [`COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md) | Full CLI documentation |
| [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | Common issues and fixes |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Contribution guidelines |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |
| [`SECURITY.md`](SECURITY.md) | Security policy |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System architecture deep-dive |
| [`docs/PERFORMANCE_TUNING.md`](docs/PERFORMANCE_TUNING.md) | GPU, CPU, and memory tuning |

---

## License

MIT License. See [`LICENSE`](LICENSE) for details.

**Maintainer**: [Abhik Sarkar (@Ruusian)](https://github.com/Ruusian)
