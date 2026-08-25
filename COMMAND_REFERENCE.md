# ASL Command Reference

Complete reference for all ASL commands and their usage.

---

## 🎯 Dashboard & Navigation

### `asl`
Launch interactive dashboard.

```bash
asl                 # Open dashboard
asl dashboard       # Same as above
asl menu            # Alias for dashboard
```

**Keyboard Shortcuts**:
- `s` - Start/mount chroot
- `x` - Stop/unmount
- `a` - Android AID setup
- `g` - Run Windows .exe
- `d` - Start desktop
- `v` - Remote SSH/VNC
- `p` - Process manager
- `t` - Thermal monitor
- `h` - Help
- `r` - Refresh
- `w` - Watch live
- `q` - Quit

---

## 🐧 Chroot Management

### `asl start`
Start and mount Debian chroot.

```bash
asl start                           # Start chroot
asl start --timeout 120             # Set custom timeout (seconds)
asl start --force                   # Force start even if stuck
asl start --verbose                 # Show detailed output
```

**Returns**:
- `0` - Success
- `1` - Failed (check `asl doctor`)
- `2` - Already mounted

---

### `asl stop`
Stop and unmount chroot.

```bash
asl stop                            # Stop chroot
asl stop --force                    # Force unmount
asl stop --lazy                     # Lazy unmount (don't wait)
asl stop --kill-all                 # Kill all processes before unmount
```

**What it does**:
1. Sends SIGTERM to running processes
2. Waits for graceful shutdown
3. Sends SIGKILL if needed
4. Unmounts all bind mounts in reverse order

---

### `asl status`
Show chroot status and statistics.

```bash
asl status                          # Show detailed status
asl status --json                   # Output as JSON
asl status --brief                  # Compact output
```

**Output includes**:
- Mounted/unmounted state
- Process count
- Rootfs size
- Mount points
- Uptime (if running)

---

### `asl shell [user]`
Enter interactive shell inside chroot.

```bash
asl shell                           # Enter as root
asl shell user                      # Enter as specific user
asl shell --                        # Pass remaining args to shell
asl shell < script.sh               # Run script in chroot shell
```

**Examples**:
```bash
asl shell                           # Get root shell
asl shell << 'EOF'
apt-get update
apt-get install -y build-essential
gcc --version
EOF
```

---

### `asl exec <command>`
Execute single command inside chroot.

```bash
asl exec "command"                  # Run command
asl exec "cmd1 && cmd2"             # Multiple commands
asl exec -- "cmd --with-dashes"     # Handle arguments properly
```

**Examples**:
```bash
asl exec "apt-get update"
asl exec "gcc -v"
asl exec "python3 script.py"
asl exec "bash /sdcard/setup.sh"
```

---

### `asl install [packages]`
Install Debian packages using apt.

```bash
asl install build-essential         # Install single package
asl install git curl wget           # Install multiple
asl install --update                # Update package list first
asl install --upgrade               # Upgrade all packages
```

**Aliases**:
- `asl pkg install` - Same as above
- `asl apt install` - Alias

---

## 📸 Snapshots & Backups

### `asl snapshot create <name>`
Create point-in-time snapshot.

```bash
asl snapshot create backup-v1       # Create snapshot
asl snapshot create daily-$(date +%Y%m%d)  # Timestamped
```

**Naming rules**:
- Alphanumeric, underscore, dash only
- No spaces or special characters
- Max 50 characters

---

### `asl snapshot list`
List all snapshots.

```bash
asl snapshot list                   # Show all
asl snapshot list --json            # JSON format
asl snapshot list --size            # Show sizes
```

**Output**:
```
Snapshots:
  backup-v1       [2.8 GB] Created: 2026-08-16 10:30
  gaming-setup    [3.1 GB] Created: 2026-08-15 14:22
  daily-20260816  [2.9 GB] Created: 2026-08-16 23:59
```

---

### `asl snapshot restore <name>`
Restore from snapshot.

```bash
asl snapshot restore backup-v1      # Restore snapshot
asl snapshot restore --force         # Force restore
asl snapshot restore --backup        # Create backup before restore
```

