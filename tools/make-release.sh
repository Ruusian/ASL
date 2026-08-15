#!/bin/bash
# Android Subsystem for Linux (ASL) Modded Rootfs Release Builder
# Packages the current active chroot at /data/local/tmp/chrootDebian into a prebuilt modded release tarball
# and uploads it to GitHub Releases via GitHub CLI (gh).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

DEBIANPATH="/data/local/tmp/chrootDebian"
RELEASE_TAG="${1:-2.5.1}"
DISTRO_NAME="${2:-debian}"
OUTPUT_TAR="/data/local/tmp/asl-${DISTRO_NAME}-modded-arm64.tar.xz"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN} 📦 ASL Modded Rootfs GitHub Release Builder        ${RESET}"
echo -e "${CYAN}====================================================${RESET}"

if [ ! -d "$DEBIANPATH" ]; then
    echo -e "${RED}[!] Error: No rootfs found at $DEBIANPATH.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Ensuring chroot is unmounted before archiving...${RESET}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$SCRIPT_DIR/core/stop-chroot.sh" >/dev/null 2>&1 || true

echo -e "${GREEN}[*] Packaging modded rootfs into $OUTPUT_TAR...${RESET}"
# Secrets & machine identity are excluded so a published release tarball never
# ships live SSH host keys, VNC/API credentials, the shadow database, or a
# ready-to-use root password. install.sh regenerates an empty /etc/shadow
# post-extraction (root stays locked until the user runs `asl exec passwd`).
su -c "PATH=\"$PREFIX/bin:\$PATH\" tar \
    --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' --exclude='./sdcard/*' --exclude='./tmp/*' \
    --exclude='./root/.asl-*' --exclude='./etc/ssh/ssh_host_*' --exclude='./root/.bash_history' \
    --exclude='./var/cache/apt/*' --exclude='./etc/shadow' --exclude='./etc/shadow-' \
    --exclude='./root/.wine-x64' --exclude='./root/.local' --exclude='./root/.cache' \
    -cJf '$OUTPUT_TAR' -C '$DEBIANPATH' ."

echo -e "${GREEN}[✓] Archive created: $OUTPUT_TAR ($(du -h "$OUTPUT_TAR" | cut -f1))${RESET}"

echo -e "${GREEN}[*] Generating SHA256SUMS checksum sidecar...${RESET}"
ARCHIVE_NAME="$(basename "$OUTPUT_TAR")"
ARCHIVE_SUM="$(sha256sum "$OUTPUT_TAR" | awk '{print $1}')"
su -c "printf '%s  %s\n' '$ARCHIVE_SUM' '$ARCHIVE_NAME' > '$(dirname "$OUTPUT_TAR")/SHA256SUMS' && chmod 644 '$(dirname "$OUTPUT_TAR")/SHA256SUMS'" 2>/dev/null || \
    printf '%s  %s\n' "$ARCHIVE_SUM" "$ARCHIVE_NAME" > "$(dirname "$OUTPUT_TAR")/SHA256SUMS" || true
echo -e "${GREEN}[✓] SHA256SUMS generated ($ARCHIVE_SUM)${RESET}"

if command -v gh >/dev/null 2>&1; then
    echo -e "${GREEN}[*] Creating GitHub Release $RELEASE_TAG and uploading modded asset...${RESET}"
    RELEASE_SUMS="$(dirname "$OUTPUT_TAR")/SHA256SUMS"
    gh release create "$RELEASE_TAG" "$OUTPUT_TAR" "$RELEASE_SUMS" --title "ASL Modded Subsystem Release $RELEASE_TAG" --notes "Prebuilt modded ASL rootfs with Turnip Mesa Vulkan, Box64, Wine64, and XFCE desktop pre-configured." --repo Ruusian5/AndroidLinux-SuperKit 2>/dev/null || \
    gh release upload "$RELEASE_TAG" "$OUTPUT_TAR" "$RELEASE_SUMS" --clobber --repo Ruusian5/AndroidLinux-SuperKit
    echo -e "${GREEN}[✓] GitHub release asset uploaded successfully!${RESET}"
else
    echo -e "${YELLOW}[!] GitHub CLI (gh) not found. To upload manually, run:${RESET}"
    echo -e "    gh release create $RELEASE_TAG $OUTPUT_TAR $(dirname "$OUTPUT_TAR")/SHA256SUMS"
fi
