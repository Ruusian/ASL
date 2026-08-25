# ASL Gaming & Wine Acceleration Guide

## Execution Environment & Hardware Acceleration
ASL provides Direct3D 9/10/11/12 gaming acceleration across Root (`su`), Shizuku (`rish`), and PRoot execution modes:
- **Root Mode (`su`)**: Direct GPU node access (`/dev/kgsl-3d0`, `/dev/dri/*`) for raw Turnip Mesa Vulkan performance.
- **Shizuku & PRoot Modes**: Hardware acceleration via Zink and VirGL renderers depending on device kernel permissions.

---

## Wine Prefix & Execution Topology
ASL manages Wine 64-bit applications under Box64 dynamic binary translation.

### Default Prefix Routing
- **Default System Prefix:** `/root/.wine` (or configurable via `WINEPREFIX`)

When executing an application:
```bash
# Launch any Windows .exe directly
asl game /sdcard/Games/MyGame/game.exe

# Or specify a custom prefix
WINEPREFIX=/root/.wine-custom asl game /sdcard/Games/MyGame/game.exe
```

---

## Box64 Dynarec Precision Tuning Profile
Toggle dynamic recompilation precision presets between high frame rate and compatibility:

```bash
# Maximize performance (Fast mode: FASTROUND=1, FASTNAN=1, X87DOUBLE=0)
asl game precision fast

# High Precision compatibility mode (Safe mode: FASTROUND=0, FASTNAN=0, X87DOUBLE=1)
asl game precision safe

# Inspect active dynarec precision profile
asl game precision status
```

---

## DXVK & Vulkan Translation Setup
DXVK translates Direct3D 9, 10, and 11 calls directly to Vulkan. VKD3D-Proton translates Direct3D 12 calls to Vulkan.

### Enabling DXVK Configuration
```bash
# Configure DXVK async translation in /etc/dxvk.conf
asl dxvk enable

# Check DXVK configuration status
asl dxvk status
```

---

## Wine Engine Switching (`asl wine-version`)
Switch the active Wine binary between Debian system-wine and Proton-GE:

```bash
# Check current active Wine engine
asl wine-version status

# Switch to Proton-GE custom engine
asl wine-version set proton-ge

# Switch to standard Debian system Wine
asl wine-version set system-wine

# Install latest Proton-GE release
asl wine-version install proton-ge
```

---

## Offline Wine Mono & Gecko Bundles (`asl wine-bundle`)
Download and package offline MSI installers for .NET Framework and MSHTML runtimes:

```bash
# Install offline MSI bundles
asl wine-bundle install

# Check bundle status
asl wine-bundle status

# Clean bundles
asl wine-bundle clean
```

---

## Bluetooth & Wireless Gamepad Passthrough (`asl gamepad`)
Synchronize Android `/dev/input/event*` wireless and USB controllers directly into the subsystem:

```bash
# Detect connected controllers
asl gamepad status

# Sync gamepad nodes into chroot /dev/input
asl gamepad sync

# Interactive input calibration test
asl gamepad test
```

---

## Real-Time Performance HUD Telemetry (`asl hud`)
Toggle MangoHud and DXVK_HUD telemetry overlay displaying FPS, CPU/GPU temperatures, and RAM/VRAM:

```bash
# Enable performance overlay
asl hud on

# Disable performance overlay
asl hud off

# Toggle overlay state
asl hud toggle
```

---

## Subsystem Backup & Restore (`asl backup`)
Back up and restore your complete Linux subsystem rootfs:

```bash
# Create full compressed backup of Debian rootfs
asl backup

# Restore rootfs from backup archive
asl restore /sdcard/Download/asl-backup.tar.xz
```
