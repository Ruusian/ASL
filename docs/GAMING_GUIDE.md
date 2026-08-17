# ASL Gaming & Wine Isolation Guide

## Execution Environment & Hardware Acceleration
ASL provides Direct3D 9/10/11/12 gaming acceleration across Root (`su`), Shizuku (`rish`), and PRoot execution modes:
- **Root Mode (`su`)**: Direct GPU node access (`/dev/kgsl-3d0`, `/dev/dri/*`) for raw Turnip Mesa Vulkan performance.
- **Shizuku & PRoot Modes**: Hardware acceleration via Zink and VirGL renderers depending on device kernel permissions.

---

## Wine Prefix & Directory Isolation Topology
ASL isolates Wine applications to prevent DLL conflicts and corrupted game configurations across titles.

### Default Prefix Routing
- **Default System Prefix:** `/root/.wine-x64`
- **Isolated Game Prefixes:** `/root/.wine-prefixes/<GameDirectoryName>`

When an `.exe` file inside `/opt/games/<GameName>/...` or `/sdcard/Games/<GameName>/...` is launched:
1. `asl-wine-launch` extracts the root folder name of the game (`<GameName>`).
2. Checks if a local `.wineprefix` or `wineprefix.txt` override file exists in the executable's directory.
3. Automatically sets `WINEPREFIX=/root/.wine-prefixes/<GameName>` and initializes the prefix if missing.

### Custom Prefix Overrides
To force a game or application into a custom prefix, create a file named `.wineprefix` in the game directory containing the absolute path:
```bash
echo "/root/.wine-prefixes/MyCustomGame" > /opt/games/MyGame/.wineprefix
```

---

## Box64 Dynarec Precision Tuning Profile
Toggle dynamic recompilation precision presets between high frame rate and crash recovery:

```bash
# Maximize performance (Fast mode)
asl game precision fast

# High Precision compatibility mode (Safe mode for float/NaN sensitive titles)
asl game precision safe

# Inspect active dynarec precision profile
asl game precision status
```

---

## DXVK & VKD3D-Proton Setup
DXVK translates Direct3D 9, 10, and 11 calls directly to Vulkan. VKD3D-Proton translates Direct3D 12 calls to Vulkan.

### Enabling DXVK for a Prefix
```bash
# Enable DXVK for default prefix
asl dxvk enable

# Enable DXVK for a specific game prefix
WINEPREFIX=/root/.wine-prefixes/MyGame asl dxvk enable
```

### DXVK Status Check
```bash
asl dxvk status
```

---

## AMD FSR Fullscreen & Resolution Scaling
ASL includes built-in AMD FidelityFX Super Resolution (FSR) support via `asl-wine-launch`.

- **Default Resolution:** `1280x720` upscaled to native display.
- **Custom Resolution:** Pass `ASL_RES` prior to running:
  ```bash
  ASL_RES=1600x900 asl game /opt/games/MyGame/game.exe
  ```

---

## Steam & x86_64 Launcher Integration
Run x86_64 launchers (Steam, Heroic, GOG) using optimized Box64 Dynarec flags.

```bash
# Launch Steam environment
asl steam

# Launch specific Windows setup or launcher package
asl steam /sdcard/SteamSetup.exe
```

---

## Game Save & Prefix Backup System (`asl-backup`)
Back up saves and AppData directly to compressed `.tar.gz` archives in `/sdcard/ASL_Backups`.

### Backup Commands
```bash
# Back up default AppData
asl backup save default

# Back up a specific game prefix
asl backup save MyGame

# Back up all Wine prefixes
asl backup save all

# List existing backups
asl backup list

# Restore a backup archive
asl backup restore /sdcard/ASL_Backups/asl_backup_MyGame_20260817_150000.tar.gz
```
