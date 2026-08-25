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
proc/*
./proc/*
sys/*
./sys/*
dev/*
./dev/*
sdcard/*
./sdcard/*
storage/*
./storage/*
tmp/*
./tmp/*
data/*
./data/*
apex/*
./apex/*
system/*
./system/*
vendor/*
./vendor/*
termux/*
./termux/*
termux-home/*
./termux-home/*

# Stray rootfs dotfiles, personal directories & caches
*.ICEauthority
*.bash_history
*.bun*
*.cache*
*.claude*
*.config*
*.dbus*
*.gnupg*
*.gvfs*
*.local*
*.mozilla*
*.npm*
*.wget-hsts
*.wine*
Desktop*
./Desktop*
Documents*
./Documents*
Downloads*
./Downloads*
Music*
./Music*
Pictures*
./Pictures*
Public*
./Public*
Templates*
./Templates*
Videos*
./Videos*

# Sensitive tokens, keys & personal auth files
root/.*
./root/.*
root/*
./root/*
root/.openclaude*
root/.claude*
root/.claude-mem*
root/.qwen*
root/.hermes*
root/.omniroute*
root/.copilot*
root/.craft-agent*
root/.dsh*
root/.prime*
root/.kilo*
root/.cua-driver*
root/.config*
root/.local*
root/.cache*
root/.npm*
root/.wine*
root/.ssh*
root/.gnupg*
root/.git-credentials
root/.gitconfig
root/ASL*
root/scripts*
root/Obsidian*
root/CamCap*
root/capture_cam*
root/test_hardware*
root/phone_screen*
root/bisect_sys_out*
root/narrow_out*
root/threshold_out*
root/tmp*
root/Downloads*

# User home directories and SSH keys
home/*/.ssh*
./home/*/.ssh*
etc/shadow
./etc/shadow
etc/shadow-
./etc/shadow-
etc/gshadow
./etc/gshadow
etc/gshadow-
./etc/gshadow-
etc/ssh/ssh_host_*
./etc/ssh/ssh_host_*

# Large personal games, backups, and temporary test artifacts
opt/obsidian*
./opt/obsidian*
opt/ninesols*
./opt/ninesols*
opt/proton-wine.android-bionic-backup*
./opt/proton-wine.android-bionic-backup*
usr/local/lib/hermes-agent*
./usr/local/lib/hermes-agent*

# Build, package, and runtime caches
var/cache/apt/*
./var/cache/apt/*
var/lib/apt/lists/*
./var/lib/apt/lists/*
var/log/*
./var/log/*
var/tmp/*
./var/tmp/*
EOF

echo -e "${GREEN}[*] Archiving and compressing modded Debian rootfs (xz -T2 -3, thermally throttled & memory-capped)...${RESET}"
su -c "rm -f '$OUTPUT_TAR'"

su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; \
    tar --exclude-from='$EXCLUDE_FILE' --numeric-owner -I 'nice -n 19 xz -T2 -3 --memlimit-compress=400MiB' -cf '$OUTPUT_TAR' -C '$DEBIANPATH' ."

rm -f "$EXCLUDE_FILE"

if [ ! -f "$OUTPUT_TAR" ]; then
    echo -e "${RED}[!] Error: Failed to generate $OUTPUT_TAR.${RESET}"
    exit 1
fi

TAR_SIZE="$(du -h "$OUTPUT_TAR" 2>/dev/null | cut -f1)"
echo -e "${GREEN}[✓] Rootfs archive created successfully: $OUTPUT_TAR ($TAR_SIZE)${RESET}"

echo -e "${GREEN}[*] Verifying archive integrity...${RESET}"
if ! su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; xz -t '$OUTPUT_TAR'"; then
    echo -e "${RED}[!] Error: Archive integrity check failed.${RESET}"
    exit 1
fi
echo -e "${GREEN}[✓] Archive integrity verified successfully!${RESET}"

echo -e "${GREEN}[*] Computing SHA256 checksum...${RESET}"
ARCHIVE_NAME="$(basename "$OUTPUT_TAR")"
ARCHIVE_SUM="$(sha256sum "$OUTPUT_TAR" | awk '{print $1}')"
su -c "printf '%s  %s\n' '$ARCHIVE_SUM' '$ARCHIVE_NAME' > '$SUMS_FILE'"
echo -e "${GREEN}[✓] SHA256 ($ARCHIVE_NAME): $ARCHIVE_SUM${RESET}"

# Check if archive exceeds GitHub Release 2 GiB per-asset limit (2,147,483,648 bytes)
TAR_BYTES="$(stat -c '%s' "$OUTPUT_TAR" 2>/dev/null || wc -c < "$OUTPUT_TAR")"
if [ "$TAR_BYTES" -ge 2097152000 ]; then
    echo -e "${YELLOW}[!] Archive ($TAR_BYTES bytes) exceeds 2.0 GiB per-asset limit. Generating multi-part chunks...${RESET}"
    su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; cd '$OUTPUT_DIR' && rm -f '${ARCHIVE_NAME}.part'* && split -b 1500M -d -a 2 '$ARCHIVE_NAME' '${ARCHIVE_NAME}.part' && sha256sum '${ARCHIVE_NAME}.part'* >> '$SUMS_FILE' && chmod 644 '${ARCHIVE_NAME}.part'* '$SUMS_FILE'"
    echo -e "${GREEN}[✓] Multi-part split complete and appended to SHA256SUMS.${RESET}"
else
    su -c "chmod 644 '$SUMS_FILE'"
fi

# Restore Termux environment permissions & SELinux contexts
su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; \
    restorecon -RF /data/data/com.termux/files/usr/share/asl /data/data/com.termux/files/usr/bin/asl /data/data/com.termux/files/home/ASL 2>/dev/null || \
    chcon -R u:object_r:app_data_file:s0:c54,c258,c512,c768 /data/data/com.termux/files/usr/share/asl /data/data/com.termux/files/usr/bin/asl /data/data/com.termux/files/home/ASL 2>/dev/null || true; \
    chown -R 10566:10566 /data/data/com.termux/files/usr/share/asl /data/data/com.termux/files/usr/bin/asl /data/data/com.termux/files/home/ASL 2>/dev/null || true; \
    chmod -R u+rwX,go+rX /data/data/com.termux/files/usr/share/asl 2>/dev/null || true"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${GREEN}[✓] ASL Modded Rootfs Packaging Complete!            ${RESET}"
echo -e "${CYAN}====================================================${RESET}"
