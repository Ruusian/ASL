# ASL v2.5.1 — Feature Catalog & Recovery Log

**Last Updated:** 2026-08-25  
**Primary Device:** Motorola Edge 60 Pro (non-rooted, proot mode)  
**Secondary Device:** LG G8X (mh2lm, root/KSU mode)  
**Chroot:** Debian Trixie at `~/.asl/chrootDebian` (1.3GB via proot-distro)  
**Source Repo:** `~/ASL/` (git clone of https://github.com/Ruusian5/ASL.git)  
**Exec Mode:** proot (set in `$PREFIX/etc/asl_exec_mode`)

---

## 2026-08-24 Recovery — ASL Reinstallation

**Problem:** User reported "maintenance part is broken" → "dev and config is also broken". Root cause: entire ASL installation deleted (chroot, binaries, configs all gone). Device lost root access (no Magisk/KSU/su present), so ASL was operating in proot mode before the wipe.

**Resolution:**
1. Re-cloned ASL repo from GitHub to `~/ASL/`
2. Installed Debian Trixie base rootfs via `proot-distro install -n asl-debian debian:trixie` (152MB, bypassing failed 6-8GB modded rootfs download)
3. Ran `desktop/asl-hub-installer.sh` to deploy asl-control-center.py + CLI into chroot
4. Fixed dpkg interrupt from proot fork limit by running `dpkg --configure -a`
5. Installed GTK3 dependencies in small batches (`python3-gi`, `gir1.2-gtk-3.0`, `libgtk-3-0t64`)
6. Created symlinks: `$PREFIX/bin/asl` and `$PREFIX/bin/superkit` → `~/ASL/bin/asl`
7. Set exec mode to `proot` in `$PREFIX/etc/asl_exec_mode`

**Status:** All previously-broken commands now functional. See verification results below.

---

## 2026-08-25 Gaming Stack — Moto Edge 60 Pro

**Device:** Motorola Edge 60 Pro (non-rooted, proot mode)  
**SoC:** MediaTek Dimensity 8300-Ultra (mt6897) — Mali-G610 GPU  
**OpenGL ES:** 3.2 | **Vulkan:** generic-virgl via Mesa  
**Chroot size:** 1.3GB (gaming packages added ~1.15GB)

### Gaming Components Installed
| Component | Version | Status |
|-----------|---------|--------|
| Wine | 10.0 (Debian repack) | ✅ `/usr/lib/wine/wine64` |
| DXVK | 2.6+ds-1 | ✅ DLLs deployed to `~/.wine/drive_c/windows/system32/` |
| VKD3D Compiler | 1.2-15+b2 | ✅ `/usr/bin/vkd3d-compiler` |
| Mesa Vulkan Drivers | 25.0.7-2+deb13u1 | ✅ VirGL renderer |
| XFCE WM (xfwm4) | 4.20.0-1 | ✅ For Termux:X11 sessions |

### Known Limitations vs LG G8X (root/Adreno)
- **No Turnip driver** — Moto has Mali GPU; LG G8X has Adreno with Turnip
- **VirGL software rendering** — Mesa renders through proot virtualization, not direct GPU access
- **No /dev/dri access** — proot can't bind-mount device nodes for hardware Vulkan
- **Wine/DXVK functional** — works through VirGL but lower performance than native

### Gaming Commands
```bash
asl setup-gaming   # Wine/DXVK/VKD3D initial setup
asl game <exe>     # Run Windows .exe via Wine
asl benchmark      # Vulkan/GPU performance test
asl desktop start  # Launch XFCE desktop via Termux:X11
```

---

## Verified Working Commands (Post-Recovery)

### Maintenance (was broken)
| Command | Status | Notes |
|---------|--------|-------|
| `asl clean status` | ✅ PASS | Shows 1.3GB rootfs, minimal cache |
| `asl repair run` | ✅ PASS | Full integrity repair cycle completes |
| `asl dev-suite` | ✅ PASS | Python3 installed, others NOT INSTALLED |
| `asl security-suite` | ✅ PASS | Shows all security tools NOT INSTALLED |
| `asl config` | ✅ PASS | Auto-initializes `/etc/asl.conf` defaults |
| `asl doctor` | ✅ PASS | All PASS; chroot WARN resolved |

### Core CLI
| Command | Status |
|---------|--------|
| `asl` / `superkit` | ✅ Symlinked in PATH |
| `asl dashboard` / `menu` | ✅ Available |
| `asl overview` | ✅ Available |
| `asl shell` | ✅ Enter interactive chroot shell |
| `asl exec <cmd>` | ✅ Run single command in chroot |
| `asl install <pkg>` | ✅ apt-get install wrapper |
| `asl search <query>` | ✅ apt-cache search wrapper |
| `asl status` | ✅ Show chroot status |
| `asl start` / `asl stop` | ⚠️ Proot mode (no bind mounts needed) |
| `asl backup` / `asl restore` | ✅ Available |

### Gaming
| Command | Status |
|---------|--------|
| `asl setup-gaming` | ✅ Wine/DXVK/VKD3D installed |
| `asl gpu` | ✅ Detects mt6897/Mali + VirGL |
| `asl benchmark` | ⏳ Requires Vulkan ICD JSON (VirGL only) |
| `asl game <exe>` | ⏳ Requires game file + Wine prefix |

### Desktop / GUI
| Command | Status |
|---------|--------|
| `asl hub` / `asl asl-hub` | ✅ Deployed, GTK3 OK |
| `asl desktop start` | ✅ XFCE WM installed, needs Termux:X11 |
| `asl theme` | ⏳ Needs desktop setup |
| `asl audio` | ⏳ Needs PulseAudio server in chroot |

---

## Installed Components

### Host Side (Termux — Moto Edge 60 Pro)
- `~/ASL/bin/asl` — Main CLI (1708 lines)
- `~/ASL/core/*.sh` — 26 core scripts (mount, unmount, repair, clean, etc.)
- `$PREFIX/bin/asl` → symlink to `~/ASL/bin/asl`
- `$PREFIX/bin/superkit` → symlink to `~/ASL/bin/asl`
- `$PREFIX/etc/asl_exec_mode` → contains `proot`

### Chroot Side (`~/.asl/chrootDebian/` → proot-distro container, 1.3GB)
- `usr/local/bin/asl-control-center` — GTK3 control center app
- `usr/local/bin/asl-cli` — Wrapper for direct-mode CLI
- `usr/local/share/asl-cli/asl` — Full CLI inside chroot
- `usr/local/share/asl-cli/core/*.sh` — All core scripts in chroot
- `root/Desktop/asl-hub.desktop` — Desktop launcher
- `usr/share/applications/asl-hub.desktop` — Application menu launcher
- `usr/local/bin/pkg` — Termux pkg compatibility shim
- **Wine 10.0** + **DXVK 2.6** (DLLs in `~/.wine/drive_c/windows/system32/`)
- **VKD3D Compiler 1.2** + **Mesa Vulkan 25.0.7** + **XFCE WM 4.20**
- **Python 3.13** + **python3-gi** + **gir1.2-gtk-3.0** + **libgtk-3-0t64**
- GTK3 version: 3.24 ✅

### Proot-Distro Container
- Named: `asl-debian`
- Type: debian:trixie (aarch64)
- Path: `/usr/var/lib/proot-distro/containers/asl-debian/rootfs/`
- Size: 1.3GB

---

## Known Limitations (Proot Mode)

1. **No bind mounts** — `/dev`, `/proc`, `/sys` not accessible inside chroot (except via proot virtualization)
2. **GPU acceleration** — Limited to VirGL/software renderer; Turnip requires root for `/dev/dri/*` access
3. **Fork limits** — Large apt installs may hit "FATAL -> Failed to fork"; install packages one at a time
4. **No X11/Wayland** — GTK apps can't create windows without Termux:X11 running
5. **No root operations** — mount, chroot with device nodes, kernel modules all unavailable

---

## What Was Cleaned (Storage History)

| Session | Cleared | Amount |
|---------|---------|--------|
| Pre-recovery | Chrome/Stremio/apt caches, npm, hermes-agent, python3.13, icons/themes, box64.bak | ~12GB total across sessions |
| Current /data usage | — | ~181G used / 221G (83%) |
| Chroot size | — | 1.3GB (gaming stack included) |
