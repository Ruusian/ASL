#!/bin/bash
# Android Subsystem for Linux (ASL): Automated One-Line Installer
# Installs dependencies, sets up ASL environment, downloads selected distro rootfs, and registers CLI commands.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/ASL"

# 1. Repository Setup & Common Functions Loading
if [ -d "$TARGET_DIR/.git" ]; then
    echo -e "\033[0;32m[*] Updating ASL repository at $TARGET_DIR...\033[0m"
    cd "$TARGET_DIR"
    # Verify the configured origin is the official ASL repo before updating
    # to avoid pulling code from a hijacked or mistyped remote.
    origin_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
    case "$origin_url" in
        *github.com/Ruusian/ASL*)
            git pull origin master 2>/dev/null || true
            ;;
        *)
            echo -e "\033[0;33m[!] Skipping auto-update: origin remote is not the official ASL repo (got: ${origin_url:-none}).${RESET}"
            ;;
    esac
else
    echo -e "\033[0;32m[*] Cloning ASL repository to $TARGET_DIR...\033[0m"
    if ! git clone https://github.com/Ruusian/ASL.git "$TARGET_DIR" 2>/dev/null && \
       ! git clone https://github.com/Ruusian/ASL.git "$TARGET_DIR" 2>/dev/null; then
        echo -e "\033[0;31m[!] Failed to clone ASL repository. Check your internet connection.\033[0m"
        exit 1
    fi
    cd "$TARGET_DIR"
fi

if [ -f "$TARGET_DIR/core/common.sh" ]; then
    source "$TARGET_DIR/core/common.sh"
