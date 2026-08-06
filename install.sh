#!/bin/bash
# Android Subsystem for Linux (ASL) / AndroidLinux-SuperKit: Automated One-Line Installer
# Installs dependencies, sets up ASL environment, downloads selected distro rootfs, and registers CLI commands.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

SELECTED_DISTRO="${DISTRO:-}"

# Parse arguments (--distro=X or -d X)
while [ $# -gt 0 ]; do
    case "$1" in
        --distro=*)
            SELECTED_DISTRO="${1#*=}"
            shift
            ;;
        -d|--distro)
            SELECTED_DISTRO="${2:-}"
            shift 2 || shift 1
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
if [ -z "$PREFIX" ] || [[ "$PREFIX" != *"/com.termux/"* ]]; then
    echo -e "${RED}[!] Error: ASL must be run inside Termux on Android.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Checking root access (su)...${RESET}"
if ! su -c "id -u" >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Warning: Root access via 'su' was not detected or prompt timed out.${RESET}"
    echo -e "${YELLOW}[!] ASL requires root access (su) to manage chroot mounts.${RESET}"
else
    echo -e "${GREEN}[✓] Root access confirmed.${RESET}"
fi

# 2. Package Installation
echo -e "${GREEN}[*] Installing required Termux packages...${RESET}"
pkg update -y || true
pkg install -y git pulseaudio termux-x11-nightly virglrenderer-android tsu socat wget unzip proot-distro 2>/dev/null || \
pkg install -y git pulseaudio termux-x11 virglrenderer-android tsu socat wget unzip proot-distro 2>/dev/null || true

# 3. Interactive Distro Selection
if [ -z "$SELECTED_DISTRO" ]; then
    if [ -t 0 ]; then
        echo -e "\n${CYAN}====================================================${RESET}"
        echo -e "${CYAN} 🐧 Choose Linux Distribution for ASL Chroot:        ${RESET}"
        echo -e "${CYAN}====================================================${RESET}"
        echo -e "  1) ${GREEN}Debian${RESET} (Trixie/Bookworm - Recommended for Wine, Box64 & Desktop)"
        echo -e "  2) ${GREEN}Ubuntu${RESET} (24.04 LTS Noble)"
        echo -e "  3) ${GREEN}Arch Linux${RESET} (Rolling)"
        echo -e "  4) ${GREEN}Alpine Linux${RESET} (Ultra-lightweight)"
        echo -e "  5) ${GREEN}Kali Linux${RESET} (Penetration Testing)"
        echo -e "  6) ${GREEN}Fedora Linux${RESET} (Latest)"
        echo -e "  7) ${YELLOW}Skip rootfs setup${RESET} (Use existing rootfs at /data/local/tmp/chrootDebian)"
        echo -e ""
        read -r -p "Select choice [1-7, default: 1]: " distro_choice
        case "$distro_choice" in
            2) SELECTED_DISTRO="ubuntu" ;;
            3) SELECTED_DISTRO="archlinux" ;;
            4) SELECTED_DISTRO="alpine" ;;
            5) SELECTED_DISTRO="kali" ;;
            6) SELECTED_DISTRO="fedora" ;;
            7) SELECTED_DISTRO="skip" ;;
            1|"") SELECTED_DISTRO="debian" ;;
            *) SELECTED_DISTRO="debian" ;;
        esac
    else
        SELECTED_DISTRO="debian"
    fi
fi

IMAGE_REF=""
case "$SELECTED_DISTRO" in
    debian) IMAGE_REF="debian:trixie" ;;
    ubuntu) IMAGE_REF="ubuntu:24.04" ;;
    arch|archlinux) IMAGE_REF="archlinux/archlinux:latest" ;;
    alpine) IMAGE_REF="alpine:latest" ;;
    kali|kalilinux) IMAGE_REF="kalilinux/kali-rolling" ;;
    fedora) IMAGE_REF="fedora:latest" ;;
    skip) IMAGE_REF="" ;;
    *) IMAGE_REF="debian:trixie" ;;
esac

cleanup_installer() {
    proot-distro remove asl-temp >/dev/null 2>&1 || true
}
trap cleanup_installer EXIT

