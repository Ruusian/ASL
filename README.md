# AndroidLinux-SuperKit 🚀

A comprehensive, safe, root-accelerated Linux environment for Android combining:
- 🛡️ **Zero-Crash Native Chroot Management Core** (Isolated mounts, `--make-rprivate` / `--make-rslave`, safe `/sdcard` sharing, no host OS degradation)
- 🎮 **Modular Gaming & Hardware Acceleration Engine** (Native Turnip + Zink + VirGL acceleration with optional Box64/Wine support)
- 🖥️ **Termux-Desktops-Inspired GUI Engine** (XFCE4 Desktop + PulseAudio audio integration via Termux-X11)
- ⚡ **Auto-Hardware Detection & Tuning** (Adreno 6xx/7xx Turnip+Zink auto-config, Snapdragon 8 Gen 1 flicker fixes, Mali VirGL fallbacks)

---

## 📦 Directory Structure

```
AndroidLinux-SuperKit/
├── bin/
│   └── superkit          # Unified CLI entrypoint
├── core/
│   ├── mount-chroot.sh   # Safe, isolated mount script
│   ├── stop-chroot.sh    # Safe unmount script
│   ├── doctor.sh         # Non-mutating environment diagnostics
│   ├── gpu-detect.sh     # Auto-detect SoC and config drivers
│   ├── thermal.sh        # Battery & CPU/GPU thermal monitor
│   └── snapshot.sh       # Fast point-in-time chroot snapshots
├── gaming/
│   └── wine-box64.sh     # MoBox gaming layer & auto-setup helpers
├── desktop/
│   ├── start-desktop.sh  # Desktop & audio launcher
│   ├── theme.sh          # Desktop look & feel switcher
│   └── remote.sh         # SSH & VNC remote access manager
├── docs/                 # Documentation & guides
└── README.md
```

---

## 🛠️ Usage Quick Reference

### Interactive Dashboard
```bash
superkit                  # Open the full interactive terminal dashboard
# or
superkit dashboard
```

The dashboard groups system, Debian, desktop/audio, and gaming/maintenance actions, with a live color-coded overview of chroot, desktop, X11 socket, audio, and GPU-profile state. Press `r` to refresh it. Set `NO_COLOR=1` to disable colors.

```bash
superkit overview          # Print the concise live overview without opening the dashboard
superkit thermal           # Display battery and CPU/GPU thermal zone temperatures
```

### Core Chroot Operations
```bash
superkit start            # Mount chroot safely
superkit shell            # Enter chroot bash session as root
superkit status           # Check status, storage size, and active sub-mounts
superkit doctor           # Check prerequisites without changing state
superkit stop             # Stop SuperKit desktop, then unmount safely
superkit install <pkgs>   # Install Debian packages directly via apt-get
superkit search <query>   # Search available Debian packages
superkit service <act> <svc> Manage Debian background services (start|stop|restart|status)
superkit snapshot [create|list|restore|delete] <name> Fast chroot snapshots
superkit backup           # Backup chroot to /sdcard/Debian_Backups
superkit restore <file>   # Restore chroot from backup
```

### MoBox Gaming Layer & Performance
```bash
superkit gpu              # Report the safe selected GPU runtime profile
superkit mode [gaming|performance|balanced] # Tune memory compaction & Turnip GPU flags
superkit setup-gaming     # Auto-install Wine, Box64, DXVK, and VKD3D dependencies
superkit game             # Open interactive gaming launcher
superkit game run <exe>   # Run a Windows executable (requires Wine / Box64 packages)
```

### Termux-Desktops GUI, Theme & Remote Access
```bash
superkit desktop start    # Launch SuperKit-managed XFCE4 desktop
superkit desktop status   # Check managed desktop state
superkit desktop stop     # Stop only the managed session
superkit desktop sync-apps # Generate SuperKit-owned Termux launchers
superkit theme [dark|light|nord|dracula] # Switch XFCE GTK and Papirus icon presets
superkit resolution [720p|1080p|native] [scale] # Configure Termux:X11 display resolution
superkit remote [ssh|vnc] [start|stop|status] # Manage SSH (port 2222) & VNC (port 5900)
superkit audio [start|stop|test|volume <0-100>] # PulseAudio server management & volume control
```

The GPU profile is selected from allowlisted hardware profiles and is applied to desktop and Wine launches. Generated launchers live in the Termux applications directory, are marked `X-SuperKit-Managed=true`, and are the only launchers synchronization removes.

---

## 🔒 Safety & OS Stability Guarantees

Unlike naive chroot scripts, **AndroidLinux-SuperKit** does **NOT** bind-mount host Android `/system`, `/vendor`, `/apex`, or `/linkerconfig`. This prevents Android application crashes and kernel panics on Android 10+ while retaining full native chroot performance and GPU hardware acceleration.
