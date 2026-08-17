#!/bin/bash
# Android Subsystem for Linux (ASL): Automated One-Line Installer
# Installs dependencies, sets up ASL environment, downloads selected distro rootfs, and registers CLI commands.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

SELECTED_DISTRO="debian"
DISTRO_TYPE="${TYPE:-auto}" # modded, standard, or auto

# Parse arguments (--modded, --standard, --type=X)
while [ $# -gt 0 ]; do
    case "$1" in
        --modded)
            DISTRO_TYPE="modded"
            shift
            ;;
        --standard|--base)
            DISTRO_TYPE="standard"
            shift
            ;;
        --type=*)
            DISTRO_TYPE="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN} 🚀 ASL Debian Snapdragon Subsystem Installer       ${RESET}"
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
pkg install -y x11-repo 2>/dev/null || true
pkg update -y || true
pkg install -y git pulseaudio termux-x11-nightly virglrenderer-android tsu socat wget unzip xz-utils proot-distro 2>/dev/null || \
pkg install -y git pulseaudio termux-x11 virglrenderer-android tsu socat wget unzip xz-utils proot-distro 2>/dev/null || true

# 3. Interactive Distro Edition Selection
if [ -t 0 ] && [ "$DISTRO_TYPE" = "auto" ]; then
    echo -e "\n${CYAN}====================================================${RESET}"
    echo -e "${CYAN} 🐧 Select Debian Snapdragon Rootfs Edition:        ${RESET}"
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "  1) ${GREEN}Debian Modded Rootfs${RESET} (Pre-configured Turnip Mesa Vulkan, Box64, Wine64 & XFCE)"
    echo -e "  2) ${CYAN}Debian Clean Base${RESET} (Official Debian Trixie via proot-distro)"
    echo -e "  3) ${YELLOW}Skip rootfs setup${RESET} (Use existing rootfs at /data/local/tmp/chrootDebian)"
    echo -e ""
    read -r -p "Select choice [1-3, default: 1]: " distro_choice
    case "$distro_choice" in
        1|"") DISTRO_TYPE="modded" ;;
        2) DISTRO_TYPE="standard" ;;
        3) DISTRO_TYPE="skip" ;;
        *) DISTRO_TYPE="modded" ;;
    esac
fi

[ "$DISTRO_TYPE" = "auto" ] && DISTRO_TYPE="modded"

IMAGE_REF="debian:trixie"
IS_MODDED=false
[ "$DISTRO_TYPE" = "modded" ] && IS_MODDED=true

cleanup_installer() {
    proot-distro remove asl-temp >/dev/null 2>&1 || true
    rm -f "$PREFIX/tmp/asl-modded-temp.tar.xz" >/dev/null 2>&1 || true
}
trap cleanup_installer EXIT

# Rootfs replacement is destructive. Stop ASL first and independently verify
# that no mount remains at or below the chroot before removing any files.
ensure_chroot_unmounted_for_replace() {
    if su -c "grep -q -F ' $DEBIANPATH ' /proc/mounts || grep -q -F ' $DEBIANPATH/' /proc/mounts" 2>/dev/null; then
        echo -e "${YELLOW}[*] Stopping active chroot before overwrite...${RESET}"
        if ! bash "$SCRIPT_DIR/core/stop-chroot.sh"; then
            echo -e "${RED}[!] Failed to stop the active chroot; refusing to replace its rootfs.${RESET}"
            return 1
        fi
    fi
    if su -c "grep -q -F ' $DEBIANPATH ' /proc/mounts || grep -q -F ' $DEBIANPATH/' /proc/mounts" 2>/dev/null; then
        echo -e "${RED}[!] ASL mounts remain below $DEBIANPATH; refusing to replace its rootfs.${RESET}"
        return 1
    fi
}

