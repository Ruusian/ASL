#!/bin/bash
# Non-mutating environment diagnostics for ASL.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi
source "$SCRIPT_DIR/core/gpu-profile.sh"

fail=0
check() {
    local name="$1" required="$2" detail="$3" status="$4"
    printf '%-14s %-5s %s\n' "$name" "$status" "$detail"
    [ "$required" = required ] && [ "$status" = FAIL ] && fail=1
    return 0
}

# Allow custom or dynamic DEBIANPATH across execution modes

case "${ASL_EXEC_MODE:-root}" in
    root)
        if [ "$(su -c 'id -u' 2>/dev/null)" = 0 ]; then
            check exec-mode required "su grants root access (ROOT mode)" PASS
        else
            check exec-mode required "root access through su is unavailable" FAIL
        fi
        ;;
    shizuku)
        if command -v rish >/dev/null 2>&1 && rish -c "id" >/dev/null 2>&1; then
            check exec-mode required "rish grants ADB privilege (SHIZUKU mode)" PASS
        else
            check exec-mode required "Shizuku (rish) is unavailable" FAIL
        fi
        ;;
    proot|*)
        if command -v proot-distro >/dev/null 2>&1 || [ -d "$PREFIX/var/lib/proot-distro" ]; then
            check exec-mode required "proot-distro emulation ready (PROOT mode)" PASS
        else
            check exec-mode required "proot-distro package is missing" FAIL
        fi
        ;;
esac

if command -v getenforce >/dev/null 2>&1; then
    se_mode=$(getenforce 2>/dev/null || echo "Unknown")
    check selinux optional "mode=$se_mode" PASS
fi
if [ -d "$DEBIANPATH" ] || [ -d "$PREFIX/var/lib/proot-distro/containers/asl-debian" ]; then check debian-root required "$DEBIANPATH exists" PASS; else check debian-root required "$DEBIANPATH is missing" FAIL; fi
if is_mounted; then mounted=1; check chroot optional "mounted" PASS; else mounted=0; check chroot optional "not mounted; chroot checks skipped" WARN; fi
if command -v termux-x11 >/dev/null; then check termux-x11 required "client installed" PASS; else check termux-x11 required "install with: pkg install termux-x11" FAIL; fi
if command -v pulseaudio >/dev/null; then check pulseaudio required "client installed" PASS; else check pulseaudio required "install with: pkg install pulseaudio" FAIL; fi
if [ -d /sdcard ] && [ -w /sdcard ]; then check storage optional "/sdcard is writable" PASS; else check storage optional "/sdcard is unavailable or not writable" WARN; fi
asl_gpu_detect
if [ -e /dev/dri ] || [ -e /dev/kgsl-3d0 ]; then check gpu optional "profile=$ASL_GPU_PROFILE; host GPU node present" PASS; else check gpu optional "profile=$ASL_GPU_PROFILE; no known host GPU node" WARN; fi
if [ "$mounted" = 1 ]; then
    (asl_chroot_exec "/usr/bin/test -x /usr/bin/xfwm4 -o -x /usr/bin/xfce4-session" 2>/dev/null) && check xfce required "XFCE session / window manager available" PASS || check xfce required "install Debian xfwm4 or xfce4-session" FAIL
    (asl_chroot_exec "/usr/bin/test -x /usr/bin/dbus-launch -a \( -S /var/run/dbus/system_bus_socket -o -S /run/dbus/system_bus_socket -o -x /usr/bin/dbus-daemon \)" 2>/dev/null) && check dbus required "D-Bus daemon & launcher ready" PASS || check dbus required "install Debian dbus-x11 / dbus" FAIL
    if asl_chroot_exec "/usr/bin/find /usr/share/vulkan/icd.d -type f -name '*.json' -print -quit 2>/dev/null | grep -q ." 2>/dev/null; then check vulkan optional "ICD JSON found" PASS; else check vulkan optional "no Vulkan ICD JSON found" WARN; fi
fi
exit "$fail"
