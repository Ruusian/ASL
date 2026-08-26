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

DISTRO_TYPE="${TYPE:-auto}" # modded, standard, ubuntu, arch, alpine, fedora, kali, or auto

# Parse arguments (--modded, --standard, --ubuntu, --arch, --alpine, --fedora, --kali, --type=X, --distro=X)
while [ $# -gt 0 ]; do
    case "$1" in
        --modded)
            DISTRO_TYPE="modded"
            shift
            ;;
        --standard|--base|--debian)
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
echo -e "${CYAN} 🚀 ASL Debian Snapdragon Subsystem Installer       ${RESET}"
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

ACTIVE_MODE="root"
ASL_EXEC_MODE="root"
export ASL_EXEC_MODE
echo -e "${GREEN}[✓] Execution Mode: ROOT (su) Kernel Chroot (Full Hardware Acceleration)${RESET}"
echo "root" > "$PREFIX/etc/asl_exec_mode"

# 2. Package Installation
echo -e "${GREEN}[*] Installing required Termux packages...${RESET}"
export DEBIAN_FRONTEND=noninteractive
pkg install -y x11-repo 2>/dev/null || { echo -e "${RED}[!] Failed to install the Termux X11 repository.${RESET}"; exit 1; }
pkg update -y 2>/dev/null || { echo -e "${RED}[!] Failed to update Termux packages.${RESET}"; exit 1; }
if ! pkg install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" git pulseaudio termux-x11-nightly virglrenderer-android tsu socat wget unzip xz-utils proot-distro 2>/dev/null && \
   ! pkg install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" git pulseaudio termux-x11 virglrenderer-android tsu socat wget unzip xz-utils proot-distro 2>/dev/null; then
    echo -e "${RED}[!] Failed to install required Termux packages.${RESET}"
    exit 1
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
    echo -e "  1) ${GREEN}Debian Modded Rootfs${RESET} (Pre-configured Turnip Mesa Vulkan & XFCE Desktop)"
    echo -e "  2) ${CYAN}Debian Clean Base${RESET} (Official Debian Trixie via proot-distro)"
    echo -e "  3) ${CYAN}Ubuntu LTS Base${RESET} (Official Ubuntu 24.04 via proot-distro)"
    echo -e "  4) ${CYAN}Arch Linux Base${RESET} (Official Arch via proot-distro)"
    echo -e "  5) ${CYAN}Alpine Linux Base${RESET} (Official Alpine via proot-distro)"
    echo -e "  6) ${CYAN}Kali Linux Base${RESET} (Official Kali via proot-distro)"
    echo -e "  7) ${CYAN}Fedora Linux Base${RESET} (Official Fedora via proot-distro)"
    echo -e "  8) ${YELLOW}Skip rootfs setup${RESET} (Use existing rootfs at /data/local/tmp/chrootDebian)"
    echo -e ""
    distro_choice=""
    if [ -c /dev/tty ]; then
        read -r -p "Select choice [1-8, default: 1]: " distro_choice < /dev/tty 2>/dev/null || true
    else
        read -r -p "Select choice [1-8, default: 1]: " distro_choice || true
    fi
    case "$distro_choice" in
        1|"") DISTRO_TYPE="modded" ;;
        2) DISTRO_TYPE="debian" ;;
        3) DISTRO_TYPE="ubuntu" ;;
        4) DISTRO_TYPE="arch" ;;
        5) DISTRO_TYPE="alpine" ;;
        6) DISTRO_TYPE="kali" ;;
        7) DISTRO_TYPE="fedora" ;;
        8) DISTRO_TYPE="skip" ;;
        *) DISTRO_TYPE="modded" ;;
    esac
fi

[ "$DISTRO_TYPE" = "auto" ] && DISTRO_TYPE="modded"

IS_MODDED=false
IMAGE_REF=""

case "$DISTRO_TYPE" in
    modded)
        IS_MODDED=true
        IMAGE_REF="debian:trixie"
        ;;
    debian|standard)
        IMAGE_REF="debian:trixie"
        ;;
    ubuntu)
        IMAGE_REF="ubuntu"
        ;;
    arch|archlinux)
        IMAGE_REF="archlinux"
        ;;
    alpine)
        IMAGE_REF="alpine"
        ;;
    fedora)
        IMAGE_REF="fedora"
        ;;
    kali)
        IMAGE_REF="kali"
        ;;
    skip)
        IMAGE_REF=""
        ;;
    *)
        IMAGE_REF="$DISTRO_TYPE"
        ;;
esac

