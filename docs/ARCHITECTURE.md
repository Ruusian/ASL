# ASL (Android Subsystem for Linux) System Architecture

## Overview
ASL is a universal, high-performance Linux container and subsystem management engine running on Android ARM64 devices across Root (`su`), Shizuku (`rish`), and PRoot execution modes.

```
+-------------------------------------------------------------------+
|                        Android OS Core                            |
|        Kernel 4.14+ / Root (su) | Shizuku (rish) | PRoot          |
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
|    - GTK3 GUI Control Center (asl-hub using os.posix_spawn)       |
+-------------------------------------------------------------------+
```

## Universal 3-Tier Execution Architecture (`core/common.sh`)
ASL abstracts execution environment differences into a unified interface through `core/common.sh`:
1. **Root Mode (`su`)**: Native Linux kernel chroot with direct GPU node access (`/dev/kgsl-3d0`, `/dev/dri/*`) delivering maximum performance.
2. **Shizuku Mode (`rish`)**: ADB-privileged execution mode (UID 2000) for non-rooted devices running Shizuku, bypassing standard app process restrictions.
3. **PRoot Mode**: Pure user-space syscall translation via `proot-distro` for non-rooted Android devices without Shizuku.

Subsystem execution is transparently routed via helper functions:
- `asl_detect_mode()`: Auto-detects available device capabilities or reads persistent config (`$PREFIX/etc/asl_exec_mode`).
- `asl_exec()`: Runs commands in host environment with active execution privileges.
- `asl_chroot_exec()`: Executes commands inside target Linux subsystem rootfs under active execution mode.

## Critical System Invariants

### 1. Process Spawning Invariant (`os.posix_spawn`)
- **Requirement:** Any Python / GTK3 desktop interface (`asl-gui` / `asl-hub`) running inside the rootfs **MUST** use `os.posix_spawn` (`safe_spawn`) to spawn subprocesses.
- **Why:** GTK3 initializes background GMainLoop event threads. Under PRoot/chroot environments on Android Linux kernels, standard `os.fork()` / `subprocess.Popen` deadlocks in glibc `atfork` handlers and causes child processes to lock up at 100% CPU utilization.
- **Implementation:** Built-in `os.posix_spawn` process runner inside `desktop/asl-hub-installer.sh` (`asl-control-center`).

### 2. Mount Safety & Error Rollback Invariant
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

