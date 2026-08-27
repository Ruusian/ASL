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
    direct)
        check exec-mode required "native container environment (DIRECT mode)" PASS
        ;;
    root|*)
        if [ "$(su -c 'id -u' 2>/dev/null)" = 0 ]; then
            check exec-mode required "su grants Superuser root access (ROOT mode)" PASS
        else
            check exec-mode required "root access through su is unavailable (Magisk/KernelSU/APatch required)" FAIL
        fi
        ;;
esac

if command -v getenforce >/dev/null 2>&1; then
    se_mode=$(getenforce 2>/dev/null || echo "Unknown")
    check selinux optional "mode=$se_mode" PASS
fi
if [ -d "$DEBIANPATH" ] || asl_exec "test -d '$DEBIANPATH'" 2>/dev/null || [ "${ASL_EXEC_MODE:-}" = "direct" ]; then check debian-root required "$DEBIANPATH exists" PASS; else check debian-root required "$DEBIANPATH is missing (run 'asl install')" FAIL; fi
if [ "${ASL_EXEC_MODE:-}" = "direct" ]; then
    mounted=1
    check chroot optional "active container environment" PASS
elif is_mounted; then
    mounted=1
    check chroot optional "mounted" PASS
else
    mounted=0
    check chroot optional "not mounted; chroot checks skipped" WARN
fi
if [ "${ASL_EXEC_MODE:-}" = "direct" ]; then
    if [ -S /tmp/.X11-unix/X0 ] || [ -f /tmp/.X0-lock ] || pgrep -f "termux-x11|Xorg" >/dev/null 2>&1 || [ -n "${DISPLAY:-}" ]; then
        check termux-x11 required "X11 display server available (${DISPLAY:-:0})" PASS
    else
        check termux-x11 optional "X11 server not running (run 'asl desktop' on host)" WARN
    fi
else
    if command -v termux-x11 >/dev/null; then check termux-x11 required "client installed" PASS; else check termux-x11 required "install with: pkg install termux-x11" FAIL; fi
fi
if command -v pulseaudio >/dev/null || command -v pactl >/dev/null || [ -e /tmp/pulse-socket ]; then check pulseaudio required "PulseAudio sound system ready" PASS; else check pulseaudio required "install with: pkg install pulseaudio" FAIL; fi
if [ -d /sdcard ] && [ -w /sdcard ]; then check storage optional "/sdcard is writable" PASS; else check storage optional "/sdcard is unavailable or not writable" WARN; fi

# Phantom Process Killer (PPK) Check on Android 12+
sdk_ver=$(getprop ro.build.version.sdk 2>/dev/null || echo 0)
[[ "$sdk_ver" =~ ^[0-9]+$ ]] || sdk_ver=0
if [ "$sdk_ver" -gt 0 ] && [ "$sdk_ver" -lt 31 ]; then
    check phantom-proc optional "Phantom Process Killer not present (Android < 12, SDK $sdk_ver)" PASS
else
    max_phantom=$(asl_exec "device_config get activity_manager max_phantom_processes 2>/dev/null" 2>/dev/null || true)
    if [ "$max_phantom" = "2147483647" ] || [ "$max_phantom" = "disabled" ]; then
        check phantom-proc optional "Phantom Process Killer disabled ($max_phantom)" PASS
    else
        check phantom-proc optional "PPK default limits active (disable with: asl ppk off)" WARN
    fi
fi

# Clipboard bridge tool check
if command -v termux-clipboard-get >/dev/null 2>&1; then
    check clipboard optional "Termux API clipboard bridge available" PASS
else
    check clipboard optional "termux-clipboard-get missing (pkg install termux-api)" WARN
fi

asl_gpu_detect
if [ -e /dev/dri ] || [ -e /dev/kgsl-3d0 ]; then check gpu optional "profile=$ASL_GPU_PROFILE; host GPU node present" PASS; else check gpu optional "profile=$ASL_GPU_PROFILE; no known host GPU node" WARN; fi
if [ "$mounted" = 1 ]; then
    (asl_chroot_exec "test -x /usr/bin/xfwm4 -o -x /usr/bin/xfce4-session" 2>/dev/null) && check xfce optional "XFCE session / window manager available" PASS || check xfce optional "install Debian xfwm4 or xfce4-session" WARN
    (asl_chroot_exec "test -x /usr/bin/dbus-launch -o -x /usr/bin/dbus-daemon" 2>/dev/null) && check dbus optional "D-Bus daemon & launcher ready" PASS || check dbus optional "install Debian dbus-x11 / dbus" WARN
    (asl_chroot_exec "test -s /etc/machine-id" 2>/dev/null) && check machine-id optional "system machine-id initialized" PASS || check machine-id optional "/etc/machine-id uninitialized" WARN
    if asl_chroot_exec "find /usr/share/vulkan/icd.d -type f -name '*.json' -print -quit 2>/dev/null | grep -q ." 2>/dev/null; then check vulkan optional "ICD JSON found" PASS; else check vulkan optional "no Vulkan ICD JSON found" WARN; fi
fi
exit "$fail"
