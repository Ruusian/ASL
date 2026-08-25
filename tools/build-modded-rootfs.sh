#!/bin/bash
# ASL Modded Debian ARM64 Rootfs Release Builder & Sanitizer
# Builds a clean, production-ready modded Debian rootfs tarball from the active installation.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
RELEASE_TAG="${1:-v2.5.1}"
OUTPUT_DIR="/data/local/tmp"
OUTPUT_TAR="$OUTPUT_DIR/asl-debian-modded-arm64.tar.xz"
SUMS_FILE="$OUTPUT_DIR/SHA256SUMS"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN} 📦 ASL Debian Modded RootFS Builder ($RELEASE_TAG)   ${RESET}"
echo -e "${CYAN}====================================================${RESET}"

if [ ! -d "$DEBIANPATH" ]; then
    echo -e "${RED}[!] Error: No rootfs found at $DEBIANPATH.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Ensuring chroot is completely unmounted...${RESET}"
if [ -f "$SCRIPT_DIR/core/stop-chroot.sh" ]; then
    bash "$SCRIPT_DIR/core/stop-chroot.sh" >/dev/null 2>&1 || true
fi

# Double-check mount status
if grep -qs "$DEBIANPATH" /proc/mounts; then
    echo -e "${RED}[!] Active mounts detected under $DEBIANPATH. Refusing to archive.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Preparing temporary exclude list...${RESET}"
EXCLUDE_FILE="${PREFIX:-/data/data/com.termux/files/usr}/tmp/asl_rootfs_excludes.txt"
cat << 'EOF' > "$EXCLUDE_FILE"
# Virtual & Android host mounts
./proc/*
./sys/*
./dev/*
./sdcard/*
./storage/*
./tmp/*
./data/*
./apex/*
./system/*
./vendor/*
./termux
./termux-home

# Stray rootfs root dotfiles & user dirs
./.ICEauthority
./.bash_history
./.bun
./.cache
./.claude
./.claude-mem
./.claude.json
./.config
./.dbus
./.gnupg
./.gvfs
./.local
./.mozilla
./.npm
./.wget-hsts
./.wine
./Desktop
./Documents
./Downloads
./Music
./Pictures
./Public
./Templates
./Videos

# Sensitive tokens, keys & personal auth files
./root/.openclaude.json
./root/.openclaude
./root/.openclaude/*
./root/.claude.json
./root/.claude
./root/.claude/*
./root/.claude-mem
./root/.claude-mem/*
./root/.qwen
./root/.qwen/*
./root/.hermes
./root/.hermes/*
./root/.omniroute
./root/.omniroute/*
./root/.copilot
./root/.copilot/*
./root/.craft-agent
./root/.craft-agent/*
./root/.dsh
./root/.dsh/*
./root/.prime
./root/.prime/*
./root/.kilo
./root/.kilo/*
./root/.config/gh
./root/.config/gh/*
./root/.config/Code
./root/.config/Code/*
./root/.config/chromium
./root/.config/chromium/*
./root/.config/zen
./root/.config/zen/*
./root/.config/falkon
./root/.config/falkon/*
./root/.config/kilo
./root/.config/kilo/*
./root/.config/opencode
./root/.config/opencode/*
./root/.config/obsidian
./root/.config/obsidian/*
./root/.git-credentials
./root/.gitconfig
./root/.ssh
./root/.ssh/*
./home/*/.ssh
./home/*/.ssh/*
./root/.gnupg
./root/.gnupg/*
./root/.netrc
./root/.aws
./root/.aws/*
./root/.pki
./root/.pki/*
./root/.bash_history
./root/.ICEauthority
./root/.Xauthority
./root/.pulse-cookie
./root/.asl-*
./root/.android
./root/.android/*
./etc/shadow
./etc/shadow-
./etc/gshadow
./etc/gshadow-
./etc/ssh/ssh_host_*

# Large personal games, backups, and temporary test artifacts
./root/Obsidian
./opt/ninesols
./opt/proton-wine.android-bionic-backup
./opt/proton-wine.android-bionic-backup/*
./root/CamCap.java
./root/capture_cam.sh
./root/test_hardware.sh
./root/phone_screen.png
./root/phone_screen_fixed.png
./root/bisect_sys_out.txt
./root/narrow_out.txt
./root/threshold_out.txt
./root/Downloads/*
./root/tmp/*

# Build, package, and runtime caches
./root/.cache
./root/.cache/*
./root/.npm
./root/.npm/*
./root/.local/state
./root/.local/state/*
./root/.mozilla
./root/.mozilla/*
./root/.ipython
./root/.ipython/*
./var/cache/apt/*
./var/lib/apt/lists/*
./var/log/*
./var/tmp/*
EOF

echo -e "${GREEN}[*] Archiving and compressing modded Debian rootfs with multi-threaded XZ (xz -T0)...${RESET}"
rm -f "$OUTPUT_TAR"

su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; \
    tar --exclude-from='$EXCLUDE_FILE' --numeric-owner -I 'xz -T0 -3' -cf '$OUTPUT_TAR' -C '$DEBIANPATH' ."

rm -f "$EXCLUDE_FILE"

if [ ! -f "$OUTPUT_TAR" ]; then
    echo -e "${RED}[!] Error: Failed to generate $OUTPUT_TAR.${RESET}"
    exit 1
fi

TAR_SIZE="$(du -h "$OUTPUT_TAR" 2>/dev/null | cut -f1)"
echo -e "${GREEN}[✓] Rootfs archive created successfully: $OUTPUT_TAR ($TAR_SIZE)${RESET}"

echo -e "${GREEN}[*] Computing SHA256 checksum...${RESET}"
ARCHIVE_NAME="$(basename "$OUTPUT_TAR")"
ARCHIVE_SUM="$(sha256sum "$OUTPUT_TAR" | awk '{print $1}')"
su -c "printf '%s  %s\n' '$ARCHIVE_SUM' '$ARCHIVE_NAME' > '$SUMS_FILE' && chmod 644 '$SUMS_FILE'"
echo -e "${GREEN}[✓] SHA256: $ARCHIVE_SUM${RESET}"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${GREEN}[✓] ASL Modded Rootfs Packaging Complete!            ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
