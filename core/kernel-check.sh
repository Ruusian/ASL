#!/bin/bash
# ASL: Kernel Configuration Check
# Checks kernel capabilities for ASL features

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_kernel_check() {
    local c_reset=$'\033[0m' c_bold=$'\033[1m' c_cyan=$'\033[36m'
    local c_green=$'\033[32m' c_yellow=$'\033[33m' c_red=$'\033[31m'

    printf '%s=== ASL Kernel Configuration Check ===%s\n' "$c_cyan$c_bold" "$c_reset"
    echo ""

    # Kernel version
    echo "Kernel Version:"
    echo "  $(uname -r)"
    echo ""

    # Check if we can read kernel config
    local kernel_config="/proc/config.gz"
    if [ ! -r "$kernel_config" ]; then
        kernel_config="/boot/config-$(uname -r)"
    fi

    if [ -r "$kernel_config" ]; then
        echo "Kernel Config: Available"
        echo ""
        
        # Essential features for ASL
        echo "Essential Features:"
        
        # Namespaces (required for containerization/chroot)
        check_config "CONFIG_NAMESPACES" "Namespaces (required for chroot)" "y"
        check_config "CONFIG_UTS_NS" "UTS namespace" "y"
        check_config "CONFIG_IPC_NS" "IPC namespace" "y"
        check_config "CONFIG_PID_NS" "PID namespace" "y"
        check_config "CONFIG_NET_NS" "Network namespace" "y"
        check_config "CONFIG_USER_NS" "User namespace" "y"
        
        echo ""
        echo "Chroot Support:"
        check_config "CONFIG_CHROOT" "Chroot support" "y"
        check_config "CONFIG_NAMESPACES" "Namespace support" "y"
        
        echo ""
        echo "GPU/Graphics:"
        check_config "CONFIG_DRM" "Direct Rendering Manager" "y"
        check_config "CONFIG_DRM_MSM" "MSM DRM driver (Adreno)" "y"
        check_config "CONFIG_MSM_KGSL" "Qualcomm KGSL driver" "y"

        echo ""
        echo "Networking:"
        check_config "CONFIG_NET" "Networking support" "y"
        check_config "CONFIG_INET" "IPv4 networking" "y"
        check_config "CONFIG_IPV6" "IPv6 networking" "y"

        echo ""
        echo "Security:"
        check_config "CONFIG_SECCOMP" "Seccomp filtering" "y"
        check_config "CONFIG_SECURITY" "Security framework" "y"

        echo ""
        echo "Memory Management:"
        check_config "CONFIG_ZRAM" "ZRAM compression" "y"
        check_config "CONFIG_SWAP" "Swap support" "y"

    else
        echo "Kernel Config: Not available (cannot read /proc/config.gz or /boot/config-*)"
        echo "  Some features may not be detectable"
    fi

    # Check actual capabilities
    echo ""
    echo "Actual Capabilities:"

    # Check if chroot works
    if [ "$(id -u)" -eq 0 ] || su -c "id -u" >/dev/null 2>&1; then
        if su -c "chroot / /bin/true 2>/dev/null || chroot / /system/bin/sh -c 'exit 0' 2>/dev/null" 2>/dev/null || [ "$(id -u)" -eq 0 ]; then
            echo "  [✓] Chroot: Works (Superuser/Root available)"
        else
            echo "  [✗] Chroot: Blocked"
        fi
    else
        echo "  [✗] Chroot: Superuser/Root not available"
    fi

    # Check namespaces
    if unshare --pid --fork /bin/true 2>/dev/null || su -c "unshare --pid --fork /bin/true" 2>/dev/null; then
        echo "  [✓] PID namespace: Works"
    else
        echo "  [ ] PID namespace: Limited or unshare restricted"
    fi
    
    # Check GPU access
    if [ -c /dev/kgsl-3d0 ]; then
        echo "  [✓] GPU device: /dev/kgsl-3d0 accessible"
    elif [ -c /dev/dri/renderD128 ]; then
        echo "  [✓] GPU device: /dev/dri/renderD128 accessible"
    else
        echo "  [✗] GPU device: Not found or not accessible"
    fi
    
    # Check memory capabilities
    echo ""
    echo "Memory Capabilities:"
    if [ -d /sys/block/zram0 ]; then
        echo "  [✓] ZRAM: Available"
    else
        echo "  [✗] ZRAM: Not available"
    fi
    
    if swapon --show 2>/dev/null | grep -q "/"; then
        echo "  [✓] File swap: Available"
    else
        echo "  [ ] File swap: Not configured"
    fi

    # Recommendations
    echo ""
    echo "Recommendations:"
    
    # Check kernel version
    local major minor
    major=$(uname -r | cut -d. -f1 | sed 's/[^0-9].*//')
    minor=$(uname -r | cut -d. -f2 | sed 's/[^0-9].*//')
    [ -n "$major" ] && [[ "$major" =~ ^[0-9]+$ ]] || major=0
    [ -n "$minor" ] && [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
    if [ "$major" -lt 4 ] || ([ "$major" -eq 4 ] && [ "$minor" -lt 14 ]); then
        echo "  [!] Kernel $major.$minor is very old (4.14+ recommended for ASL)"
    fi
    
    # Check if running as root
    if [ "$(id -u)" -eq 0 ]; then
        echo "  [✓] Running as root (full access)"
    else
        echo "  [ ] Running as user (some features may be limited)"
    fi
}

check_config() {
    local config="$1" description="$2" expected="$3"
    local value
    
    if [ -r "/proc/config.gz" ]; then
        value=$(zcat /proc/config.gz 2>/dev/null | grep "^${config}=" | cut -d= -f2 || true)
    elif [ -r "/boot/config-$(uname -r)" ]; then
        value=$(grep "^${config}=" "/boot/config-$(uname -r)" 2>/dev/null | cut -d= -f2 || true)
    fi
    
    if [ -z "$value" ]; then
        echo "    $description: Not found"
    elif [ "$value" = "$expected" ] || [ "$value" = "y" ] || [ "$value" = "m" ]; then
        echo "    [✓] $description: $value"
    else
        echo "    [✗] $description: $value (expected $expected)"
    fi
}

case "${1:-check}" in
    check|status)
        asl_kernel_check
        ;;
    *)
        echo "Usage: $0 [check]"
        ;;
esac
