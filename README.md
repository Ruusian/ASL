# 🚀 Android Subsystem for Linux (ASL)

[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Termux-brightgreen.svg)](https://termux.dev)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64-blue.svg)](#)
[![Requirement](https://img.shields.io/badge/Requirements-Root%20(su)%20%2B%20Termux-red.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Android Subsystem for Linux (ASL)** (formerly AndroidLinux-SuperKit) is a high-performance, root-accelerated Linux chroot management subsystem and gaming container framework for Android ARM64. 

Modeled after **WSL (Windows Subsystem for Linux)** on PC, **ASL** turns your Android device into a full Linux workstation and gaming machine using only **Root (`su`)** and **Termux**.

It seamlessly bridges native **Debian Linux** environments with Android hardware acceleration (**Turnip Mesa Vulkan**, **Zink**, **VirGL**), high-performance **Box64 + Wine64** x86_64 emulation, and low-latency **Termux-X11 + PulseAudio** XFCE4 desktop integration.

---

## ⚡ One-Line Automated Installation

Install or update **ASL** instantly with a single command inside Termux:

```bash
curl -fsSL https://raw.githubusercontent.com/Ruusian5/AndroidLinux-SuperKit/master/install.sh | bash
```

Once installed, launch the interactive terminal dashboard by running:
```bash
asl
# or
superkit
```

---

## 🔥 Key Features

- 🛡️ **Zero-Crash Isolated Subsystem Core**: Uses isolated bind mounts (`--make-rprivate` and `--make-rslave`) without mounting Android host `/system`, `/vendor`, `/apex`, or `/linkerconfig`. Eliminates Android OS crashes, reboot loops, and background app terminations.
- 🎮 **MoBox Gaming & Direct3D Acceleration Engine**: Integrated **Turnip Mesa** Vulkan driver support for Qualcomm Adreno 6xx/7xx GPUs with DXVK 2.4+ async pipeline compilation, VKD3D Direct3D 12 translation, and Box64 dynarec stability flags tuned for Unity Mono C# garbage collection stack unwinding.
- 🖥️ **Termux-X11 & Desktop Suite**: Low-latency XFCE4 desktop session with PulseAudio sound server integration, window decorations, wallpaper configuration, and one-click app launcher synchronization.
- ⚡ **Auto-Hardware Detection & Performance Profiles**: Real-time GPU profile detection (`Adreno 6xx/7xx`, `Mali VirGL fallback`), kernel sysctl memory tuning (`vm.max_map_count=1048576`, `fs.inotify.max_user_watches=524288`), and glibc heap allocation optimizations (`MALLOC_ARENA_MAX=2`).
- 📸 **Point-in-Time Filesystem Snapshots & Backups**: Instant chroot Btrfs/Tar snapshot creation, point-in-time state restoration, and compressed `/sdcard/Debian_Backups` archives.
- 🌐 **Remote Access Bridge**: One-command management for background OpenSSH daemon (port 2222) and x11vnc server (port 5900).
- 🌡️ **Telemetry, Swap & Thermal Monitor**: Live battery telemetry, RAM & Swap memory headroom (ZRAM + Swapfile), CPU governor, and CPU/GPU thermal zone temperature monitoring.

---

## 📦 Repository Structure

```text
AndroidLinux-SuperKit/
├── install.sh            # One-line automated setup script for ASL
├── bin/
│   └── superkit          # Unified CLI entrypoint & dashboard (symlinked as 'asl')
├── core/
│   ├── mount-chroot.sh   # Safe isolated chroot mount manager
│   ├── stop-chroot.sh    # Safe unmount script
│   ├── doctor.sh         # Non-mutating environment diagnostics
│   ├── gpu-detect.sh     # SoC auto-detection & driver profile configuration
│   ├── thermal.sh        # Battery & CPU/GPU thermal zone monitor
│   └── snapshot.sh       # Point-in-time chroot snapshot manager
├── gaming/
│   └── wine-box64.sh     # Wine64, Box64, DXVK, winetricks & gaming setup tools
├── desktop/
│   ├── start-desktop.sh  # Termux-X11 desktop & PulseAudio launcher
│   ├── theme.sh          # GTK theme & Papirus icon set switcher
│   └── remote.sh         # SSH & VNC remote access manager
└── docs/                 # Detailed technical guides
```

---

## 🛠️ Complete Command Reference

Both `asl` and `superkit` can be used interchangeably in the terminal.

### 1. Interactive Dashboard & Telemetry
```bash
asl                       # Open full color-coded terminal dashboard
asl dashboard             # Open interactive terminal dashboard
asl overview              # Print concise live system status without dashboard
asl thermal               # Monitor battery & CPU/GPU thermal zone temperatures
```

### 2. Core Linux Chroot Operations
```bash
asl start                 # Safely mount Debian chroot environment
asl shell                 # Enter root bash session inside chroot
asl status                # Inspect mount points, chroot storage, and process state
asl doctor                # Run non-mutating environment pre-flight check
asl stop                  # Safely terminate GUI sessions and unmount chroot
asl install <pkgs>        # Install packages inside Debian via apt-get
asl search <query>        # Search available Debian apt repositories
asl service <act> <svc>   # Manage background services (start|stop|restart|status)
asl snapshot create <name> # Create instant point-in-time snapshot
asl snapshot list         # List available chroot snapshots
asl snapshot restore <name># Restore chroot from a saved snapshot
asl backup                # Create compressed backup in /sdcard/Debian_Backups
asl restore <file>        # Restore chroot from tar.gz backup file
```

### 3. MoBox Gaming & Direct3D 11/12 Engine
```bash
asl gpu                   # Display active Turnip/Mesa GPU hardware runtime profile
asl mode [gaming|performance|balanced] # Apply memory compaction & Turnip GPU tuning
asl setup-gaming          # Auto-install Wine64, Box64, DXVK 2.4, and VKD3D
asl game                  # Open interactive gaming launcher menu
asl game run <exe>        # Execute Windows application via Box64 + Wine64
```

### 4. Termux-X11 Desktop, Themes & Remote Access
```bash
asl desktop start         # Launch hardware-accelerated XFCE4 desktop
asl desktop status        # Inspect active desktop session state
asl desktop stop          # Terminate current desktop session safely
asl desktop sync-apps      # Generate X-SuperKit-Managed app shortcuts
asl theme [dark|light|nord|dracula] # Switch GTK theme & Papirus icon presets
asl resolution [720p|1080p|native] [scale] # Configure Termux:X11 display resolution
asl remote ssh [start|stop|status] # Manage SSH server on port 2222
asl remote vnc [start|stop|status] # Manage x11vnc server on port 5900
asl audio [start|stop|test|volume <0-100>] # PulseAudio server management
```

---

## 🎮 Game Optimization Highlights (Nine Sols & Unity Mono)

For heavy Windows 64-bit Unity Mono titles (such as *Nine Sols*), **ASL** includes specialized runtime flags:

- **Box64 Dynarec**: Configured with `BOX64_DYNAREC_STRONGMEM=2`, `BOX64_DYNAREC_CALLRET=0`, `BOX64_DYNAREC_FASTNAN=0`, and `BOX64_DYNAREC_SAFEFLAGS=2` to ensure stability during Mono C# JIT garbage collection and stack unwinding.
- **Turnip Mesa Vulkan**: Relocates shader caching to tmpfs (`/dev/shm/mesa_cache`) with `TU_DEBUG="sysmem,noconform"` to eliminate GMEM tile buffer resolves on Adreno GPUs.
- **System Memory Protection**: Automatically allocates dedicated swap files (`/data/local/tmp/swapfile`), applies `oom_score_adj=-1000` to game processes, and restricts glibc heap fragmentation via `MALLOC_ARENA_MAX=2`.
- **Windowed Input Fixes**: Applied `UseTakeFocus=N` and `GrabPointer=Y` in Wine X11 Driver registry to ensure proper keyboard and mouse event routing in windowed mode.

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
