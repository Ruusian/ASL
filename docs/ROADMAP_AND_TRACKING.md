# ASL Feature Roadmap & Tracking

## Completed Features
- [x] **Universal 3-Tier Execution Engine** (Root `su`, Shizuku `rish`, PRoot `proot-distro`)
- [x] **Multi-Distro Subsystem Provisioner** (Debian Modded, Debian Trixie Base, Ubuntu 24.04 LTS, Arch Linux, Alpine, Kali)
- [x] **Execution Mode CLI Manager** (`asl exec-mode [root|shizuku|proot|status]`)
- [x] **Box64 Dynarec Precision Profile Switcher** (`asl game precision [safe|fast|status]`)
- [x] **Automated Chroot Mount Error Rollback Trap** (`core/mount-chroot.sh`)
- [x] **Hardened Loopback Remote Access** (`desktop/remote.sh` 127.0.0.1 default binding)
- [x] **Shared Execution Abstraction Engine** (`core/common.sh`)
- [x] **Debian 13 (Trixie) ARM64 RootFS Integration**
- [x] **GTK3 Dashboard (`asl-gui` / `asl-hub`) with `posix_spawn` multithreading deadlock fix**
- [x] **Native Debian Desktop GTK3 Control Center ("ASL Hub") App & Launcher**
- [x] **Box64 ARM64 -> x86_64 Dynarec + Wine 64-bit Execution Stack**
- [x] **Mesa Turnip Vulkan + Zink D3D Driver Integration**
- [x] **MangoHud & DXVK_HUD Performance Overlay Manager (`asl hud`)**
- [x] **Wine Mono / Gecko Offline Bundle Installer (`asl wine-bundle`)**
- [x] **Wine & Proton-GE Version Engine Manager (`asl wine-version`)**
- [x] **Bluetooth & Evdev Gamepad Passthrough (`asl gamepad`)**
- [x] **IDE & Developer Environment Toolsuite (`asl dev-suite`)**
- [x] **Containerized Defensive Security Audit Suite (`asl security-suite`)**
- [x] **Storage Cleaner & Automated Integrity Repair (`asl clean` & `asl repair`)**
- [x] **Per-Game Wine Prefix Isolation System**
- [x] **Direct `.exe` / `.msi` MIME Desktop File Associations in Debian File Managers**
- [x] **DXVK & VKD3D-Proton Runtime Auto-Installer (`asl dxvk`)**
- [x] **Termux:X11 Dynamic FSR Resolution & Low-Latency PulseAudio Optimizer**
- [x] **Steam & x86_64 Game Launcher Environment (`asl steam`)**
- [x] **One-Click Game Save & Wine Prefix Backup/Restore (`asl backup`)**
- [x] **Comprehensive `docs/` Directory Structure**
- [x] **Host Kernel OS Stability Protection** (Zero host kernel `sysctl` overrides to prevent kernel panics on custom Android kernels)
- [x] **Hang-Free Subshell Execution Routing** (Temporary script file routing in `core/common.sh` eliminating base64 subshell limits)
- [x] **D-Bus Managed XFCE Session Lifecycle** (`dbus-run-session startxfce4` with setpriv fallbacks & robust `xfce4-session` / `xfwm4` process tracking)

## Planned Enhancements & Roadmap
- [ ] **Wayland Native compositor backend (When Termux:X11 Wayland DRI3 stabilizes)**

## Known Architecture Invariants to Maintain
1. **Never replace `os.posix_spawn` in `asl-gui` / `asl-hub`** with `subprocess.Popen` or `os.fork()`.
2. **Always sanitize `.wineprefix` paths** with `tr -d '\r\n'` to prevent Windows CRLF file issues.
3. **Ensure `export PATH` is explicit** across all utility scripts called inside minimal chroot subshells.
4. **Use `core/common.sh` abstractions (`asl_exec`, `asl_chroot_exec`)** for all host/chroot execution paths.