cleanup_installer() {
    proot-distro remove asl-temp >/dev/null 2>&1 || true
    rm -f "$PREFIX/tmp/asl-modded-temp.tar.xz" >/dev/null 2>&1 || true
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
if [ "$DISTRO_TYPE" != "skip" ]; then
    echo -e "${GREEN}[*] Provisioning Debian Snapdragon rootfs (Edition: ${DISTRO_TYPE})...${RESET}"
    if [ -d "$DEBIANPATH/etc" ] || asl_exec "test -d '$DEBIANPATH/etc'" 2>/dev/null; then
        echo -e "${YELLOW}[!] Existing chroot detected at $DEBIANPATH.${RESET}"
        overwrite_confirm=""
        if [ -c /dev/tty ]; then
            read -r -p "Overwrite existing chroot with fresh Debian rootfs? [y/N]: " overwrite_confirm < /dev/tty 2>/dev/null || true
        elif [ -t 0 ]; then
            read -r -p "Overwrite existing chroot with fresh Debian rootfs? [y/N]: " overwrite_confirm || true
        fi
        if [[ ! "$overwrite_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}[*] Keeping existing chroot environment.${RESET}"
            DISTRO_TYPE="skip"
        fi
    fi

    if [ "$DISTRO_TYPE" != "skip" ]; then
        if [ "$IS_MODDED" = "true" ]; then
            echo -e "${GREEN}[*] Fetching release metadata & checksums...${RESET}"
            SHA256SUMS_URL="https://github.com/Ruusian/ASL/releases/latest/download/SHA256SUMS"
            TEMP_SUMS="$PREFIX/tmp/asl-modded-SHA256SUMS"
            TEMP_TAR="$PREFIX/tmp/asl-modded-temp.tar.xz"
            rm -f "$TEMP_TAR" "$TEMP_SUMS" "$PREFIX/tmp"/asl-debian-modded-arm64.tar.xz.part* 2>/dev/null || true

            if ! (curl -fsSL --connect-timeout 15 --max-time 60 --retry 2 -o "$TEMP_SUMS" "$SHA256SUMS_URL" || wget -q --timeout=15 --tries=2 -O "$TEMP_SUMS" "$SHA256SUMS_URL") || [ ! -s "$TEMP_SUMS" ]; then
                echo -e "${YELLOW}[!] Could not download SHA256SUMS (HTTP rate limit or release asset unavailable). Falling back to Debian base...${RESET}"
                rm -f "$TEMP_TAR" "$TEMP_SUMS"
                IS_MODDED=false
            else
                PART_FILES=$(awk '{ if ($NF ~ /^asl-debian-modded-arm64\.tar\.xz\.part/) print $NF }' "$TEMP_SUMS" | sort -u)
                if [ -n "$PART_FILES" ]; then
                    echo -e "${GREEN}[*] Multi-part release detected. Downloading rootfs parts...${RESET}"
                    DL_OK=true
                    for pfile in $PART_FILES; do
                        echo -e "${CYAN}    Downloading $pfile...${RESET}"
                        P_URL="https://github.com/Ruusian/ASL/releases/latest/download/$pfile"
                        P_DST="$PREFIX/tmp/$pfile"
                        if ! (curl -fsSL --connect-timeout 15 --max-time 1800 --retry 3 -o "$P_DST" "$P_URL" || wget -q --timeout=30 --tries=3 -O "$P_DST" "$P_URL") || [ ! -s "$P_DST" ]; then
                            echo -e "${YELLOW}[!] Failed to download $pfile.${RESET}"
                            DL_OK=false
                            break
                        fi
                        EXP_PSUM=$(awk -v f="$pfile" '$NF == f { sub(/^\*/, "", $1); print $1 }' "$TEMP_SUMS" | head -n 1)
                        ACT_PSUM=$(sha256sum "$P_DST" | awk '{ print $1 }')
                        if [ -n "$EXP_PSUM" ] && [ "$EXP_PSUM" != "$ACT_PSUM" ]; then
                            echo -e "${YELLOW}[!] Checksum verification failed for $pfile.${RESET}"
                            DL_OK=false
                            break
                        fi
                    done
                    if [ "$DL_OK" = "true" ]; then
                        echo -e "${GREEN}[*] Reassembling rootfs archive from parts...${RESET}"
                        cat "$PREFIX/tmp"/asl-debian-modded-arm64.tar.xz.part* > "$TEMP_TAR"
                        rm -f "$PREFIX/tmp"/asl-debian-modded-arm64.tar.xz.part*
                    else
                        rm -f "$PREFIX/tmp"/asl-debian-modded-arm64.tar.xz.part* "$TEMP_TAR"
                        IS_MODDED=false
                    fi
                else
                    RELEASE_URL="https://github.com/Ruusian/ASL/releases/latest/download/asl-debian-modded-arm64.tar.xz"
                    echo -e "${GREEN}[*] Downloading ASL Exclusive Debian Modded Rootfs archive...${RESET}"
                    echo -e "${CYAN}    URL: $RELEASE_URL${RESET}"
                    if ! (curl -fsSL --connect-timeout 15 --max-time 1800 --retry 3 -o "$TEMP_TAR" "$RELEASE_URL" || wget -q --timeout=30 --tries=3 -O "$TEMP_TAR" "$RELEASE_URL") || [ ! -s "$TEMP_TAR" ]; then
                        echo -e "${YELLOW}[!] Modded release asset download failed. Falling back to Debian base...${RESET}"
                        rm -f "$TEMP_TAR"
                        IS_MODDED=false
                    fi
                fi

                if [ "$IS_MODDED" = "true" ]; then
                    EXPECTED=$(awk '{ h=$1; sub(/^\*/, "", h); if ($NF == "asl-debian-modded-arm64.tar.xz" && h ~ /^[[:xdigit:]]{64}$/) print h }' "$TEMP_SUMS" | head -n 1)
                    rm -f "$TEMP_SUMS"
                    if [ -n "$EXPECTED" ]; then
                        echo -e "${GREEN}[*] Verifying reassembled archive checksum...${RESET}"
                        ACTUAL=$(sha256sum "$TEMP_TAR" | awk '{ print $1 }')
                        if [ "$ACTUAL" != "$EXPECTED" ]; then
                            echo -e "${YELLOW}[!] Checksum verification failed for modded rootfs. Falling back to Debian base...${RESET}"
                            rm -f "$TEMP_TAR"
                            IS_MODDED=false
                        else
                            echo -e "${GREEN}[✓] Checksum verified (SHA-256: ${EXPECTED:0:16}...)${RESET}"
                        fi
                    fi
                fi

                if [ "$IS_MODDED" = "true" ]; then
                    echo -e "${GREEN}[*] Extracting prebuilt modded Debian rootfs into $DEBIANPATH...${RESET}"
                    ensure_chroot_unmounted_for_replace || exit 1
                    if ! asl_exec "rm -rf '$DEBIANPATH' && mkdir -p '$DEBIANPATH' && tar --numeric-owner -xf '$TEMP_TAR' -C '$DEBIANPATH'"; then
                        echo -e "${YELLOW}[!] Failed to extract modded rootfs. Falling back to Debian base...${RESET}"
                        rm -f "$TEMP_TAR"
                        IS_MODDED=false
                    else
                        rm -f "$TEMP_TAR"
                        # Configure DNS & hosts & APT performance
                        asl_chroot_exec 'mkdir -p /etc && echo "nameserver 1.1.1.1" > /etc/resolv.conf && echo "nameserver 8.8.8.8" >> /etc/resolv.conf && echo "127.0.0.1 localhost" > /etc/hosts && mkdir -p /etc/apt/apt.conf.d && echo "Acquire::GzipIndexes \"true\";" > /etc/apt/apt.conf.d/99gzip' 2>/dev/null || true
                        asl_chroot_exec 'if [ ! -f /etc/shadow ]; then touch /etc/shadow && chown root:shadow /etc/shadow && chmod 640 /etc/shadow; fi' 2>/dev/null || true
                        echo -e "${GREEN}[✓] ASL Exclusive Debian Modded Rootfs provisioned successfully!${RESET}"
                    fi
                fi
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
                if ! asl_exec "rm -rf '$DEBIANPATH' && mkdir -p '$DEBIANPATH' && cp -af '$TEMP_ROOTFS/.' '$DEBIANPATH/'"; then
                    echo -e "${RED}[!] Failed to copy the Debian base rootfs.${RESET}"
                    exit 1
                fi
                proot-distro remove asl-temp >/dev/null 2>&1 || true

                # Configure DNS & hosts & APT performance
                asl_chroot_exec 'mkdir -p /etc && echo "nameserver 1.1.1.1" > /etc/resolv.conf && echo "nameserver 8.8.8.8" >> /etc/resolv.conf && echo "127.0.0.1 localhost" > /etc/hosts && mkdir -p /etc/apt/apt.conf.d && echo "Acquire::GzipIndexes \"true\";" > /etc/apt/apt.conf.d/99gzip' 2>/dev/null || true
                echo -e "${GREEN}[✓] Debian base rootfs provisioned successfully.${RESET}"
            else
                echo -e "${RED}[!] Error: Failed to locate extracted rootfs for $IMAGE_REF.${RESET}"
                exit 1
            fi
        fi
    fi
fi

# 5. Global Binary Linking & Android AID setup
echo -e "${GREEN}[*] Installing ASL system runtime to ${PREFIX:-/data/data/com.termux/files/usr}/share/asl...${RESET}"
INSTALL_DIR="${PREFIX:-/data/data/com.termux/files/usr}/share/asl"
mkdir -p "$INSTALL_DIR"
for d in bin core desktop gaming tools; do
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
if ! "$INSTALL_DIR/core/android-aid.sh" setup; then
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

echo -e "${GREEN}[*] Provisioning OpenClaude AI agent environment...${RESET}"
if [ -f "$INSTALL_DIR/core/openclaude-setup.sh" ]; then
    bash "$INSTALL_DIR/core/openclaude-setup.sh" || true
fi

echo -e "${CYAN}====================================================${RESET}"
echo -e "${GREEN}[✓] Android Subsystem for Linux (ASL) Installed!     ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo -e "Type ${YELLOW}asl${RESET} to open the interactive dashboard."
echo -e "Type ${YELLOW}asl start${RESET} to mount your Linux chroot environment."
echo -e "Type ${YELLOW}asl desktop start${RESET} to launch XFCE4 desktop with Termux:X11."
echo -e "Type ${YELLOW}asl hub${RESET} to launch the ASL Hub Control Center."
echo -e "${CYAN}====================================================${RESET}"