**What it does**:
1. Stops running chroot
2. Swaps current with snapshot
3. Verifies integrity
4. Restarts chroot

---

### `asl snapshot delete <name>`
Delete a snapshot.

```bash
asl snapshot delete backup-v1       # Delete snapshot
asl snapshot delete --all           # Delete all (dangerous!)
asl snapshot delete --confirm       # Skip confirmation
```

---

### `asl backup create [name]`
Create full chroot backup.

```bash
asl backup create                   # Auto-named backup
asl backup create my-backup         # Named backup
asl backup create --compress gz     # Compress with gzip
```

---

### `asl backup restore <name>`
Restore from backup.

```bash
asl backup restore my-backup        # Restore backup
asl backup restore --verify         # Verify before restore
```

---

## 🖥️ Desktop & Remote

### `asl desktop start`
Start XFCE desktop with Termux:X11.

```bash
asl desktop start                   # Start desktop
asl desktop start --resolution 1920x1080  # Custom resolution
asl desktop start --dpi 96          # Set DPI
```

**Requirements**:
- Termux:X11 app installed and running
- At least 2GB free RAM

---

### `asl desktop stop`
Stop XFCE desktop.

```bash
asl desktop stop                    # Stop gracefully
asl desktop stop --kill             # Force kill
asl desktop stop --logout           # Logout user first
```

---

### `asl desktop status`
Show desktop status.

```bash
asl desktop status                  # Show status
asl desktop status --verbose        # Detailed info
```

---

### `asl theme [dark|light|auto]`
Set desktop theme.

```bash
asl theme dark                      # Dark theme
asl theme light                     # Light theme
asl theme auto                      # Auto-detect
asl theme list                      # List available themes
```

---

### `asl resolution <WxH>`
Set desktop resolution.

```bash
asl resolution 1920x1080            # 1080p
asl resolution 1280x720             # 720p
asl resolution 2560x1440            # 1440p
asl resolution list                 # Show options
```

---

### `asl remote`
Modular remote access bridge with 8 tunnel components (LAN, Oracle VPS, Serveo, Ngrok, SSH Keys, Autoconnect).

```bash
asl remote status                   # Show all tunnel status
asl remote all                      # Start LAN + Oracle + Serveo + Autoconnect
```

#### LAN SSH (port 8022)
```bash
asl remote lan start                # Start LAN SSH server
asl remote lan stop                 # Stop LAN SSH server
```

#### Oracle Cloud VPS (Always-On Tunnel)
```bash
asl remote oracle start             # Connect to Oracle VPS reverse tunnel
asl remote oracle stop              # Disconnect Oracle tunnel
```

#### Serveo Persistent Tunnel
```bash
asl remote serveo start             # Start Serveo tunnel (alias: asl-<user>)
asl remote serveo stop              # Stop Serveo tunnel
asl remote serveo alias <name>      # Set custom Serveo subdomain
```

#### Ngrok (On-Demand Multi-Token Pool)
```bash
asl remote ngrok start              # Start Ngrok tunnel (auto-rotates tokens)
asl remote ngrok stop               # Stop Ngrok tunnel
asl remote ngrok add-token <token>  # Add auth token to pool
asl remote ngrok list-tokens        # List tokens and quota status
asl remote ngrok rotate             # Rotate to next active token
asl remote ngrok reset              # Reset quota-exhausted tokens
```

#### SSH Key Management
```bash
asl remote keys list                # List authorized SSH public keys
asl remote keys add "<pubkey>"      # Add an SSH public key
asl remote keys import-github <user> # Import keys from GitHub
```

#### Autoconnect Daemon
```bash
asl remote autoconnect              # Start 24/7 auto-reconnect daemon
asl remote autoconnect stop         # Stop autoconnect daemon
```

#### Password Management
```bash
asl remote password set <pass>      # Set remote SSH password
asl remote password clear           # Remove remote SSH password
```

---

## 🎮 Gaming & Performance

### `asl game [name]`
Launch pre-configured game.

```bash
asl game                            # List available games
asl game ninesols                   # Launch Ninesols
asl game list                       # List all games
asl game <path/to/game.exe>         # Launch any .exe
```

---

### `asl mode [mode]`
Set performance profile.

