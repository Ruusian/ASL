# ASL (Android Subsystem for Linux) System Architecture

## Overview
ASL is a high-performance Linux container and gaming layer running on Android ARM64 devices via Debian chroot and Termux environment integration.

```
+-------------------------------------------------------------------+
|                        Android OS Core                            |
|             Kernel 4.14 (Myth-V2) / Root (KernelSU/su)            |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|                   Termux Environment (~/ASL)                      |
|    - asl CLI dispatcher                                           |
|    - PulseAudio server (127.0.0.1:4713)                           |
|    - Termux:X11 display server (:0)                               |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|            Debian 13 (Trixie) ARM64 RootFS (/data/local/tmp/...) |
|    - Box64 ARM64 -> x86_64 Dynarec Execution                      |
|    - Wine 64-bit Windows Binary Runtime                           |
|    - Mesa Turnip Vulkan + Zink D3D-to-Vulkan Driver              |
|    - GTK3 GUI (asl-gui using os.posix_spawn)                     |
+-------------------------------------------------------------------+
```

## Critical System Invariants

### 1. Process Spawning Invariant (`os.posix_spawn`)
- **Requirement:** Any Python / GTK3 desktop interface (`asl-gui`) running inside the chroot **MUST** use `os.posix_spawn` (`safe_spawn`) to spawn subprocesses.
- **Why:** GTK3 initializes background GMainLoop event threads. Under PRoot/chroot environments on Android Linux 4.14 kernels, standard `os.fork()` / `subprocess.Popen` deadlocks in glibc `atfork` handlers and causes child processes to lock up at 100% CPU utilization.
- **Implementation:** Custom `safe_spawn()` helper function defined in `/usr/local/bin/asl-gui`.

### 2. Graphics Driver Stack (Turnip + Zink)
- **Vulkan ICD:** `/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json`
- **OpenGL Layer:** Zink OpenGL-over-Vulkan implementation (`GALLIUM_DRIVER=zink`, `MESA_LOADER_DRIVER_OVERRIDE=zink`)
- **Direct3D:** Native DXVK (D3D9-D3D11) and VKD3D-Proton (D3D12) mapping directly onto Turnip Vulkan.

### 3. Memory and Swap Topology
- **ZRAM:** 2.0 GB compressed zram swap (`/dev/block/zram0`)
- **File Swap:** 2.0 GB swap file (`/data/swapfile`)
- **Total Active Swap:** 4.0 GB tuned for Android gaming stability without excessive storage wear.
- **Swappiness Target:** `vm.swappiness=10` during active gaming session to protect low latency execution.
