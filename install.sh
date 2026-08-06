#!/bin/bash
# AndroidLinux-SuperKit: Automated One-Line Installer
# Installs dependencies, sets up SuperKit, and registers the global 'superkit' CLI command in Termux.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${CYAN}====================================================${RESET}"
echo -e "${CYAN}   🚀 AndroidLinux-SuperKit Automated Installer      ${RESET}"
echo -e "${CYAN}====================================================${RESET}"

# 1. Environment & Platform Checks
if [ -z "$PREFIX" ] || [[ "$PREFIX" != *"/com.termux/"* ]]; then
    echo -e "${RED}[!] Error: This installation script must be run inside Termux on Android.${RESET}"
    exit 1
fi

echo -e "${GREEN}[*] Checking root access (su)...${RESET}"
if ! su -c "id -u" >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Warning: Root access via 'su' was not detected or prompt timed out.${RESET}"
    echo -e "${YELLOW}[!] SuperKit chroot operations require root access.${RESET}"
else
    echo -e "${GREEN}[✓] Root access confirmed.${RESET}"
fi

# 2. Package Installation
echo -e "${GREEN}[*] Installing required Termux packages...${RESET}"
pkg update -y || true
pkg install -y git pulseaudio termux-x11-nightly virglrenderer-android tsu socat wget unzip 2>/dev/null || \
pkg install -y git pulseaudio termux-x11 virglrenderer-android tsu socat wget unzip 2>/dev/null || true

# 3. Repository Setup
TARGET_DIR="$HOME/AndroidLinux-SuperKit"

if [ -d "$TARGET_DIR/.git" ]; then
    echo -e "${GREEN}[*] Updating existing SuperKit repository at $TARGET_DIR...${RESET}"
    cd "$TARGET_DIR"
    git pull origin master || true
else
    echo -e "${GREEN}[*] Cloning SuperKit repository to $TARGET_DIR...${RESET}"
    git clone https://github.com/Ruusian5/AndroidLinux-SuperKit.git "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

# 4. Global Binary Linking
echo -e "${GREEN}[*] Registering 'superkit' CLI executable...${RESET}"
chmod +x "$TARGET_DIR/bin/superkit"
chmod +x "$TARGET_DIR/core/"*.sh
chmod +x "$TARGET_DIR/desktop/"*.sh
chmod +x "$TARGET_DIR/gaming/"*.sh

mkdir -p "$PREFIX/bin"
ln -sf "$TARGET_DIR/bin/superkit" "$PREFIX/bin/superkit"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${GREEN}[✓] AndroidLinux-SuperKit installed successfully!${RESET}"
echo -e "${CYAN}====================================================${RESET}"
echo -e "Type ${YELLOW}superkit${RESET} to open the interactive terminal dashboard."
echo -e "Type ${YELLOW}superkit start${RESET} to mount your Linux chroot environment."
echo -e "Type ${YELLOW}superkit desktop start${RESET} to launch XFCE4 desktop with Termux:X11."
echo -e "Type ${YELLOW}superkit setup-gaming${RESET} to auto-configure Wine, Box64 & DXVK."
echo -e "${CYAN}====================================================${RESET}"
