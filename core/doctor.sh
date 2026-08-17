#!/bin/bash
# Non-mutating environment diagnostics for ASL.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gpu-profile.sh"

fail=0
check() {
    local name="$1" required="$2" detail="$3" status="$4"
    printf '%-14s %-5s %s\n' "$name" "$status" "$detail"
    [ "$required" = required ] && [ "$status" = FAIL ] && fail=1
    return 0
}

[ "$DEBIANPATH" = /data/local/tmp/chrootDebian ] || { echo "FAIL fixed-path DEBIANPATH must be /data/local/tmp/chrootDebian"; exit 2; }

if [ "$(su -c 'id -u' 2>/dev/null)" = 0 ]; then check root required "su grants root access" PASS; else check root required "root access through su is unavailable" FAIL; fi
if [ -d "$DEBIANPATH" ]; then check debian-root required "$DEBIANPATH exists" PASS; else check debian-root required "$DEBIANPATH is missing" FAIL; fi
if su -c "grep -q -F ' $DEBIANPATH/proc ' /proc/mounts" 2>/dev/null; then mounted=1; check chroot optional "mounted" PASS; else mounted=0; check chroot optional "not mounted; chroot checks skipped" WARN; fi
if command -v termux-x11 >/dev/null; then check termux-x11 required "client installed" PASS; else check termux-x11 required "install with: pkg install termux-x11" FAIL; fi
if [ -f "$SCRIPT_DIR/wayland.sh" ]; then
    w_backend=$(bash "$SCRIPT_DIR/wayland.sh" exports 2>/dev/null | grep XDG_SESSION_TYPE | cut -d'"' -f2 || echo "x11")
    if bash "$SCRIPT_DIR/wayland.sh" status 2>/dev/null | grep -q "DETECTED ("; then
        check wayland optional "backend=${w_backend^^}; socket detected" PASS
    else
        check wayland optional "backend=${w_backend^^}; socket not detected (X11 active/fallback)" WARN
    fi
fi
if command -v pulseaudio >/dev/null; then check pulseaudio required "client installed" PASS; else check pulseaudio required "install with: pkg install pulseaudio" FAIL; fi
if [ -d /sdcard ] && [ -w /sdcard ]; then check storage optional "/sdcard is writable" PASS; else check storage optional "/sdcard is unavailable or not writable" WARN; fi
asl_gpu_detect
if [ -e /dev/dri ] || [ -e /dev/kgsl-3d0 ]; then check gpu optional "profile=$ASL_GPU_PROFILE; host GPU node present" PASS; else check gpu optional "profile=$ASL_GPU_PROFILE; no known host GPU node" WARN; fi
if [ "$mounted" = 1 ]; then
    (su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/xfwm4 -o -x /usr/bin/xfce4-session" 2>/dev/null) && check xfce required "XFCE session / window manager available" PASS || check xfce required "install Debian xfwm4 or xfce4-session" FAIL
    (su -c "chroot '$DEBIANPATH' /usr/bin/test -x /usr/bin/dbus-launch" 2>/dev/null) && check dbus required "dbus-launch available" PASS || check dbus required "install Debian dbus-x11" FAIL
    if su -c "chroot '$DEBIANPATH' /usr/bin/find /usr/share/vulkan/icd.d -type f -name '*.json' -print -quit 2>/dev/null | grep -q ." 2>/dev/null; then check vulkan optional "ICD JSON found" PASS; else check vulkan optional "no Vulkan ICD JSON found" WARN; fi
fi
exit "$fail"