elif [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

: "${DEBIANPATH:=/data/local/tmp/chrootDebian}"
export DEBIANPATH

# Safety guard: DEBIANPATH is used with `rm -rf` and `mkdir -p` as root.
# Refuse values that could destroy the device if misconfigured.
asl_validate_debianpath() {
    local p="$1"
    case "$p" in
        /|/data|/data/|/sdcard|/sdcard/|/system|/system/|/vendor|/vendor/)
            echo -e "\033[0;31m[!] Refusing unsafe DEBIANPATH: $p${RESET}" >&2
            return 1
            ;;
    esac
    case "$p" in
        /*) return 0 ;;
        *) echo -e "\033[0;31m[!] DEBIANPATH must be an absolute path: $p${RESET}" >&2; return 1 ;;
    esac
}
if ! asl_validate_debianpath "$DEBIANPATH"; then
    echo -e "\033[0;31m[!] Aborting installation due to unsafe DEBIANPATH.${RESET}"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

DISTRO_TYPE="${TYPE:-auto}" # debian, ubuntu, arch, alpine, fedora, kali, void, opensuse, or auto
INSTALL_DESKTOP="${DESKTOP:-auto}" # yes, no, auto

# Parse arguments (--debian, --ubuntu, --arch, --alpine, --fedora, --kali, --void, --opensuse, --skip, --desktop, --no-desktop, --type=X, --distro=X)
while [ $# -gt 0 ]; do
    case "$1" in
        --standard|--base|--debian|--modded)
            DISTRO_TYPE="debian"
            shift
            ;;
        --ubuntu)
            DISTRO_TYPE="ubuntu"
            shift
            ;;
        --arch|--archlinux)
            DISTRO_TYPE="arch"
            shift
            ;;
        --alpine)
            DISTRO_TYPE="alpine"
            shift
            ;;
        --fedora)
            DISTRO_TYPE="fedora"
            shift
            ;;
        --kali)
            DISTRO_TYPE="kali"
            shift
            ;;
        --void)
            DISTRO_TYPE="void"
            shift
            ;;
        --opensuse|--suse)
            DISTRO_TYPE="opensuse"
            shift
            ;;
        --desktop)
            INSTALL_DESKTOP="yes"
            shift
            ;;
        --no-desktop|--headless)
            INSTALL_DESKTOP="no"
            shift
            ;;
        --skip)
            DISTRO_TYPE="skip"
            shift
            ;;
        --root)
            shift
            ;;
        --type=*|--distro=*)
            DISTRO_TYPE="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN} 🚀 Android Subsystem for Linux (ASL) Installer     ${RESET}"
echo -e "${CYAN}====================================================${RESET}"

# 1. Environment & Platform Checks
export DEBIAN_FRONTEND=noninteractive
export PIP_NO_INPUT=1
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_DEFAULT_TIMEOUT=15

if [ -z "$PREFIX" ] || [[ "$PREFIX" != *"/com.termux/"* ]]; then
    echo -e "${RED}[!] Error: ASL must be run inside Termux on Android.${RESET}"
    exit 1
fi

mkdir -p "$PREFIX/etc" "$PREFIX/tmp"

echo -e "${GREEN}[*] Verifying Superuser root access (su)...${RESET}"
if [ "$(su -c 'id -u' 2>/dev/null)" != "0" ]; then
    echo -e "${RED}[!] Error: ASL requires Superuser root access (Magisk / KernelSU / APatch).${RESET}"
    echo -e "${YELLOW}[!] Grant root access in your root manager and run 'asl install' again.${RESET}"
    exit 1
fi

ASL_EXEC_MODE="root"
export ASL_EXEC_MODE
echo -e "${GREEN}[✓] Execution Mode: ROOT (su) Kernel Chroot (Full Hardware Acceleration)${RESET}"
echo "root" > "$PREFIX/etc/asl_exec_mode"

# 2. Package Installation
echo -e "${GREEN}[*] Verifying required Termux packages...${RESET}"
export DEBIAN_FRONTEND=noninteractive
MISSING_PKGS=()
for p in git pulseaudio tsu socat wget unzip xz proot-distro; do
    if ! command -v "$p" >/dev/null 2>&1; then
        if [ "$p" = "xz" ]; then
            MISSING_PKGS+=("xz-utils")
        else
            MISSING_PKGS+=("$p")
        fi
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${CYAN}[*] Installing missing dependencies: ${MISSING_PKGS[*]}...${RESET}"
    pkg install -y x11-repo 2>/dev/null || true
    pkg update -y 2>/dev/null || true
    if ! pkg install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${MISSING_PKGS[@]}" termux-x11-nightly virglrenderer-android 2>/dev/null && \
       ! pkg install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${MISSING_PKGS[@]}" termux-x11 virglrenderer-android 2>/dev/null; then
        echo -e "${YELLOW}[!] Note: Could not fetch packages from online mirror (offline or network policy).${RESET}"
    fi
else
    echo -e "${GREEN}[✓] Required Termux packages are already installed.${RESET}"
fi

# Automated repair for broken Termux package dependencies (e.g. ncurses mismatches)
if ! command -v proot-distro >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Termux package manager encountered held/broken dependencies. Running automated repair...${RESET}"
    apt-get install -y --allow-downgrades --fix-broken ncurses ncurses-utils proot-distro git pulseaudio tsu socat wget unzip xz-utils 2>/dev/null || {
        echo -e "${RED}[!] Automatic package repair failed.${RESET}"
        exit 1
    }
fi

# Re-verify Repository Clone now that git is installed
if [ ! -d "$TARGET_DIR/.git" ]; then
    echo -e "${GREEN}[*] Provisioning ASL repository to $TARGET_DIR...${RESET}"
    (git clone https://github.com/Ruusian/ASL.git "$TARGET_DIR" 2>/dev/null || git clone https://github.com/Ruusian/ASL.git "$TARGET_DIR" 2>/dev/null) || {
        echo -e "${RED}[!] Failed to clone the ASL repository.${RESET}"
        exit 1
    }
    cd "$TARGET_DIR"
fi

# 3. Interactive Distro Edition Selection
if { [ -t 0 ] || [ -c /dev/tty ]; } && [ "$DISTRO_TYPE" = "auto" ]; then
    echo -e "\n${CYAN}====================================================${RESET}"
    echo -e "${CYAN} 🐧 Select Linux Subsystem Distribution / Edition:   ${RESET}"
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "  1) ${GREEN}Debian Trixie${RESET} (Recommended - Turnip Mesa Vulkan, Audio, and Desktop)"
    echo -e "  2) ${CYAN}Ubuntu LTS${RESET} (Official Ubuntu 24.04 Noble via proot-distro)"
    echo -e "  3) ${CYAN}Arch Linux${RESET} (Official Arch Rolling via proot-distro)"
    echo -e "  4) ${CYAN}Alpine Linux${RESET} (Official Alpine Lightweight via proot-distro)"
    echo -e "  5) ${CYAN}Kali Linux${RESET} (Official Kali Security via proot-distro)"
    echo -e "  6) ${CYAN}Fedora Linux${RESET} (Official Fedora Workstation via proot-distro)"
    echo -e "  7) ${CYAN}Void Linux${RESET} (Official Void Linux via proot-distro)"
    echo -e "  8) ${YELLOW}Skip rootfs setup${RESET} (Use existing rootfs at /data/local/tmp/chrootDebian)"
    echo -e ""
    distro_choice=""
    if [ -c /dev/tty ]; then
        read -r -p "Select choice [1-8, default: 1]: " distro_choice < /dev/tty 2>/dev/null || true
    else
        read -r -p "Select choice [1-8, default: 1]: " distro_choice || true
    fi
    case "$distro_choice" in
        1|"") DISTRO_TYPE="debian" ;;
        2) DISTRO_TYPE="ubuntu" ;;
        3) DISTRO_TYPE="arch" ;;
        4) DISTRO_TYPE="alpine" ;;
        5) DISTRO_TYPE="kali" ;;
        6) DISTRO_TYPE="fedora" ;;
        7) DISTRO_TYPE="void" ;;
        8) DISTRO_TYPE="skip" ;;
        *) DISTRO_TYPE="debian" ;;
    esac
fi

[ "$DISTRO_TYPE" = "auto" ] && DISTRO_TYPE="debian"

IMAGE_REF=""
DISTRO_NAME=""

case "$DISTRO_TYPE" in
    debian|modded|standard|base|"")
        IMAGE_REF="debian:trixie"
        DISTRO_NAME="Debian Trixie"
        ;;
    ubuntu)
        IMAGE_REF="ubuntu:24.04"
        DISTRO_NAME="Ubuntu 24.04 LTS"
        ;;
    arch|archlinux)
        IMAGE_REF="archlinux/archlinux:latest"
        DISTRO_NAME="Arch Linux"
        ;;
    alpine)
        IMAGE_REF="alpine:latest"
        DISTRO_NAME="Alpine Linux"
        ;;
    fedora)
        IMAGE_REF="fedora:latest"
        DISTRO_NAME="Fedora Linux"
        ;;
    kali)
        IMAGE_REF="kalilinux/kali-rolling:latest"
        DISTRO_NAME="Kali Linux"
        ;;
    void)
        IMAGE_REF="ghcr.io/void-linux/void-glibc:latest"
        DISTRO_NAME="Void Linux"
        ;;
    opensuse|suse)
        IMAGE_REF="opensuse/tumbleweed:latest"
        DISTRO_NAME="openSUSE Tumbleweed"
        ;;
    skip)
        IMAGE_REF=""
        DISTRO_NAME="Skip"
        ;;
    *)
        IMAGE_REF="$DISTRO_TYPE"
        DISTRO_NAME="$DISTRO_TYPE"
        ;;
esac

cleanup_installer() {
    proot-distro remove asl-temp >/dev/null 2>&1 || true
    rm -f "$PREFIX/tmp/asl-modded-temp.tar.xz" "$PREFIX/tmp"/asl-*-temp.* >/dev/null 2>&1 || true
}
trap cleanup_installer EXIT

# Rootfs replacement is destructive. Stop ASL first and independently verify
# that no mount remains at or below the chroot before removing any files.
ensure_chroot_unmounted_for_replace() {
    if is_mounted "$DEBIANPATH"; then
        echo -e "${YELLOW}[*] Stopping active chroot before overwrite...${RESET}"
        local stop_script="$TARGET_DIR/core/stop-chroot.sh"
        [ -f "$stop_script" ] || stop_script="$SCRIPT_DIR/core/stop-chroot.sh"
        if ! bash "$stop_script"; then
            echo -e "${RED}[!] Failed to stop the active chroot; refusing to replace its rootfs.${RESET}"
            return 1
        fi
    fi
    if is_mounted "$DEBIANPATH"; then
        echo -e "${RED}[!] ASL mounts remain below $DEBIANPATH; refusing to replace its rootfs.${RESET}"
        return 1
    fi
}

# 4. Rootfs Download & Chroot Provisioning
if [ "$DISTRO_TYPE" != "skip" ] && [ -n "$IMAGE_REF" ]; then
    echo -e "${GREEN}[*] Provisioning Linux Subsystem Rootfs (${DISTRO_NAME})...${RESET}"
    if [ -d "$DEBIANPATH/etc" ] || asl_exec "test -d '$DEBIANPATH/etc'" 2>/dev/null; then
        echo -e "${YELLOW}[!] Existing chroot detected at $DEBIANPATH.${RESET}"
        overwrite_confirm=""
        if [ -c /dev/tty ]; then
            read -r -p "Overwrite existing chroot with fresh $DISTRO_NAME rootfs? [y/N]: " overwrite_confirm < /dev/tty 2>/dev/null || true
        elif [ -t 0 ]; then
            read -r -p "Overwrite existing chroot with fresh $DISTRO_NAME rootfs? [y/N]: " overwrite_confirm || true
        fi
        if [[ ! "$overwrite_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}[*] Keeping existing chroot environment.${RESET}"
            DISTRO_TYPE="skip"
            IMAGE_REF=""
        fi
    fi

    if [ "$DISTRO_TYPE" != "skip" ] && [ -n "$IMAGE_REF" ]; then
        echo -e "${GREEN}[*] Fetching and unpacking official $DISTRO_NAME rootfs via proot-distro ($IMAGE_REF)...${RESET}"
        proot-distro remove asl-temp >/dev/null 2>&1 || true
        if ! proot-distro install -n asl-temp "$IMAGE_REF"; then
            echo -e "${RED}[!] Error: proot-distro failed to download or unpack $IMAGE_REF.${RESET}"
            exit 1
        fi

        TEMP_ROOTFS=""
        if [ -d "$PREFIX/var/lib/proot-distro/containers/asl-temp/rootfs" ]; then
            TEMP_ROOTFS="$PREFIX/var/lib/proot-distro/containers/asl-temp/rootfs"
        elif [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/asl-temp" ]; then
            TEMP_ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/asl-temp"
        fi

        if [ -n "$TEMP_ROOTFS" ] && [ -d "$TEMP_ROOTFS" ]; then
            echo -e "${GREEN}[*] Copying $DISTRO_NAME rootfs into chroot location ($DEBIANPATH)...${RESET}"
            ensure_chroot_unmounted_for_replace || exit 1
            if ! asl_exec "rm -rf '$DEBIANPATH' && mkdir -p '$DEBIANPATH' && cp -af '$TEMP_ROOTFS/.' '$DEBIANPATH/'"; then
                echo -e "${RED}[!] Failed to copy the rootfs into $DEBIANPATH.${RESET}"
                exit 1
            fi
            proot-distro remove asl-temp >/dev/null 2>&1 || true

            # Configure DNS & hosts & APT performance
            asl_chroot_exec 'mkdir -p /etc && echo "nameserver 1.1.1.1" > /etc/resolv.conf && echo "nameserver 8.8.8.8" >> /etc/resolv.conf && echo "127.0.0.1 localhost" > /etc/hosts' 2>/dev/null || true
            asl_chroot_exec 'if [ -d /etc/apt ]; then mkdir -p /etc/apt/apt.conf.d && echo "Acquire::GzipIndexes \"true\";" > /etc/apt/apt.conf.d/99gzip; fi' 2>/dev/null || true
            asl_chroot_exec 'if [ ! -f /etc/shadow ]; then touch /etc/shadow && chown root:shadow /etc/shadow 2>/dev/null || true; chmod 640 /etc/shadow 2>/dev/null || true; fi' 2>/dev/null || true
            echo -e "${GREEN}[✓] $DISTRO_NAME rootfs provisioned successfully!${RESET}"
        else
            echo -e "${RED}[!] Error: Failed to locate extracted rootfs for $IMAGE_REF.${RESET}"
            exit 1
        fi
    fi
fi

# 5. Global Binary Linking & Android AID setup
echo -e "${GREEN}[*] Installing ASL system runtime to ${PREFIX:-/data/data/com.termux/files/usr}/share/asl...${RESET}"
INSTALL_DIR="${PREFIX:-/data/data/com.termux/files/usr}/share/asl"
mkdir -p "$INSTALL_DIR"
for d in bin core desktop tools docs; do
    if [ -d "$TARGET_DIR/$d" ]; then
        mkdir -p "$INSTALL_DIR/$d"
        cp -a "$TARGET_DIR/$d/." "$INSTALL_DIR/$d/"
    fi
done

chmod +x "$TARGET_DIR/bin/asl" "$INSTALL_DIR/bin/asl" 2>/dev/null || true
find "$TARGET_DIR" "$INSTALL_DIR" -maxdepth 3 -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

mkdir -p "$PREFIX/bin"
ln -sf "$INSTALL_DIR/bin/asl" "$PREFIX/bin/asl"

echo -e "${GREEN}[*] Applying Android GID mappings...${RESET}"
if ! bash "$INSTALL_DIR/core/android-aid.sh" setup; then
    echo -e "${RED}[!] Android GID mapping failed. Installation cannot continue safely.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Provisioning auto-configured SoC GPU drivers & hardware acceleration...${RESET}"
if ! (
    source "$INSTALL_DIR/core/gpu-profile.sh"
    asl_gpu_install_drivers
); then
    echo -e "${RED}[!] GPU driver provisioning failed. Installation cannot continue safely.${RESET}"
    exit 1
fi

if [ "$INSTALL_DESKTOP" != "no" ] && [ "$DISTRO_TYPE" != "skip" ]; then
    case "$DISTRO_TYPE" in
        debian|ubuntu|"")
            echo -e "${GREEN}[*] Provisioning XFCE4 desktop environment & D-Bus...${RESET}"
            if [ -f "$INSTALL_DIR/desktop/start-desktop.sh" ]; then
                bash "$INSTALL_DIR/desktop/start-desktop.sh" setup || echo -e "${YELLOW}[!] Desktop package provisioning finished with notice.${RESET}"
            fi
            ;;
    esac
fi

echo -e "${GREEN}[*] Provisioning OpenClaude AI agent environment...${RESET}"
if [ -f "$INSTALL_DIR/core/openclaude-setup.sh" ]; then
    bash "$INSTALL_DIR/core/openclaude-setup.sh" || true
fi

# Synchronize dynamic environment
if [ -f "$INSTALL_DIR/core/gpu-profile.sh" ]; then
    (
        source "$INSTALL_DIR/core/gpu-profile.sh"
        asl_sync_chroot_env 2>/dev/null || true
    )
fi

echo -e "${CYAN}====================================================${RESET}"
echo -e "${GREEN}[✓] Android Subsystem for Linux (ASL) Installed!     ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo -e "Type ${YELLOW}asl${RESET} to open the interactive dashboard."
echo -e "Type ${YELLOW}asl start${RESET} to mount your Linux chroot environment."
echo -e "Type ${YELLOW}asl desktop start${RESET} to launch XFCE4 desktop with Termux:X11."
echo -e "${CYAN}====================================================${RESET}"
