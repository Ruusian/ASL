#!/bin/bash
# Android Subsystem for Linux (ASL) Modded Rootfs Release Builder & Publisher
# Packages the current active chroot using make-release.sh and publishes artifacts to GitHub Releases.

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

RELEASE_TAG="${1:-2.5.1}"
OUTPUT_DIR="/data/local/tmp"
OUTPUT_TAR="$OUTPUT_DIR/asl-debian-modded-arm64.tar.xz"
SUMS_FILE="$OUTPUT_DIR/SHA256SUMS"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN} 📦 ASL Modded Rootfs GitHub Release Builder & Publisher ${RESET}"
echo -e "${CYAN}====================================================${RESET}"

# 1. Build and sanitize rootfs using canonical make-release.sh
MAKE_RELEASE_SCRIPT="$SCRIPT_DIR/tools/make-release.sh"
if [ ! -f "$MAKE_RELEASE_SCRIPT" ]; then
    echo -e "${RED}[!] Error: Release builder $MAKE_RELEASE_SCRIPT not found.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Invoking canonical release builder (tools/make-release.sh)...${RESET}"
bash "$MAKE_RELEASE_SCRIPT" "$RELEASE_TAG"

# 2. Collect generated assets
ASSETS=()
if [ -f "$OUTPUT_TAR" ]; then
    ASSETS+=("$OUTPUT_TAR")
fi
# Add multi-part chunks if split
for part in "$OUTPUT_DIR"/asl-debian-modded-arm64.tar.xz.part*; do
    if [ -f "$part" ]; then
        ASSETS+=("$part")
    fi
done
if [ -f "$SUMS_FILE" ]; then
    ASSETS+=("$SUMS_FILE")
fi

if [ ${#ASSETS[@]} -eq 0 ]; then
    echo -e "${RED}[!] Error: No release assets found in $OUTPUT_DIR.${RESET}"
    exit 1
fi

# 3. Publish to GitHub Releases
if command -v gh >/dev/null 2>&1; then
    echo -e "${GREEN}[*] Creating GitHub Release $RELEASE_TAG and uploading assets via gh CLI...${RESET}"
    gh release create "$RELEASE_TAG" "${ASSETS[@]}" \
        --title "ASL Modded Subsystem Release $RELEASE_TAG" \
        --notes "Prebuilt modded ASL rootfs with Turnip Mesa Vulkan and XFCE desktop pre-configured." \
        --repo Ruusian/ASL 2>/dev/null || \
    gh release upload "$RELEASE_TAG" "${ASSETS[@]}" --clobber --repo Ruusian/ASL
    echo -e "${GREEN}[✓] GitHub release assets uploaded successfully!${RESET}"
elif [ -f "$SCRIPT_DIR/tools/release-helper.py" ]; then
    echo -e "${GREEN}[*] Uploading assets to GitHub Releases via release-helper API...${RESET}"
    for asset in "${ASSETS[@]}"; do
        su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; python3 '$SCRIPT_DIR/tools/release-helper.py' upload '$RELEASE_TAG' '$asset'"
    done
    echo -e "${GREEN}[✓] GitHub release assets uploaded successfully!${RESET}"
else
    echo -e "${YELLOW}[!] Release uploader not available. To upload manually, run:${RESET}"
    for asset in "${ASSETS[@]}"; do
        echo -e "    python3 tools/release-helper.py upload $RELEASE_TAG $asset"
    done
fi
