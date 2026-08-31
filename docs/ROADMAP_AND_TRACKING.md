# ASL Feature Roadmap & Tracking

## Completed Features
- [x] **Root-Accelerated Subsystem Engine** (Native kernel chroot with direct GPU node access)
- [x] **Multi-Distro Subsystem Provisioner** (Debian Modded, Debian Trixie Base, Ubuntu 24.04 LTS, Arch Linux, Alpine, Kali)
- [x] **Dynamic Android Network DNS Sync & Phantom Process Killer Watchdog** (`asl dns` & `asl ppk`)
- [x] **GPU Hardware Acceleration Engine & Profile Switcher** (`asl gpu [profile|apply]`)
- [x] **Automated Chroot Mount Error Rollback Trap** (`core/mount-chroot.sh`)
- [x] **Hardened Loopback Remote Access** (`desktop/remote.sh` 127.0.0.1 default binding)
- [x] **Shared Execution Abstraction Engine** (`core/common.sh`)
- [x] **Debian 13 (Trixie) ARM64 RootFS Integration**
- [x] **Mesa Turnip Vulkan + Zink D3D Driver Integration**
- [x] **MangoHud Performance Overlay Manager (`asl hud`)**
- [x] **Bluetooth & Evdev Gamepad Passthrough (`asl gamepad`)**
- [x] **IDE & Developer Environment Toolsuite (`asl dev-suite`)**
- [x] **Containerized Defensive Security Audit Suite (`asl security-suite`)**
- [x] **Storage Cleaner & Automated Integrity Repair (`asl clean` & `asl repair`)**
- [x] **Termux:X11 Dynamic Display Resolution & Low-Latency PulseAudio Optimizer**
- [x] **Full Subsystem Backup & Point-in-Time Snapshot Management (`asl backup` & `asl snapshot`)**
- [x] **Declarative System Configuration Manager (`/etc/asl.conf` / `asl config`)**
- [x] **Host <-> Subsystem Path Translation Utility (`asl path`)**
- [x] **Comprehensive `docs/` Directory Structure**
- [x] **Host Kernel OS Stability Protection** (Zero host kernel `sysctl` overrides to prevent kernel panics on custom Android kernels)
- [x] **Hang-Free Subshell Execution Routing** (Temporary script file routing in `core/common.sh` eliminating base64 subshell limits)
- [x] **D-Bus Managed XFCE Session Lifecycle** (`dbus-run-session startxfce4` with robust `xfce4-session` / `xfwm4` process tracking)
- [x] **Terminal UI/UX DEC 1049 Alternate Screen Buffer Isolation** (Clean flicker-free TUI console rendering)
- [x] **24/7 Background Service Manager & OmniRoute AI Gateway Integration** (`service-manager.sh` with detached subshells & netd DNS bypass)
- [x] **Modular 24/7 Remote Mesh Architecture** (LAN SSH, Oracle VPS dedicated relay, Serveo jump-host, Ngrok pool)
- [x] **Source Repository vs Installed Runtime Separation** (`~/ASL` development repo vs `$PREFIX/share/asl` system install)
- [x] **Kernel Sysctl TCP Network Throughput Tuning** (`99-asl-tcp-tuning.conf`)

## Planned Enhancements & Roadmap
- [ ] **Wayland Native compositor backend (When Termux:X11 Wayland DRI3 stabilizes)**

## Known Architecture Invariants to Maintain
1. **Always sanitize file paths** with `tr -d '\r\n'` to prevent Windows CRLF file issues.
3. **Ensure `export PATH` is explicit** across all utility scripts called inside minimal chroot subshells.
4. **Use `core/common.sh` abstractions (`asl_exec`, `asl_chroot_exec`)** for all host/chroot execution paths.
