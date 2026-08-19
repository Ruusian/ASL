#!/bin/bash
# Mock Termux/Android environment for testing ASL outside of Android
# Provides fake paths, commands, and system files so scripts can be sourced/tested

# This is a helper library and must NOT enable `set -e` for callers.
# Each test suite sets its own shell options.
set -u

MOCK_ROOT="${MOCK_ROOT:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}/asl-mock-$UID}"
export MOCK_ROOT

setup_mock_env() {
    rm -rf "$MOCK_ROOT"
    mkdir -p "$MOCK_ROOT"/{dev/shm,dev/pts,proc,sys,tmp,var/lib,root,etc,usr/bin,usr/lib,usr/share/applications}
    mkdir -p "$MOCK_ROOT/usr/local/bin"
    mkdir -p "$MOCK_ROOT/data/local/tmp/chrootDebian"
    mkdir -p "$MOCK_ROOT/data/data/com.termux/files/usr"/{bin,lib,tmp,etc}
    mkdir -p "$MOCK_ROOT/home"
    mkdir -p "$MOCK_ROOT/root/.config/pulse"
    mkdir -p "$MOCK_ROOT/root/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$MOCK_ROOT/root/.config/autostart"
    mkdir -p "$MOCK_ROOT/root/Desktop"

    # Fake Termux PREFIX
    export PREFIX="$MOCK_ROOT/data/data/com.termux/files/usr"
    export HOME="$MOCK_ROOT/root"
    export TMPDIR="$PREFIX/tmp"
    export PATH="$PREFIX/bin:$PATH"

    # Fake Termux binaries
    for cmd in su rish shizuku-exec proot-distro termux-wake-lock termux-wake-unlock \
               termux-open termux-clipboard-set termux-clipboard-get \
               termux-notification termux-toast termux-setup-storage \
               pgrep pkill socat ssh-keygen sshd wget curl convert; do
        cat > "$PREFIX/bin/$cmd" << 'FAKECMD'
#!/bin/bash
echo "[mock] $0 called with: $@" >&2
exit 0
FAKECMD
        chmod +x "$PREFIX/bin/$cmd"
    done

    # Fake su that "works"
    cat > "$PREFIX/bin/su" << 'SUEOF'
#!/bin/bash
if [ "$1" = "-c" ]; then
    shift
    eval "$@"
else
    exec "$@"
fi
SUEOF
    chmod +x "$PREFIX/bin/su"

    # Fake /proc/cpuinfo
    cat > "$MOCK_ROOT/proc/cpuinfo" << 'CPUINFO'
processor	: 0
BogoMIPS	: 38.40
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32
CPU implementer	: 0x51
CPU architecture: 8
CPU variant	: 0x2
CPU part	: 0x805
CPU revision	: 14

processor	: 1
BogoMIPS	: 38.40
CPUINFO

    # Fake /proc/loadavg
    echo "0.52 0.38 0.29 2/487 12345" > "$MOCK_ROOT/proc/loadavg"

    # Fake /proc/mounts (empty — nothing mounted)
    touch "$MOCK_ROOT/proc/mounts"

    # Fake /proc/meminfo
    cat > "$MOCK_ROOT/proc/meminfo" << 'MEMINFO'
MemTotal:        7800000 kB
MemFree:         3200000 kB
MemAvailable:    4500000 kB
SwapTotal:       2000000 kB
SwapFree:        1800000 kB
MEMINFO

    # Fake /proc/uptime
    echo "86400.50 172800.10" > "$MOCK_ROOT/proc/uptime"

    # Fake sysfs
    mkdir -p "$MOCK_ROOT/sys/devices/system/cpu/cpu0/cpufreq"
    echo "2400000" > "$MOCK_ROOT/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
    echo "performance" > "$MOCK_ROOT/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    echo "1800000" > "$MOCK_ROOT/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
    echo "2800000" > "$MOCK_ROOT/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"

    # Fake battery
    mkdir -p "$MOCK_ROOT/sys/class/power_supply/battery"
    echo "75" > "$MOCK_ROOT/sys/class/power_supply/battery/capacity"
    echo "Discharging" > "$MOCK_ROOT/sys/class/power_supply/battery/status"
    echo "320" > "$MOCK_ROOT/sys/class/power_supply/battery/temp"

    # Fake thermal zones
    for zone in cpu-0-0 gpu-0 soc-0 quiet-therm; do
        mkdir -p "$MOCK_ROOT/sys/class/thermal/thermal_zone${zone}"
        echo "42000" > "$MOCK_ROOT/sys/class/thermal/thermal_zone${zone}/temp"
        echo "$zone" > "$MOCK_ROOT/sys/class/thermal/thermal_zone${zone}/type"
    done

    # Fake /data
    mkdir -p "$MOCK_ROOT/data"
    echo "32G" > /dev/null 2>&1 || true

    # Fake df output mock
    mkdir -p "$MOCK_ROOT/data/local/tmp"

    # Fake GPU device
    touch "$MOCK_ROOT/dev/kgsl-3d0"
    mkdir -p "$MOCK_ROOT/dev/dri"
    touch "$MOCK_ROOT/dev/dri/renderD128"

    # Fake /sys/class/dmi (for non-Android fallback)
    mkdir -p "$MOCK_ROOT/sys/class/dmi/id"

    # Fake getprop
    cat > "$PREFIX/bin/getprop" << 'GETPROP'
#!/bin/bash
case "$1" in
    ro.board.platform) echo "taro" ;;
    ro.hardware.chipname) echo "taro" ;;
    ro.product.model) echo "Test Phone" ;;
    ro.build.version.release) echo "14" ;;
    ro.build.version.sdk) echo "34" ;;
    net.dns1) echo "8.8.8.8" ;;
    net.dns2) echo "8.8.4.4" ;;
    *) echo "" ;;
esac
GETPROP
    chmod +x "$PREFIX/bin/getprop"

    # Fake ip command
    cat > "$PREFIX/bin/ip" << 'IPEOF'
#!/bin/bash
if [[ "$*" == *"-o -4 addr show"* ]]; then
    echo "2: wlan0    inet 192.168.1.100/24 brd 192.168.1.255 scope global wlan0"
fi
IPEOF
    chmod +x "$PREFIX/bin/ip"

    # Fake df
    cat > "$PREFIX/bin/df" << 'DFEOF'
#!/bin/bash
echo "Filesystem     Size  Used Avail Use% Mounted on"
echo "/dev/block/sda 128G   45G   83G  36% /data"
DFEOF
    chmod +x "$PREFIX/bin/df"

    # Fake uname
    cat > "$PREFIX/bin/uname" << 'UNAMEEOF'
#!/bin/bash
if [[ "$*" == *"-m"* ]]; then
    echo "aarch64"
elif [[ "$*" == *"-r"* ]]; then
    echo "5.15.0-android14-8"
else
    echo "Linux TestPhone 5.15.0-android14-8 #1 SMP PREEMPT aarch64 GNU/Linux"
fi
UNAMEEOF
    chmod +x "$PREFIX/bin/uname"

    export DEBIANPATH="$MOCK_ROOT/data/local/tmp/chrootDebian"
    export ASL_EXEC_MODE="root"
    export ASL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    echo "[mock] Mock environment initialized at $MOCK_ROOT"
}

cleanup_mock_env() {
    if [ -d "$MOCK_ROOT" ]; then
        rm -rf "$MOCK_ROOT"
        echo "[mock] Cleaned up $MOCK_ROOT"
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_mock_env
    echo "Mock env ready. DEBIANPATH=$DEBIANPATH PREFIX=$PREFIX"
fi
