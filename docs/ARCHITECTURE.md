# ASL (Android Subsystem for Linux) System Architecture

## Overview
ASL is an enterprise-grade, high-performance Linux container and subsystem management engine running on Android ARM64 devices via a native root-accelerated Linux kernel chroot environment (Magisk / KernelSU / APatch).

```
+-------------------------------------------------------------------+
|                        Android OS Core                            |
|               Kernel 4.14+ / Superuser Root (su)                  |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                   Termux Environment (~/ASL)                      |
|    - asl CLI dispatcher & core/common.sh execution layer          |
|    - PulseAudio server (127.0.0.1:4713)                           |
|    - Termux:X11 display server (:0)                               |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|     Multi-Distro Linux Subsystem RootFS (/data/local/tmp/...)    |
|   (Debian Modded / Trixie, Ubuntu 24.04, Arch, Alpine, Kali)      |
|    - Mesa Turnip Vulkan + Zink OpenGL/Vulkan Driver Stack         |
|    - Systemd Emulation Engine & Custom Desktop Environments       |
+-------------------------------------------------------------------+
```

## Root-Accelerated Kernel Architecture (`core/common.sh`)
ASL operates on a native Linux kernel chroot execution model with Superuser privileges (Magisk / KernelSU / APatch):
1. **Root Kernel Chroot (`su`)**: Direct kernel mounting with full `/dev/kgsl-3d0` and `/dev/dri/*` hardware GPU acceleration, direct memory management, and zero translation overhead.
2. **Dynamic DNS Synchronization**: Dynamically extracts active Android nameservers (`net.dns*`, `net.wlan0.dns*`, `net.rmnet_data*.dns*`) and synchronizes into Debian `/etc/resolv.conf`.
3. **Android 12+ PPK Watchdog**: Automatically overrides Android Phantom Process Killer restrictions via `device_config` to prevent OS process reaping.
4. **Machine-ID & D-Bus Provisioning**: Automatically ensures `/etc/machine-id` and D-Bus sockets are initialized for GTK4/Wayland/X11 compatibility.

Subsystem execution is transparently routed via helper functions:
- `asl_detect_mode()`: Validates native container (`direct`) or root Superuser (`root`) environment.
- `asl_exec()`: Runs commands in host environment with root privileges.
- `asl_chroot_exec()`: Executes commands inside target Linux subsystem rootfs.

## Critical System Invariants

### 1. Mount Safety & Error Rollback Invariant
- **Requirement:** Mount managers (`core/mount-chroot.sh`) enforce private bind mounts (`--make-rprivate` and `--make-rslave`) without mounting host Android system partitions (`/system`, `/vendor`, `/apex`).
- **Rollback Trap:** Implements `trap cleanup_on_error ERR` to automatically unmount partially mounted filesystems if an error occurs during initialization.

### 3. Graphics Driver Stack (Turnip + Zink)
- **Vulkan ICD:** `/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json`
- **Render Node Detection:** Scans `/dev/kgsl-3d0`, `/dev/dri/renderD128`, and `/dev/dri/card0` for Adreno GPU hardware nodes.
- **OpenGL Layer:** Zink OpenGL-over-Vulkan implementation (`GALLIUM_DRIVER=zink`, `MESA_LOADER_DRIVER_OVERRIDE=zink`)
- **Direct3D:** Native DXVK (D3D9-D3D11) and VKD3D-Proton (D3D12) mapping directly onto Turnip Vulkan.

### 4. Memory and Swap Topology
- **ZRAM:** 2.0 GB compressed zram swap (`/dev/block/zram0`)
- **File Swap:** 2.0 GB swap file (`/data/swapfile`)
- **Total Active Swap:** 4.0 GB tuned for Android gaming stability without excessive storage wear (capped at 5.0 GB limit).
- **Swappiness Target:** `vm.swappiness=10` during active gaming session to protect low latency execution.

### 5. Runtime vs Source Repository Separation
- **Source Repository (`~/ASL`):** Houses git tracking, source development tree, test suites, and documentation.
- **Installed Runtime (`$PREFIX/share/asl`):** Dedicated system installation target deployed by `install.sh`.
- **Binary Symlink (`$PREFIX/bin/asl`):** Points to `$PREFIX/share/asl/bin/asl` and resolves paths dynamically via `readlink -f`.
- **Subshell Detachment:** Background daemons spawn via `((nohup bash ... &) &) 2>/dev/null` to prevent shell job control notifications.

### 6. Terminal Display & TUI Architecture
- **DEC Mode 1049 Buffer (`\033[?1049h` / `\033[?1049l`):** TUI views (`dashboard`, `watch`, `process_manager`) run in the terminal's alternate screen buffer. Screen redraws and timer ticks do not leak into the terminal scrollback history.
- **74-Column Box Drawing Grid:** UI frames are strictly constrained to 74 columns with ANSI escapes formatted outside string measurement routines to ensure pixel-perfect rendering across terminal emulators.

### 7. OmniRoute AI Gateway & Android Netd Bypass
- **Local Proxy Endpoint:** Runs on `127.0.0.1:20128` to bridge local LLM clients with backend AI inference providers.
- **Android Netd Bypass:** On Android 14+, non-root app UIDs (like Termux UID `10566`) are subject to strict `netd` resolver filtering. OmniRoute is managed under root execution with explicit Termux library paths (`LD_LIBRARY_PATH`) and host `/etc/resolv.conf` fallback.

### 8. Modular 24/7 Remote Mesh Architecture
- **Host-Only SSH Management:** Termux host OpenSSH server runs on port 8022 under user permissions (`u0_a566`) with key/password authentication.
- **Dedicated Oracle / VPS Reverse Tunnel:** Persistent SSH reverse relay to user-configured VPS (`asl remote oracle setup`) routing Port 2222 -> Termux SSH (8022).
- **Adaptive Jump-Host & On-Demand Pool:** Automatic fallback to Serveo reverse tunnels and on-demand Ngrok token rotation pools with automatic quota tracking.
- **24/7 Watchdog:** Self-healing health check running every 180s to maintain tunnel persistence without excessive battery/CPU drain.