# 4. Rootfs Download & Chroot Provisioning
DEBIANPATH="/data/local/tmp/chrootDebian"
if [ -n "$IMAGE_REF" ]; then
    echo -e "${GREEN}[*] Provisioning $SELECTED_DISTRO rootfs ($IMAGE_REF)...${RESET}"
    if su -c "test -d '$DEBIANPATH/etc'"; then
        echo -e "${YELLOW}[!] Existing chroot detected at $DEBIANPATH.${RESET}"
        if [ -t 0 ]; then
            read -r -p "Overwrite existing chroot with fresh $SELECTED_DISTRO rootfs? [y/N]: " overwrite_confirm
            if [[ ! "$overwrite_confirm" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}[*] Keeping existing chroot environment.${RESET}"
                IMAGE_REF=""
            fi
        else
            echo -e "${GREEN}[*] Keeping existing chroot environment.${RESET}"
            IMAGE_REF=""
        fi
    fi

    if [ -n "$IMAGE_REF" ]; then
        echo -e "${GREEN}[*] Fetching and unpacking $IMAGE_REF via proot-distro...${RESET}"
        proot-distro remove asl-temp >/dev/null 2>&1 || true
        proot-distro install -n asl-temp "$IMAGE_REF" || {
            echo -e "${RED}[!] Error: proot-distro failed to download or unpack $IMAGE_REF.${RESET}"
            exit 1
        }

        TEMP_ROOTFS="$PREFIX/var/lib/proot-distro/containers/asl-temp/rootfs"
        if [ -d "$TEMP_ROOTFS" ]; then
            echo -e "${GREEN}[*] Copying rootfs into root chroot location ($DEBIANPATH)...${RESET}"
            su -c "mkdir -p '$DEBIANPATH' && cp -af '$TEMP_ROOTFS/.' '$DEBIANPATH/'"
            proot-distro remove asl-temp >/dev/null 2>&1 || true

            # Configure DNS & hosts
            su -c "chroot '$DEBIANPATH' /bin/sh -c 'echo \"nameserver 1.1.1.1\" > /etc/resolv.conf && echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf && echo \"127.0.0.1 localhost\" > /etc/hosts'" 2>/dev/null || true
            echo -e "${GREEN}[✓] Rootfs provisioned successfully.${RESET}"
        else
            echo -e "${RED}[!] Error: Failed to locate extracted rootfs for $IMAGE_REF.${RESET}"
            exit 1
        fi
        fi
fi

# 5. Repository Setup
TARGET_DIR="$HOME/AndroidLinux-SuperKit"

if [ -d "$TARGET_DIR/.git" ]; then
    echo -e "${GREEN}[*] Updating existing ASL repository at $TARGET_DIR...${RESET}"
    cd "$TARGET_DIR"
    git pull origin master || true
else
    echo -e "${GREEN}[*] Cloning ASL repository to $TARGET_DIR...${RESET}"
    git clone https://github.com/Ruusian5/AndroidLinux-SuperKit.git "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

# 6. Global Binary Linking & Android AID setup
echo -e "${GREEN}[*] Registering 'asl' and 'superkit' CLI executables...${RESET}"
chmod +x "$TARGET_DIR/bin/superkit"
chmod +x "$TARGET_DIR/core/"*.sh
chmod +x "$TARGET_DIR/desktop/"*.sh
chmod +x "$TARGET_DIR/gaming/"*.sh

mkdir -p "$PREFIX/bin"
ln -sf "$TARGET_DIR/bin/superkit" "$PREFIX/bin/asl"
ln -sf "$TARGET_DIR/bin/superkit" "$PREFIX/bin/superkit"

echo -e "${GREEN}[*] Applying Android GID mappings...${RESET}"
"$TARGET_DIR/core/android-aid.sh" setup >/dev/null 2>&1 || true

echo -e "${CYAN}====================================================${RESET}"
echo -e "${GREEN}[✓] Android Subsystem for Linux (ASL) Installed!     ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo -e "Type ${YELLOW}asl${RESET} (or ${YELLOW}superkit${RESET}) to open the interactive dashboard."
echo -e "Type ${YELLOW}asl start${RESET} to mount your Linux chroot environment."
echo -e "Type ${YELLOW}asl desktop start${RESET} to launch XFCE4 desktop with Termux:X11."
echo -e "Type ${YELLOW}asl setup-gaming${RESET} to auto-configure Wine, Box64 & DXVK."
echo -e "${CYAN}====================================================${RESET}"
