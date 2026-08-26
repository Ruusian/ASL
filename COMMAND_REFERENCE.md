# ASL Command Reference

Complete reference for all ASL commands and their real-world usage.

---

## 🎯 Dashboard & Navigation

### `asl`
Launch interactive 74-column DEC Mode 1049 alternate-screen buffer dashboard.

```bash
asl                 # Open dashboard
asl dashboard       # Same as above
asl menu            # Alias for dashboard
```

**Interactive Hotkeys**:
- `s` - Start / mount subsystem
- `x` - Stop / unmount subsystem
- `d` - Start desktop session (Termux:X11)
- `g` - Launch Windows executable / Game Hub
- `h` - Toggle performance HUD overlay
- `v` - Remote bridges & tunnel endpoints
- `p` - Process manager
- `t` - Thermal & battery monitor
- `w` - Live watchdog monitor
- `c` - Clean container cache & storage
- `r` - System integrity self-repair
- `q` - Quit dashboard

---

## ⚡ Network DNS & Phantom Process Killer
 
### `asl dns`
Synchronize active Android network DNS into Debian `/etc/resolv.conf`.
 
```bash
asl dns                                 # Synchronize current Android nameservers into chroot
asl dns status                          # View active nameserver configuration
```
 
---
 
### `asl ppk`
Inspect or disable Android 12+ Phantom Process Killer limits.
 
```bash
asl ppk off                             # Disable Phantom Process Killer (max 2147483647 processes)
asl ppk status                          # Inspect current PPK status
asl ppk on                              # Restore default PPK limits (32 processes)
```

---

### `asl wizard` / `asl init`
Run guided first-time interactive setup wizard.

```bash
asl wizard                             # Launch interactive setup wizard
asl init                               # Alias for asl wizard
```

Preset options available in wizard:
1. **GPU & Graphics Acceleration** (Turnip Mesa Vulkan, Zink, MangoHud, Gamepad)
2. **Software Developer** (Python 3, Node.js, Neovim, Go, Rust, VS Code Server)
3. **Security Auditing** (Nmap, Wireshark/TShark, Netcat, Socat, Hydra)
4. **Full Workstation** (Complete desktop suite, developer tools & graphics stack)

---

## 🐧 Subsystem Management

### `asl start`
Mount Debian chroot and virtual filesystems (`/dev`, `/proc`, `/sys`, `/sdcard`, `/tmp`).

```bash
asl start                           # Start and mount subsystem
```

---

### `asl stop`
Gracefully terminate desktop and subsystem processes, then unmount all bind mounts in reverse order.

```bash
asl stop                            # Prompt confirmation and stop subsystem
```

---

### `asl status`
Show subsystem mount status, container size, location, and active sub-mounts.

```bash
asl status                          # Show status overview
```

---

### `asl shell [user]`
Enter interactive bash login shell inside subsystem rootfs.

```bash
asl shell                           # Enter as root
asl shell user                      # Enter as specific container user
```

---

### `asl exec <command>`
Execute a single command directly inside the subsystem container.

```bash
asl exec "uname -a"                 # Run command
asl exec "apt-get update"           # Update package lists
asl exec "python3 script.py"        # Run Python script
```

---

### `asl install <packages...>`
Install Debian packages inside the subsystem using APT.

```bash
asl install build-essential         # Install single package
asl install git curl wget           # Install multiple packages
```

---

### `asl search <query>`
Search available Debian APT packages in repository cache.

```bash
asl search python3                  # Search packages
```

---

## 📸 Snapshots & Backups

### `asl snapshot`
Point-in-time container snapshot management.

```bash
asl snapshot list                   # List all saved snapshots
asl snapshot create <name>          # Create snapshot of current rootfs
asl snapshot restore <name>         # Restore rootfs from snapshot
asl snapshot delete <name>          # Delete snapshot
asl snapshot export <name> [file]   # Export snapshot to compressed archive (.tar.zst / .tar.xz)
asl snapshot import <file> <name>   # Import snapshot from compressed archive
```

---

### `asl backup` & `asl restore`
Full rootfs backup and restoration.

```bash
asl backup                          # Create full compressed backup of Debian rootfs
asl restore [path/to/backup.tar.xz] # Restore Debian rootfs from backup archive
```

---

## 🖥️ Desktop & Resolution

