# Getting Started with ASL

This guide will help you get up and running with Android Subsystem for Linux (ASL) in minutes.

---

## Prerequisites

Before installing ASL, ensure you have:

- ✅ **Android Device** with root access (Magisk, KernelSU, or APatch), Shizuku, or standard Termux
- ✅ **Termux** installed from F-Droid or GitHub Releases
- ✅ **Storage Space** - At least 5GB free for Linux subsystem rootfs + applications

### Quick Prerequisites Check

Run this in Termux to verify everything:

```bash
su -c "id | grep -q 'uid=0' && echo '✓ Root access OK' || echo '✗ Root access not detected'"
which termux-setup-storage
```

---

## 🚀 Installation (5 Minutes)

### Step 1: Install ASL

Open **Termux** and run:

```bash
# Recommended CDN Mirror (bypasses raw GitHub HTTP 429 rate limits):
curl -fsSL https://cdn.jsdelivr.net/gh/Ruusian/ASL@master/install.sh | bash
```

Or install via Git clone:

```bash
git clone https://github.com/Ruusian/ASL.git
cd ASL
bash install.sh
```

### Step 2: Choose Rootfs Edition

During installation, you can select the Linux distribution flavor:

- **Debian Modded [RECOMMENDED]**: Turnip Mesa Vulkan, GPU Drivers, XFCE4 desktop pre-configured.
- **Clean Debian Trixie Base**: Minimal official Debian Trixie arm64 rootfs.
- **Ubuntu 24.04 LTS Base**: Clean Ubuntu Noble arm64 base.
- **Arch / Kali / Alpine Base**: Alternative Linux distributions.

### Step 3: Verify Installation

Test the installation:

```bash
asl doctor
```

Expected output:
```
exec-mode      PASS  su grants root access (ROOT mode)
debian-root    PASS  /data/local/tmp/chrootDebian exists
chroot         WARN  not mounted; chroot checks skipped (run: asl start)
termux-x11     PASS  client installed
pulseaudio     PASS  client installed
storage        PASS  /sdcard is writable
gpu            PASS  profile=turnip; host GPU node present
```

---

## 🎮 Quick Start Workflows

### Workflow 1: Launch Interactive Dashboard

```bash
asl
```

This opens the interactive 74-column alternate-screen buffer TUI dashboard with real-time system stats.

**Key hotkeys**:
- `s` - Start / mount subsystem
- `x` - Stop / unmount subsystem  
- `d` - Start XFCE desktop session (Termux:X11)
- `g` - Launch Windows executable / Game Hub
- `p` - Process manager
- `t` - Thermal & battery monitor
- `h` - Toggle HUD telemetry overlay
- `v` - Remote bridge endpoints
- `c` - Clean storage & caches
- `r` - Integrity self-repair
- `q` - Quit

### Workflow 2: Mount Debian & Enter Shell

```bash
# Start chroot (mount Debian)
asl start

# Enter root shell inside subsystem
asl shell

# Now you're in Linux!
apt-get update
apt-get install -y git build-essential
```

### Workflow 3: Run a Single Command

```bash
# Execute command without entering shell
asl exec "uname -a"

# Run with arguments
asl exec "gcc --version"
```

### Workflow 4: Start Desktop Environment

```bash
# Start XFCE desktop with Termux:X11
asl desktop start

# Check remote connection endpoints
asl remote status

# Stop desktop when done
asl desktop stop
```

### Workflow 5: Run Windows Applications & Games

```bash
# Start subsystem
asl start

# Open interactive Gaming & Host Apps Hub
asl game

# Or run any .exe directly
asl game /sdcard/Games/MyGame/game.exe
```

---

## 📚 Common Commands

### Subsystem Management

```bash
asl start              # Mount Debian chroot
asl stop               # Unmount subsystem
asl status             # Show subsystem status
asl shell [user]       # Enter interactive shell (default: root)
asl exec <cmd>         # Run single command
asl install <pkg...>   # Install Debian packages
asl search <query>     # Search available packages
```

### Snapshots & Backups

```bash
asl snapshot create daily    # Create snapshot named "daily"
asl snapshot list            # List all snapshots
asl snapshot restore daily   # Restore from snapshot
asl snapshot delete daily    # Delete snapshot
asl snapshot export daily    # Export to .tar.zst archive
asl backup                   # Full chroot backup
```

### Desktop & Resolution

```bash
asl desktop start      # Start XFCE + Termux:X11
asl desktop stop       # Stop desktop
asl theme dark         # Set dark theme
asl resolution 1080p   # Set 1080p resolution
asl remote lan start   # Start LAN SSH server
asl remote oracle start# Connect to dedicated VPS tunnel
```

### Graphics & Performance

```bash
asl gpu apply          # Detect and apply GPU acceleration
asl turbo              # Set CPU/GPU governor to performance
asl mode balanced      # Set CPU governor to balanced
asl hud on             # Enable MangoHud overlay
```

### Diagnostics

```bash
asl doctor             # Health check
asl overview           # Show system overview
asl thermal            # Monitor thermal/battery
asl thermal watch      # Live thermal monitor
asl ps                 # Process manager
```

### Android Host Integration

```bash
asl aid                # Map Android ID groups
asl wakelock on/off    # CPU wake lock
asl open <file>        # Open file in Android host app
asl clip copy/paste    # Clipboard bridge
asl toast "Message"    # Android notification
asl shortcut <app>     # Create Android home screen shortcut
```

---

## ⚙️ Configuration

### Environment Variables

Set in container `/etc/profile` or host `~/.bashrc`:

```bash
# Display server
export DISPLAY=:0

# PulseAudio TCP server
export PULSE_SERVER=127.0.0.1:4713
```

### Files & Locations

```
/data/local/tmp/chrootDebian      # Debian rootfs container
/data/local/tmp/.asl-snapshots/   # Snapshot storage
$PREFIX/etc/asl_exec_mode         # Execution mode configuration
$PREFIX/etc/asl.conf              # System declarative configuration
/sdcard/                          # Android storage (shared)
```

---

## 🔧 Troubleshooting

### Chroot Won't Start

```bash
# Check what's wrong
asl doctor

# Force stop and clean stale mounts
asl repair mounts

# Re-attempt startup
asl start
```

### Performance Optimization

```bash
# Set gaming profile (CPU governor performance)
asl mode gaming

# Setup 5GB virtual swap pool
asl swap setup 5G

# Optimize memory and drop caches
asl swap optimize

# Monitor temperatures
asl thermal watch
```

### Graphics Diagnostics

```bash
# Check GPU detection
asl doctor

# Run GPU and Vulkan benchmark
asl game benchmark
```

### Desktop Issues

```bash
# Stop desktop cleanly
asl desktop stop

# Refresh Termux:X11 socket
asl desktop refresh-x11

# Restart desktop session
asl desktop start
```

---

## 📖 Next Steps

- **Read [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md)** for complete CLI syntax
- **Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for technical architecture
- **Read [TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for common issues & solutions

---

## 💬 Support & Community

- 🐛 **Report Bugs**: GitHub Issues at https://github.com/Ruusian/ASL/issues
- 📧 **Contact**: abhiksarkar00@gmail.com

---

**Ready?** Run `asl` now to launch the interactive dashboard! 🚀