```bash
asl mode gaming                     # Gaming profile (full power)
asl mode balanced                   # Balanced (default)
asl mode power-save                 # Power save
asl mode list                       # Show profiles
asl mode current                    # Show current mode
```

**What each mode does**:

| Mode | CPU Governor | Swap | Dirty Ratio |
|------|--------------|------|-------------|
| Gaming | performance | 10 | 10 |
| Balanced | schedutil | 30 | 20 |
| Power-save | powersave | 60 | 40 |

---

### `asl boost`
Run system optimization.

```bash
asl boost                           # Run optimizer
asl boost --verbose                 # Show details
asl boost --dry-run                 # Don't actually run
```

**Does**:
- Kill non-essential Android background apps
- Force CPU to performance mode
- Set OOM score for protection
- Compact memory and cache
- Tune swap/VFS settings

---

## 📊 Diagnostics & Monitoring

### `asl doctor`
System health check.

```bash
asl doctor                          # Full diagnostics
asl doctor --verbose                # Detailed output
asl doctor --json                   # JSON format
```

**Checks**:
- Root access
- Debian rootfs
- Chroot mounted
- Termux:X11
- PulseAudio
- Storage access
- GPU detection

---

### `asl overview`
Quick system overview.

```bash
asl overview                        # Show overview
asl overview --watch                # Auto-refresh
asl overview --json                 # JSON format
```

**Shows**:
- Chroot/Desktop/GPU status
- RAM/Swap usage
- CPU temperature
- Battery status
- Network info

---

### `asl thermal`
Monitor thermal & battery.

```bash
asl thermal                         # Show status
asl thermal --watch                 # Live monitoring
asl thermal --json                  # JSON format
asl thermal --alert 80              # Alert at 80°C
```

**Monitors**:
- CPU temperature
- GPU temperature
- Battery temperature
- Thermal sensors (TSENS, quiet-therm)

---

### `asl ps`
List chroot processes.

```bash
asl ps                              # List all
asl ps <pid>                        # Show specific PID
asl ps -k <pid>                     # Kill process
asl ps --json                       # JSON format
```

---

### `asl log`
View system logs.

```bash
asl log                             # Show recent logs
asl log --tail 100                  # Last 100 lines
asl log --follow                    # Live tail
asl log --grep "error"              # Filter logs
```

---

## 📱 Android Integration

### `asl android aid`
Map Android ID groups.

```bash
asl android aid                     # Apply AID mapping
asl android aid --check             # Verify mapping
asl android aid --reset             # Reset to defaults
```

---

### `asl wakelock [on|off]`
CPU wake lock control.

```bash
asl wakelock on                     # Enable wake lock
asl wakelock off                    # Disable wake lock
asl wakelock status                 # Show current status
```

---

### `asl open <file|url>`
Open file/URL in Android.

```bash
asl open /sdcard/photo.jpg          # Open in photo app
asl open https://github.com         # Open in browser
asl open document.pdf               # Open in PDF reader
```

---

### `asl clip [copy|paste]`
Clipboard sync.

```bash
asl clip copy                       # Copy to Android clipboard
asl clip paste                      # Paste from Android
echo "text" | asl clip copy         # Pipe to clipboard
```

---

### `asl toast "message"`
Android notification.

```bash
asl toast "Build complete!"
asl toast "Error occurred" --long   # Long duration
asl toast "Download: 50%" --tag build-progress  # Persistent
```

---

## 🔧 System Commands

### `asl help`
Show command help.

```bash
asl help                            # Show all commands
asl help <command>                  # Help for specific command
asl help gaming                     # Help for category
asl help --full                     # Full manual
```

---

### `asl version`
Show version information.

```bash
asl version                         # Version
asl version --check                 # Check for updates
```

---

### `asl config [key] [value]`
Manage configuration.

```bash
asl config get GPU                  # Get setting
asl config set GPU turnip           # Set setting
asl config list                     # List all
asl config reset                    # Reset to defaults
```

---

### `asl update`
Update ASL.

```bash
asl update                          # Update to latest
asl update --check                  # Check for updates
asl update --from-source            # Build from source
```

---

## 🤖 AI, Background Services & Automation

