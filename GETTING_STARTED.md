# Getting Started with ASL

This guide will help you get up and running with Android Subsystem for Linux (ASL) in minutes.

---

## Prerequisites

Before installing ASL, ensure you have:

- ✅ **Android Device** with root access (Magisk, KernelSU, or APatch)
- ✅ **Termux** installed from F-Droid or GitHub Releases
- ✅ **Root Manager** with working `su` command
- ✅ **Storage Space** - At least 5GB free for Debian rootfs + applications

### Quick Prerequisites Check

Run this in Termux to verify everything:

```bash
su -c "id | grep -q 'uid=0' && echo '✓ Root access OK' || echo '✗ Root access FAILED'"
termux-storage-get  # Check storage access
which proot-distro  # Check if proot-distro is installed
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

During installation, you'll be prompted:

```
Select Debian edition:
  1) Modded (Pre-configured for gaming/desktop) [RECOMMENDED]
  2) Standard (Clean Debian Trixie)
  3) Custom (Advanced)
```

**For beginners**: Choose **1 (Modded)** — includes Turnip Vulkan, Box64, Wine, XFCE.

### Step 3: Verify Installation

Test the installation:

```bash
asl doctor
```

Expected output:
```
root           PASS  su grants root access
debian-root    PASS  /data/local/tmp/chrootDebian found
chroot         WARN  not mounted yet (run: asl start)
termux-x11     PASS  installed
pulseaudio     PASS  client installed
storage        PASS  /sdcard is writable
gpu            PASS  profile=turnip; Adreno GPU detected
```

---

## 🎮 Quick Start Workflows

### Workflow 1: Launch Interactive Dashboard

```bash
asl
```

This opens the interactive TUI dashboard with 23+ commands and real-time system stats.

**Key hotkeys**:
- `s` - Start/mount chroot
- `x` - Stop/unmount chroot  
- `d` - Start XFCE desktop
- `g` - Run Windows .exe (via Wine/Box64)
- `p` - Process manager
- `t` - Thermal monitor
- `h` - Help
- `q` - Quit

### Workflow 2: Mount Debian & Enter Shell

```bash
# Start chroot (mount Debian)
asl start

# Enter root shell inside chroot
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

# Run interactive command
asl shell
```

### Workflow 4: Start Desktop Environment

```bash
# Start XFCE desktop with Termux:X11
asl desktop start

# Access via VNC or SSH
asl remote ssh

# Stop desktop when done
asl desktop stop
```

### Workflow 5: Run Windows Games

```bash
# Start chroot
asl start

# List installed games
wine notepad

# Run a game (example: Ninesolls)
asl game ninesols

# Or run any .exe directly
asl exec "wine /sdcard/Games/MyGame.exe"
```

---

## 📚 Common Commands

### Chroot Management

```bash
asl start              # Mount Debian chroot
asl stop               # Unmount chroot
asl status             # Show chroot status
asl shell [user]       # Enter interactive shell (default: root)
asl exec <cmd>         # Run single command
asl install <pkg...>   # Install Debian packages
```

### Snapshots & Backups

```bash
asl snapshot create daily    # Create snapshot named "daily"
asl snapshot list            # List all snapshots
asl snapshot restore daily   # Restore from snapshot
asl snapshot delete daily    # Delete snapshot
asl backup create            # Full chroot backup
asl backup list              # List backups
```

### Desktop & Remote

```bash
asl desktop start      # Start XFCE + Termux:X11
asl desktop stop       # Stop desktop
asl theme dark         # Set dark theme
asl resolution 1920x1080  # Set resolution
asl remote ssh         # Enable SSH access
asl remote vnc         # Enable VNC access
```

### Gaming & Performance

```bash
asl game [name]        # Launch pre-configured game
asl mode gaming        # Set gaming performance profile
asl mode balanced      # Set balanced mode
asl mode power-save    # Set power save mode
asl boost              # Run optimization script
```

### Diagnostics

```bash
asl doctor             # Health check
asl overview           # Show system overview
asl thermal            # Monitor thermal/battery
asl ps                 # List running chroot processes
asl log                # View system logs
```

### Android Integration

```bash
asl android aid        # Map Android ID groups
asl wakelock on/off    # CPU wake lock
asl open <file>        # Open file in Android app
asl clip copy/paste    # Clipboard bridge
asl toast "Message"    # Android notification
```

---

## ⚙️ Configuration

### Environment Variables

Set in `/etc/profile` or `~/.bashrc`:

```bash
# GPU profile (turnip, zink, virgl, swiftshader)
export ASL_GPU=turnip

# Box64 dynarec CPU option
export BOX64_DYNAREC_CPU=cortex-a76

# Wine prefix
export WINEPREFIX=~/.wine

# Mesa debug output
export MESA_DEBUG=silent
```

### Files & Locations

```
~/.config/asl/                    # ASL config directory
~/.local/state/asl/               # Runtime state
/data/local/tmp/chrootDebian      # Debian rootfs
/data/local/tmp/.asl-snapshots/   # Snapshot storage
~/.wine/                          # Wine prefix
/sdcard/                          # Android storage (shared)
```

---

## 🔧 Troubleshooting

### Chroot Won't Start

```bash
# Check what's wrong
asl doctor

# Common fixes
asl stop              # Force stop
rm -rf /data/local/tmp/.asl-snapshots  # Clear locks
asl start --force     # Start with force flag

# If still stuck
su -c "umount -l /data/local/tmp/chrootDebian"
```

### Performance Issues

```bash
# Check CPU/GPU profile
asl overview

# Optimize system
asl boost             # Run optimization script
asl mode gaming       # Set gaming mode

# Monitor in real-time
asl thermal           # Watch temps
watch -n1 'asl ps'    # Watch processes
```

### Graphics Not Working

```bash
# Check GPU detection
asl doctor | grep gpu

# Test graphics
asl shell
glxinfo | grep "OpenGL"
vkcube               # Vulkan test

# Fallback to VirGL if Turnip doesn't work
export ASL_GPU=virgl
```

### Desktop Crashes

```bash
# Stop desktop cleanly
asl desktop stop

# Restart X11 server
killall -9 Xwayland  # or Xvfb depending on setup
asl desktop start
```

---

## 📖 Next Steps

- **Read [TROUBLESHOOTING.md](TROUBLESHOOTING.md)** for common issues
- **Check [CONTRIBUTING.md](CONTRIBUTING.md)** to help improve ASL
- **Review [TEST_RESULTS.md](TEST_RESULTS.md)** for v1.1 release validation
- **Explore [.instructions.md](.instructions.md)** for advanced agent context

---

## 💬 Support & Community

- 🐛 **Report Bugs**: GitHub Issues at https://github.com/Ruusian/ASL/issues
- 💡 **Suggest Features**: GitHub Discussions
- 📧 **Contact**: abhiksarkar00@gmail.com

---

**Ready?** Run `asl` now to launch the interactive dashboard! 🚀