# 4. Rootfs Download & Chroot Provisioning
DEBIANPATH="/data/local/tmp/chrootDebian"
if [ "$DISTRO_TYPE" != "skip" ]; then
    echo -e "${GREEN}[*] Provisioning Debian Snapdragon rootfs (Edition: ${DISTRO_TYPE})...${RESET}"
    if su -c "test -d '$DEBIANPATH/etc'"; then
        echo -e "${YELLOW}[!] Existing chroot detected at $DEBIANPATH.${RESET}"
        if [ -t 0 ]; then
            read -r -p "Overwrite existing chroot with fresh Debian rootfs? [y/N]: " overwrite_confirm
            if [[ ! "$overwrite_confirm" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}[*] Keeping existing chroot environment.${RESET}"
                DISTRO_TYPE="skip"
            fi
        else
            echo -e "${GREEN}[*] Keeping existing chroot environment.${RESET}"
            DISTRO_TYPE="skip"
        fi
    fi

    if [ "$DISTRO_TYPE" != "skip" ]; then
        if [ "$IS_MODDED" = "true" ]; then
            RELEASE_URL="https://github.com/Ruusian5/ASL/releases/latest/download/asl-debian-modded-arm64.tar.xz"
            TEMP_TAR="$PREFIX/tmp/asl-modded-temp.tar.xz"
            echo -e "${GREEN}[*] Downloading ASL Exclusive Debian Modded Rootfs archive...${RESET}"
            echo -e "${CYAN}    URL: $RELEASE_URL${RESET}"

            if wget -q --show-progress -O "$TEMP_TAR" "$RELEASE_URL" 2>/dev/null || curl -L -o "$TEMP_TAR" "$RELEASE_URL"; then
                echo -e "${GREEN}[*] Verifying downloaded archive checksum...${RESET}"
                SHA256SUMS_URL="https://github.com/Ruusian5/ASL/releases/latest/download/SHA256SUMS"
                TEMP_SUMS="$PREFIX/tmp/asl-modded-SHA256SUMS"
                EXPECTED=""
                if ! (wget -q -O "$TEMP_SUMS" "$SHA256SUMS_URL" 2>/dev/null || curl -fsSL -o "$TEMP_SUMS" "$SHA256SUMS_URL"); then
                    echo -e "${RED}[!] Could not download the SHA256SUMS sidecar; refusing to extract.${RESET}"
                    rm -f "$TEMP_TAR" "$TEMP_SUMS"
                    exit 1
                fi
                EXPECTED=$(awk '$2 == "asl-debian-modded-arm64.tar.xz" && $1 ~ /^[[:xdigit:]]{64}$/ { print $1 }' "$TEMP_SUMS" | head -n 1)
                rm -f "$TEMP_SUMS"
                if [ -z "$EXPECTED" ]; then
                    echo -e "${RED}[!] SHA256SUMS is missing a valid checksum for the modded rootfs; refusing to extract.${RESET}"
                    rm -f "$TEMP_TAR"
                    exit 1
                fi
                ACTUAL=$(sha256sum "$TEMP_TAR" | awk '{ print $1 }')
                if [ "$ACTUAL" != "$EXPECTED" ]; then
                    echo -e "${RED}[!] Checksum verification FAILED for modded rootfs archive.${RESET}"
                    echo -e "${RED}    Expected: $EXPECTED${RESET}"
                    echo -e "${RED}    Actual:   $ACTUAL${RESET}"
                    echo -e "${RED}    Refusing to extract. The release artifact may be corrupted or tampered with.${RESET}"
                    rm -f "$TEMP_TAR"
                    exit 1
                fi
                echo -e "${GREEN}[✓] Checksum verified (SHA-256: ${EXPECTED:0:16}...)${RESET}"
                echo -e "${GREEN}[*] Extracting prebuilt modded Debian rootfs into $DEBIANPATH...${RESET}"
                ensure_chroot_unmounted_for_replace || exit 1
                if ! su -c "rm -rf '$DEBIANPATH' && mkdir -p '$DEBIANPATH' && tar -xf '$TEMP_TAR' -C '$DEBIANPATH'"; then
                    echo -e "${RED}[!] Failed to extract the modded rootfs.${RESET}"
                    rm -f "$TEMP_TAR"
                    exit 1
                fi
                rm -f "$TEMP_TAR"
                # Configure DNS & hosts
                su -c "chroot '$DEBIANPATH' /bin/sh -c 'echo \"nameserver 1.1.1.1\" > /etc/resolv.conf && echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf && echo \"127.0.0.1 localhost\" > /etc/hosts'" 2>/dev/null || true
                # The release tarball excludes /etc/shadow; regenerate an empty one so
                # login works but root stays password-locked until the user runs passwd.
                su -c "chroot '$DEBIANPATH' /bin/sh -c 'if [ ! -f /etc/shadow ]; then touch /etc/shadow && chown root:shadow /etc/shadow && chmod 640 /etc/shadow; fi'" 2>/dev/null || true
                echo -e "${GREEN}[✓] ASL Exclusive Debian Modded Rootfs provisioned successfully!${RESET}"
            else
                echo -e "${YELLOW}[!] Modded release asset not found online yet. Falling back to Debian Trixie base image...${RESET}"
                IS_MODDED=false
            fi
        fi

        if [ "$IS_MODDED" = "false" ] && [ -n "$IMAGE_REF" ]; then
            echo -e "${GREEN}[*] Fetching and unpacking official Debian Trixie base via proot-distro...${RESET}"
            proot-distro remove asl-temp >/dev/null 2>&1 || true
            proot-distro install -n asl-temp "$IMAGE_REF" || {
                echo -e "${RED}[!] Error: proot-distro failed to download or unpack $IMAGE_REF.${RESET}"
                exit 1
            }

            TEMP_ROOTFS="$PREFIX/var/lib/proot-distro/containers/asl-temp/rootfs"
            if [ -d "$TEMP_ROOTFS" ]; then
                echo -e "${GREEN}[*] Copying Debian rootfs into chroot location ($DEBIANPATH)...${RESET}"
                ensure_chroot_unmounted_for_replace || exit 1
                if ! su -c "rm -rf '$DEBIANPATH' && mkdir -p '$DEBIANPATH' && cp -af '$TEMP_ROOTFS/.' '$DEBIANPATH/'"; then
                    echo -e "${RED}[!] Failed to copy the Debian base rootfs.${RESET}"
                    exit 1
                fi
                proot-distro remove asl-temp >/dev/null 2>&1 || true

                # Configure DNS & hosts
                su -c "chroot '$DEBIANPATH' /bin/sh -c 'echo \"nameserver 1.1.1.1\" > /etc/resolv.conf && echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf && echo \"127.0.0.1 localhost\" > /etc/hosts'" 2>/dev/null || true
                echo -e "${GREEN}[✓] Debian base rootfs provisioned successfully.${RESET}"
            else
                echo -e "${RED}[!] Error: Failed to locate extracted rootfs for $IMAGE_REF.${RESET}"
                exit 1
            fi
        fi
    fi
fi

# 5. Repository Setup
TARGET_DIR="$HOME/ASL"

if [ -d "$TARGET_DIR/.git" ]; then
    echo -e "${GREEN}[*] Updating existing ASL repository at $TARGET_DIR...${RESET}"
    cd "$TARGET_DIR"
    git pull origin master || true
else
    echo -e "${GREEN}[*] Cloning ASL repository to $TARGET_DIR...${RESET}"
    git clone https://github.com/Ruusian5/ASL.git "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

# 6. Global Binary Linking & Android AID setup
echo -e "${GREEN}[*] Registering 'asl' CLI executable...${RESET}"
chmod +x "$TARGET_DIR/bin/asl"
chmod +x "$TARGET_DIR/core/"*.sh
chmod +x "$TARGET_DIR/desktop/"*.sh
chmod +x "$TARGET_DIR/gaming/"*.sh

mkdir -p "$PREFIX/bin"
ln -sf "$TARGET_DIR/bin/asl" "$PREFIX/bin/asl"
ln -sf "$TARGET_DIR/bin/asl" "$PREFIX/bin/superkit" 2>/dev/null || echo -e "${YELLOW}[!] Could not create superkit symlink in \$PREFIX/bin${RESET}"

echo -e "${GREEN}[*] Applying Android GID mappings...${RESET}"
if ! "$TARGET_DIR/core/android-aid.sh" setup; then
    echo -e "${RED}[!] Android GID mapping failed. Installation cannot continue safely.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Provisioning auto-configured SoC GPU drivers & hardware acceleration...${RESET}"
if ! (
    source "$TARGET_DIR/core/gpu-profile.sh"
    asl_gpu_install_drivers
); then
    echo -e "${RED}[!] GPU driver provisioning failed. Installation cannot continue safely.${RESET}"
    exit 1
fi

echo -e "${CYAN}====================================================${RESET}"
echo -e "${GREEN}[✓] Android Subsystem for Linux (ASL) Installed!     ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo -e "Type ${YELLOW}asl${RESET} to open the interactive dashboard."
echo -e "Type ${YELLOW}asl start${RESET} to mount your Linux chroot environment."
echo -e "Type ${YELLOW}asl desktop start${RESET} to launch XFCE4 desktop with Termux:X11."
echo -e "Type ${YELLOW}asl setup-gaming${RESET} to install Wine and Box64; add DXVK per Wine prefix with Winetricks."
echo -e "${CYAN}====================================================${RESET}"