### `asl desktop`
Manage hardware-accelerated XFCE4 desktop session on Termux:X11 (`:0`).

```bash
asl desktop start                   # Start XFCE4 desktop session
asl desktop stop                    # Stop desktop session
asl desktop restart                 # Restart desktop session
asl desktop status                  # Check desktop session state
asl desktop refresh-x11             # Refresh Termux:X11 display socket
asl desktop sync-apps               # Sync .desktop application shortcuts
asl desktop launch <app>            # Launch specific desktop application
```

---

### `asl resolution [720p|1080p|native] [scale]`
Configure Termux:X11 display resolution and GTK scaling.

```bash
asl resolution 720p                 # Set 1280x720 display resolution
asl resolution 1080p                # Set 1920x1080 display resolution
asl resolution native               # Set native display resolution
asl resolution 1080p 1.25           # Set 1080p with 1.25x GTK scale factor
asl resolution status               # Inspect current display resolution
```

---

### `asl theme`
Switch desktop theme and styling.

```bash
asl theme                           # Interactive theme menu
asl theme dark                      # Apply dark GTK/XFCE theme
asl theme light                     # Apply light theme
```

---

## 🌐 Remote Access Bridges (`asl remote`)

Modular remote connection manager supporting LAN SSH, user Oracle/custom VPS reverse tunnels, Serveo, and Ngrok.

```bash
asl remote status                   # Show status of all remote bridge endpoints
asl remote all                      # Start LAN SSH + Oracle VPS + Serveo + Autoconnect
asl remote gui                      # Display remote desktop (VNC/X11) SSH forwarding guide
```

### LAN SSH Server (Port 8022)
```bash
asl remote lan start                # Start host OpenSSH daemon on port 8022
asl remote lan stop                 # Stop LAN SSH daemon
asl remote lan status               # Show LAN connection command with dynamic IP
```

### Dedicated VPS / Oracle Cloud Relay
Interactive and configurable for your own remote server:
```bash
asl remote oracle setup             # Interactive setup wizard (prompts for host, user, port, key)
asl remote oracle start             # Connect persistent reverse SSH tunnel (port 2222 -> 8022)
asl remote oracle stop              # Disconnect VPS tunnel
asl remote oracle status            # Check VPS tunnel status
asl remote oracle gen-key           # Generate dedicated ED25519 keypair
asl remote oracle add-key <keyfile> # Import existing SSH private key
asl remote oracle push-pubkey       # Copy public key to remote VPS authorized_keys
asl remote oracle remove            # Remove VPS configuration and keys
```

### Serveo Jump-Host Reverse Tunnel
```bash
asl remote serveo start             # Start Serveo reverse tunnel
asl remote serveo stop              # Stop Serveo tunnel
asl remote serveo alias <name>      # Set custom Serveo subdomain
```

### Ngrok On-Demand Tunnel Pool
```bash
asl remote ngrok start              # Start Ngrok TCP tunnel
asl remote ngrok stop               # Stop Ngrok tunnel
asl remote ngrok add-token <token>  # Add authtoken to rotation pool
asl remote ngrok list-tokens        # List tokens and quota statuses
asl remote ngrok rotate             # Rotate to next active token in pool
asl remote ngrok reset              # Reset exhausted quota flags
```

### SSH Key & Password Management
```bash
asl remote keys list                # List authorized SSH public keys
asl remote keys add "<pubkey>"      # Add an authorized SSH public key
asl remote keys import-github <user># Import public SSH keys from GitHub account
asl remote password set <pass>      # Set remote SSH password
asl remote password clear           # Clear remote SSH password
```

### Autoconnect 24/7 Daemon
```bash
asl remote autoconnect              # Start 24/7 auto-reconnect background daemon
asl remote autoconnect stop         # Stop autoconnect daemon
```

---

## 🎮 GPU Acceleration & Graphics Engine

### `asl gpu [profile|apply]`
Configure and apply hardware-accelerated Turnip Vulkan and Mesa Zink graphics drivers.

```bash
asl gpu apply                        # Detect GPU hardware and apply acceleration
asl gpu profile                      # Inspect detected GPU and Vulkan ICD
```

---

### `asl turbo` / `asl mode gpu`
Apply maximum CPU/GPU performance governor and OOM protection.

