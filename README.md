# 🚀 Android Subsystem for Linux (ASL)

[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Termux-brightgreen.svg)](https://termux.dev)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64-blue.svg)](#)
[![Requirement](https://img.shields.io/badge/Requirements-Root%20(su)%20%2B%20Termux-red.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Android Subsystem for Linux (ASL)** (formerly AndroidLinux-SuperKit) is a high-performance, root-accelerated Linux chroot management subsystem, gaming container framework, and Android host bridge for ARM64 devices.

Modeled after **WSL (Windows Subsystem for Linux)** on PC, **ASL** turns your Android phone or tablet into a full Linux workstation and gaming machine using only **Root (`su`)** and **Termux**.

---

## ⚡ One-Line Automated Installation

Install or update **ASL** instantly with a single command inside Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash
```

### 🐧 Distro Selection Options
Select your preferred Linux distribution interactively during setup, or pass flags non-interactively:

```bash
# Non-interactive distro installation flags:
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash -s -- --distro=debian
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash -s -- --distro=ubuntu
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash -s -- --distro=archlinux
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash -s -- --distro=alpine
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash -s -- --distro=kali
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash -s -- --distro=fedora
```

Launch the interactive 3D console anytime after installation:
```bash
asl       # or superkit
```

---

## 🔥 Unique Features & Capabilities

### 🛡️ 1. Zero-Crash Isolated Subsystem Core
- **100% Native Kernel Performance**: Unlike PRoot (which intercepts system calls via ptrace), ASL mounts Linux chroots directly using native root kernel privileges (`su`).
- **Strict Mount Isolation**: Enforces private slave bind mounts (`--make-rprivate` and `--make-rslave`) without mounting Android host `/system`, `/vendor`, `/apex`, or `/linkerconfig`. Eliminates SELinux panics, mount deadlocks, and host OS reboots.

### 🎮 2. Direct3D 11/12 Acceleration & MoBox Gaming Engine
- **Turnip Mesa Vulkan Drivers**: Integrated Turnip driver profile support for Qualcomm Adreno 6xx/7xx GPUs with DXVK 2.4+ async pipeline compilation, VKD3D Direct3D 12 translation, and VirGL fallback for Mali GPUs.
- **Unity Mono Stability Tuning**: Pre-configured Box64 dynarec stability flags (`BOX64_DYNAREC_STRONGMEM=2`, `SAFEFLAGS=2`) to prevent crashes during Mono C# JIT garbage collection unwinding (e.g. *Nine Sols*, *Hollow Knight*, Unity engine titles).
- **Shader Cache on tmpfs**: Moves Mesa shader caching to `/dev/shm` to bypass storage bottlenecks.

### 📱 3. Deep Android Host & Termux Integration Bridge
- **Android AID (Android ID) Group Mapping**: Automatically maps host GIDs (`aid_graphics`, `aid_audio`, `aid_sdcard_rw`, `aid_gpu_service`, `aid_inet`) inside the Linux chroot so applications have direct hardware access to GPU device nodes, audio sockets, and `/sdcard`.
- **Magisk / KernelSU / APatch Action Module**: Includes root module UI integration (`module/action.sh`) to start or stop the ASL subsystem directly from KernelSU or Magisk Manager UI.
- **Bi-Directional Host Services**:
  - 🔒 **CPU Wake Lock**: Prevent Android deep sleep during long builds or background server tasks (`asl wakelock on`).
  - 🔗 **Host File & URL Launcher**: Open Linux files or web links directly in native Android apps (`asl open <path|url>`).
  - 📋 **System Clipboard Bridge**: Sync clipboard contents between Linux and Android (`asl clip copy/paste`).
  - 🔔 **Android System Toasts & Notifications**: Trigger native Android system toasts and notifications from Linux terminal scripts (`asl toast "Task Done"`).

### 🐧 4. One-Click Multi-Distro Provisioning
- Pulls official OCI container rootfs images via `proot-distro` and provisions them as full root chroots:
  - 🐧 **Debian (Trixie)** — Recommended for Wine64, Box64 & Desktop
  - 🟠 **Ubuntu (24.04 LTS)** — Modern Linux workstation stack
  - 🏹 **Arch Linux** — Rolling release base
  - 🏔️ **Alpine Linux** — Ultra-minimal footprint base
  - 🐉 **Kali Linux** — Security & penetration testing suite
  - 🎩 **Fedora Linux** — Red Hat ecosystem stack

### 📸 5. Point-in-Time Filesystem Snapshots & Backups
- **Instant Local Snapshots**: Create instant snapshots (`asl snapshot create <name>`) and safely restore chroot state in seconds.
- **Rollback Safety**: Includes automated rollback protection and disk headroom validation prior to backup operations.

### 🖥️ 6. Modern 3D TUI Dashboard
- Clean terminal user interface with 3D drop-shadow banners, categorized card grid layout, real-time telemetry (RAM, Swap, CPU temp, battery, load, host IP, X11 status, WakeLock), and single-letter hotkeys (`[s]`, `[x]`, `[d]`, `[g]`, `[m]`, `[p]`, `[t]`, `[v]`, `[k]`, `[o]`, `[c]`, `[n]`, `[a]`).

---

## 📦 Repository Structure

```text
AndroidLinux-SuperKit/
├── install.sh            # One-line automated setup script with distro selector
├── bin/
│   └── superkit          # 3D CLI entrypoint & dashboard (symlinked as 'asl')
├── core/
│   ├── mount-chroot.sh   # Safe isolated chroot mount manager
│   ├── stop-chroot.sh    # Safe unmount & process termination manager
│   ├── doctor.sh         # Non-mutating environment pre-flight check
│   ├── gpu-detect.sh     # SoC auto-detection & driver profile manager
│   ├── gpu-profile.sh    # Mesa Turnip / Zink / VirGL environment profile
│   ├── thermal.sh        # Battery & CPU/GPU thermal zone monitor
│   ├── termux-bridge.sh  # WakeLock, open, clipboard, and notification bridge
│   ├── android-aid.sh    # Android AID GID group mapper
│   └── snapshot.sh       # Point-in-time chroot snapshot & backup manager
├── gaming/
│   └── wine-box64.sh     # Wine64, Box64, DXVK & Windows app launcher
├── desktop/
│   ├── start-desktop.sh  # Termux-X11 desktop & PulseAudio launcher
│   ├── theme.sh          # GTK theme & Papirus icon set switcher
│   └── remote.sh         # OpenSSH (2222) & x11vnc (5900) server manager
└── module/
    ├── action.sh         # Magisk / KernelSU / APatch UI action trigger
    └── module.prop       # Root module metadata properties
```

---

## 🛠️ Complete Command Reference

Both `asl` and `superkit` can be used interchangeably.

### 1. Interactive 3D Dashboard & Telemetry
```bash
asl                       # Open 3D terminal dashboard
asl dashboard             # Open interactive 3D terminal dashboard
asl overview              # Print concise live system status without dashboard
asl thermal               # Monitor battery & CPU/GPU thermal zone temperatures
```

### 2. Core Linux Subsystem Operations
```bash
asl start                 # Safely mount Linux chroot environment
asl shell                 # Enter root bash session inside chroot
asl exec <command>        # Execute a command inside chroot
asl status                # Inspect mount points, chroot storage, and process state
asl doctor                # Run environment pre-flight check
asl stop                  # Safely terminate GUI sessions and unmount chroot
asl install <pkgs>        # Install packages inside chroot via apt-get
asl search <query>        # Search available apt repositories
asl service <act> <svc>   # Manage background services (start|stop|restart|status)
asl snapshot create <name># Create instant point-in-time snapshot
asl snapshot list         # List available chroot snapshots
asl snapshot restore <name># Restore chroot from a saved snapshot
asl backup                # Create compressed backup archive
asl restore <file>        # Restore chroot from backup archive
asl aid setup             # Map Android host AID GIDs inside chroot
```

### 3. MoBox Gaming & Direct3D Engine
```bash
asl gpu                   # Display active Turnip/Mesa GPU hardware runtime profile
asl mode [gaming|performance|balanced] # Apply memory compaction & Turnip GPU tuning
asl setup-gaming          # Auto-install Wine64, Box64, DXVK, and VKD3D
asl game                  # Open interactive gaming menu
asl game run <exe>        # Execute Windows application via Box64 + Wine64
```

### 4. Termux-X11 Desktop, Themes & Remote Access
```bash
asl desktop start         # Launch hardware-accelerated XFCE4 desktop
asl desktop status        # Inspect active desktop session state
asl desktop stop          # Terminate current desktop session safely
asl desktop sync-apps     # Sync Debian app shortcuts to Termux
asl theme [dark|light|nord|dracula] # Switch GTK theme presets
asl resolution [720p|1080p|native] # Configure Termux:X11 display resolution
asl remote ssh [start|stop|status] # Manage SSH server (port 2222)
asl remote vnc [start|stop|status] # Manage x11vnc server (port 5900)
asl audio [start|stop|test] # PulseAudio server management
```

### 5. Termux & Android Host Bridge
```bash
asl wakelock [on|off|status] # Control CPU Wake Lock
asl open <file|url>         # Open file or URL in default Android host app
asl clip [copy|paste]       # Read or write Android system clipboard
asl toast <message>         # Send quick Android toast message
asl notify <title> <msg>    # Send Android notification banner
```

---

## 🔒 Safety & Isolation Guarantees

Standard chroot scripts often execute `mount --bind / /chroot` or bind Android system folders (`/system`, `/vendor`, `/apex`). On modern Android versions (Android 10 through 15+), this causes SELinux violations, mounting deadlocks, broken camera/audio daemons, and forced kernel panics.

**Android Subsystem for Linux (ASL)** enforces strict mount isolation:
- Shared access is provided strictly for user storage (`/sdcard`) and IPC sockets (`/tmp`).
- Mount points use `--make-rprivate` and `--make-rslave` flags to prevent mount events from leaking into the host Android OS.
- Host system integrity remains 100% protected.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for details.
