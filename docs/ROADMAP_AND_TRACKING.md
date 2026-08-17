# ASL Feature Roadmap & Tracking

## Completed Features
- [x] **Debian 13 (Trixie) ARM64 RootFS Integration**
- [x] **GTK3 Dashboard (`asl-gui`) with `posix_spawn` multithreading deadlock fix**
- [x] **Box64 ARM64 -> x86_64 Dynarec + Wine 64-bit Execution Stack**
- [x] **Mesa Turnip Vulkan + Zink D3D Driver Integration**
- [x] **MangoHud & DXVK_HUD Performance Overlay Manager (`asl hud`)**
- [x] **Wayland / Native Xwayland Display Backend Manager (`asl wayland`)**
- [x] **Per-Game Wine Prefix Isolation System**
- [x] **Direct `.exe` / `.msi` MIME Desktop File Associations in Debian File Managers**
- [x] **DXVK & VKD3D-Proton Runtime Auto-Installer (`asl dxvk`)**
- [x] **Termux:X11 Dynamic FSR Resolution & Low-Latency PulseAudio Optimizer**
- [x] **Steam & x86_64 Game Launcher Environment (`asl steam`)**
- [x] **One-Click Game Save & Wine Prefix Backup/Restore (`asl backup`)**
- [x] **Comprehensive `docs/` Directory Structure**

## Planned Enhancements & Roadmap
- [ ] **Wine Mono / Gecko Offline Bundle Installer:** Package offline `.msi` installers for games requiring .NET framework or MSHTML.
- [ ] **Containerized Security Testing Tools:** Optional chroot security toolsuite (nmap, wireshark, mettle/kali tools) for defensive security auditing inside ASL.

## Known Architecture Invariants to Maintain
1. **Never replace `os.posix_spawn` in `asl-gui`** with `subprocess.Popen` or `os.fork()`.
2. **Always sanitize `.wineprefix` paths** with `tr -d '\r\n'` to prevent Windows CRLF file issues.
3. **Ensure `export PATH` is explicit** across all utility scripts called inside minimal chroot subshells.