### `asl service`
Manage 24/7 background daemons, Termux:Boot autostart, and health watchdog.

```bash
asl service status                  # Check 24/7 service and daemon status
asl service start                   # Start background services (SSH, Tunnels, OmniRoute)
asl service stop                    # Stop background services
asl service restart                 # Restart background services
asl service check                   # Run self-healing health watchdog
asl service loop                    # Start autonomous background watchdog daemon (180s interval)
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
asl swap create [size_in_mb]        # Create virtual swapfile (default: 4096MB)
asl swap enable                     # Activate virtual swapfile
asl swap disable                    # Deactivate virtual swapfile
asl swap auto                       # Automatically size swapfile based on RAM & free storage
asl swap remove                     # Deactivate and delete virtual swapfile
```

---

### `asl clean`
Purge cache files, package archives, and temporary artifacts to free internal storage.

```bash
asl clean status                    # Show cleanable storage breakdown
asl clean all                       # Clean APT cache, /tmp, and Wine shader cache
asl clean apt                       # Clean Debian APT package archives
asl clean tmp                       # Clean container temporary files
asl clean wine                      # Clean Wine prefix cache and shaders
```

---

### `asl repair`
Automated system integrity repair and recovery for corrupted locks or mount states.

```bash
asl repair all                      # Run full self-healing recovery suite
asl repair mounts                   # Fix stale or corrupted chroot mounts
asl repair perms                    # Restore file permissions and Android AID mappings
asl repair dpkg                     # Recover from interrupted DPKG / APT lock states
asl repair dbus                     # Reset D-Bus socket and daemon
```

---

## 🛠️ Developer & Security Suites

### `asl dev-suite`
Deploy pre-configured developer toolchains inside the Debian chroot.

```bash
asl dev-suite list                  # List available development toolchains
asl dev-suite install python        # Install Python 3, pip, venv, and development headers
asl dev-suite install webdev        # Install Node.js, npm, yarn, and TypeScript
asl dev-suite install neovim        # Install Neovim with modern Lua configuration
asl dev-suite install vscode        # Install VS Code Server (web-accessible code editor)
asl dev-suite install golang        # Install Go compiler and toolchain
asl dev-suite install rust          # Install Rust toolchain via rustup
```

---

### `asl security-suite`
Install defensive network auditing and security analysis tools.

```bash
asl security-suite list             # List available security packages
asl security-suite install basic    # Install nmap, netcat, socat, tcpdump
asl security-suite install audit    # Install Wireshark/TShark, Nikto, Gobuster
```

---

### `asl hub` / `asl gui`
Launch native GTK3 Control Center desktop application inside XFCE4 session.

```bash
asl hub                             # Launch ASL Control Center GTK3 app
asl gui                             # Alias for asl hub
```

---

## 🎓 Advanced Usage

### Chaining Commands

```bash
# Start → Install package → Run command → Stop
asl start && asl install build-essential && asl exec "gcc -v" && asl stop

# With error handling
asl start || exit 1
asl install git || exit 1
asl exec "git --version" || exit 1
asl stop
```

### Using in Scripts

```bash
#!/bin/bash
# Build script using ASL

set -e  # Exit on error

asl start
asl exec "apt-get update && apt-get install -y build-essential"
asl exec "cd /sdcard/project && make"
asl stop

echo "✓ Build complete"
```

### Environment Variables

```bash
# Set in chroot
export ASL_GPU=turnip
export WINEPREFIX=~/.wine-gaming
export MESA_DEBUG=silent

# Set globally
echo 'export ASL_GPU=turnip' >> ~/.bashrc
```

---

## 📞 Getting Help

```bash
asl help                    # Show all commands
asl <command> --help        # Help for specific command
asl doctor                  # Diagnostics
asl log                     # View logs

# Online help
# GitHub: https://github.com/Ruusian/ASL
# Docs: https://github.com/Ruusian/ASL/blob/master/GETTING_STARTED.md
# Troubleshooting: https://github.com/Ruusian/ASL/blob/master/TROUBLESHOOTING.md
```

---

**Pro Tip**: Most commands support `--help`, `--verbose`, `--json` flags for more info!