```bash
asl turbo                            # Switch CPU governor to performance
asl mode balanced                    # Switch to balanced profile
asl mode status                      # Query active governor profile
```

---

### `asl gamepad [status|sync|test]`
Synchronize Bluetooth and USB `/dev/input/event*` wireless controllers into chroot.

```bash
asl gamepad status                  # Detect connected gamepads
asl gamepad sync                    # Map host gamepad event nodes into chroot /dev/input
asl gamepad test                    # Interactive button & joystick calibration test
```

---

### `asl hud [on|off|toggle|status]`
Manage MangoHud and DXVK_HUD real-time performance telemetry overlay.

```bash
asl hud on                          # Enable FPS, CPU/GPU temp, RAM/VRAM overlay
asl hud off                         # Disable telemetry overlay
asl hud toggle                      # Toggle overlay state
asl hud status                      # Check active HUD configuration
```

---

### `asl mode [gaming|performance|balanced|status]`
Set system CPU governor and performance profile.

```bash
asl mode gaming                     # Gaming profile (CPU governor set to performance)
asl mode performance                # Performance profile
asl mode balanced                   # Balanced profile (CPU governor set to schedutil/powersave)
asl mode status                     # Show active profile and CPU governor
```

---

## 📊 Diagnostics & Monitoring

### `asl doctor`
Comprehensive non-mutating pre-flight system diagnostics.

```bash
asl doctor                          # Run full environment health check
```

**Checks**:
- Superuser root access (`su`) verification
- Debian rootfs existence and integrity
- Subsystem mount status
- Termux:X11 client installation
- PulseAudio client installation
- Storage permissions (`/sdcard`)
- GPU detection and hardware nodes (`/dev/kgsl-3d0`, `/dev/dri/*`)
- XFCE4 session and D-Bus daemon availability
- Vulkan ICD configuration

---

### `asl overview`
Display live system status and remote endpoint table.

```bash
asl overview                        # Show system overview
```

---

### `asl thermal`
Monitor thermal sensors and battery temperature.

```bash
asl thermal                         # Show thermal & battery report
asl thermal watch                   # Live thermal monitor (5s refresh)
```

---

### `asl ps` / `asl watch`
Interactive process management and live monitor.

```bash
asl ps                              # Open interactive process manager
asl watch                           # Open live system monitoring dashboard
```

---

## 📱 Android Host Integration

### `asl aid` / `asl gids`
Map Android AID groups (sdcard_rw, inet, graphics) inside container.

```bash
asl aid                             # Apply Android AID group mappings
asl aid status                      # Verify AID mapping status
```

---

### `asl wakelock [on|off|status]`
CPU wake lock control.

```bash
asl wakelock on                     # Acquire CPU wake lock (prevents sleep during background tasks)
asl wakelock off                    # Release CPU wake lock
asl wakelock status                 # Show current wake lock status
```

---

### `asl open <file|url>`
Open container file or URL in default Android host application.

```bash
asl open /sdcard/photo.jpg          # Open image in Android gallery
asl open https://github.com         # Open URL in Android browser
```

---

### `asl clip [copy <text>|paste]`
Android system clipboard bridge.

```bash
asl clip copy "Hello from Linux"    # Copy text to Android clipboard
asl clip paste                      # Paste text from Android clipboard
echo "data" | asl clip copy         # Pipe standard input to clipboard
asl clip-sync start                 # Start background bidirectional clipboard sync daemon
asl clip-sync stop                  # Stop clipboard sync daemon
```

---

### `asl toast <message>` & `asl notify <title> <message>`
Trigger native Android host notifications and toast messages.

```bash
asl toast "Task completed!"         # Display Android toast
asl notify "ASL" "Build finished"   # Post Android system notification
```

---

### `asl shortcut <app-name>`
Create Android home screen launcher shortcut for container applications.

```bash
asl shortcut xfce4-terminal         # Create shortcut for XFCE terminal
```

---

### `asl storage`
Request Android shared storage permissions.

```bash
asl storage                         # Trigger termux-setup-storage
```

---

### `asl path [OPTIONS] <path>`
Translate filesystem paths between Android host and Linux container.

```bash
asl path -u /storage/emulated/0/doc # Convert host path to container path (/sdcard/doc)
asl path -a /sdcard/doc             # Convert container path to host path
asl path -c /etc/hosts              # Convert container path to chroot filesystem path
asl path -m                         # Display container storage mount points
```

---

## 🤖 24/7 Background Services & Automation

### `asl service`
Manage 24/7 background daemons, Termux:Boot autostart, and health watchdog.

```bash
asl service status                  # Check 24/7 service, boot autostart, and daemon status
asl service start                   # Start background services (SSH, Tunnels, OmniRoute)
asl service stop                    # Stop all background services
asl service restart                 # Restart background services
asl service check                   # Run self-healing health watchdog check
asl service loop                    # Start autonomous background watchdog loop (180s interval)
asl service enable                  # Enable Termux:Boot autostart & shell hook
asl service disable                 # Disable boot autostart
```

---

### `asl omniroute`
Manage OmniRoute local AI API gateway running on port 20128 (root-isolated to bypass Android netd DNS restrictions).

```bash
asl omniroute status                # Check proxy health and endpoint
asl omniroute start                 # Start OmniRoute daemon as root
asl omniroute stop                  # Stop OmniRoute daemon
asl omniroute restart               # Restart OmniRoute daemon
asl omniroute logs                  # Tail recent OmniRoute proxy logs
```

---

## 💾 Storage, Memory & Maintenance

### `asl swap`
Manage virtual swap pool and zRAM swap files with 5GB safety bounds.

```bash
asl swap status                     # Show swap usage, zRAM state & swapfile stats
asl swap setup [size]               # Setup virtual swapfile (default: 5G)
asl swap optimize                   # Run memory compaction and drop caches
asl swap cleanup                    # Deactivate and detach swap loop devices
```

---

### `asl clean`
Purge cache files, package archives, and temporary artifacts to free internal storage.

```bash
asl clean status                    # Show cleanable storage breakdown
asl clean all                       # Clean APT cache, /tmp, and shader caches
asl clean apt                       # Clean Debian APT package archives
asl clean tmp                       # Clean container temporary files
asl clean cache                     # Clean user cache & Mesa shader caches
```

---

### `asl repair`
Automated system integrity repair and recovery for corrupted locks, permissions, or mount states.

```bash
asl repair all                      # Run full self-healing recovery suite
asl repair mounts                   # Fix stale or corrupted chroot mounts
asl repair permissions              # Restore file permissions, GPU nodes, and IPC sockets
asl repair dpkg                     # Recover from interrupted DPKG / APT lock states & DNS
asl repair env                      # Resynchronize dynamic profile.d GPU/HUD environment variables
asl repair libs                     # Rebind dynamic linker bindings (ldconfig)
```

---

## 🛠️ Developer & Security Suites

### `asl dev-suite`
Deploy pre-configured developer toolchains inside the Debian chroot.

```bash
asl dev-suite status                # Check installed development toolchains
asl dev-suite install all           # Install full developer suite
asl dev-suite install python        # Install Python 3, pip, venv, and development headers
asl dev-suite install webdev        # Install Node.js, npm, yarn, and TypeScript
asl dev-suite install neovim        # Install Neovim with modern configuration
asl dev-suite install vscode        # Install VS Code Server
asl dev-suite install golang        # Install Go compiler and toolchain
asl dev-suite install rust          # Install Rust toolchain via rustup
```

---

### `asl security-suite`
Install defensive network auditing and security analysis tools.

```bash
asl security-suite status           # Check installed security packages
asl security-suite install basic    # Install Nmap, Netcat, Socat, TCPDump
asl security-suite install audit    # Install Wireshark/TShark, Nikto, Gobuster
asl security-suite install full     # Install complete security suite
```

---

### `asl hub` / `asl gui`
Launch native GTK3 Control Center desktop application inside XFCE4 session (`os.posix_spawn` invariant).

```bash
asl hub                             # Launch ASL Control Center GTK3 app
asl gui                             # Alias for asl hub
```

---

### `asl config`
Manage declarative configuration in `/etc/asl.conf`.

```bash
asl config show                     # Display active /etc/asl.conf settings
asl config init                     # Initialize default configuration file
asl config get <section> <key>      # Get specific configuration value
asl config set <sec> <key> <val>    # Update configuration setting
```

---

## 📞 Getting Help

```bash
asl help                            # Show all CLI commands
asl doctor                          # Run system diagnostics
```
