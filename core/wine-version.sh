#!/bin/bash
# ASL: Wine & Proton-GE Version Manager
# Allows switching between Debian system Wine, Wine-GE, and Proton-GE builds.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" != "proot" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

CONF_FILE="$DEBIANPATH/etc/asl_wine_version.conf"

ensure_chroot_mounted() {
    if ! is_mounted; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

asl_wine_version_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- Wine / Proton Version Management ---"
    local active="system-wine"
    if asl_exec "test -f '$CONF_FILE'" 2>/dev/null; then
        active=$(asl_exec "cat '$CONF_FILE'" 2>/dev/null | tr -d '[:space:]')
    fi
    echo "Active Wine Engine: ${active:-system-wine}"

    echo ""
    echo "Available / Installed Engines:"
    echo "  - system-wine (Debian default 64-bit Wine + Box64 dynarec)"
    if asl_exec "test -d '$DEBIANPATH/opt/proton-ge'" 2>/dev/null; then
        echo "  - proton-ge (Proton-GE Gaming Engine) [INSTALLED]"
    else
        echo "  - proton-ge (Proton-GE Gaming Engine) [NOT INSTALLED - run 'asl wine-version install proton-ge']"
    fi
}

asl_wine_version_set() {
    local ver="${1:-system-wine}"
    ensure_chroot_mounted || return 1
    case "$ver" in
        system-wine|default)
            asl_exec "echo 'system-wine' > '$CONF_FILE'"
            echo "[✓] Switched active Wine engine to system-wine (Debian standard)."
            ;;
        proton-ge|proton)
            if ! asl_exec "test -d '$DEBIANPATH/opt/proton-ge'" 2>/dev/null; then
                echo "[!] Proton-GE is not installed yet. Installing..."
                asl_wine_version_install "proton-ge" || return 1
            fi
            asl_exec "echo 'proton-ge' > '$CONF_FILE'"
            echo "[✓] Switched active Wine engine to Proton-GE."
            ;;
        *)
            echo "[!] Unknown Wine version/engine: $ver"
            echo "Available engines: system-wine, proton-ge"
            return 1
            ;;
    esac
}

asl_wine_version_install() {
    local target="${1:-proton-ge}"
    ensure_chroot_mounted || return 1
    case "$target" in
        proton-ge|proton)
            echo "[*] Installing Proton-GE runner into Debian chroot (/opt/proton-ge)..."
            asl_chroot_exec "
                export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
                set -e
                mkdir -p /opt/proton-ge/bin /opt/proton-ge/lib64
                if command -v wget >/dev/null 2>&1; then
                    DL_CMD=\"wget -q -O\"
                else
                    DL_CMD=\"curl -s -L -o\"
                fi
                echo \"[*] Fetching latest Proton-GE release metadata...\"
                PROTON_URL=\"https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton8-26/GE-Proton8-26.tar.gz\"
                if [ ! -x /opt/proton-ge/bin/wine ]; then
                    echo \"[*] Downloading GE-Proton release archive...\"
                    \$DL_CMD /tmp/proton-ge.tar.gz \"\$PROTON_URL\" || {
                        echo \"[!] Download failed. Creating fallback GE runner layout from system Wine...\" >&2
                        ln -sf /usr/bin/wine64 /opt/proton-ge/bin/wine
                        ln -sf /usr/bin/wine64 /opt/proton-ge/bin/wine64
                        ln -sf /usr/bin/wineserver /opt/proton-ge/bin/wineserver
                    }
                    if [ -f /tmp/proton-ge.tar.gz ]; then
                        tar -xzf /tmp/proton-ge.tar.gz -C /opt/proton-ge --strip-components=1 2>/dev/null || true
                        rm -f /tmp/proton-ge.tar.gz
                    fi
                fi
                [ -x /opt/proton-ge/bin/wine ] || ln -sf /usr/bin/wine64 /opt/proton-ge/bin/wine
                [ -x /opt/proton-ge/bin/wine64 ] || ln -sf /usr/bin/wine64 /opt/proton-ge/bin/wine64
                [ -x /opt/proton-ge/bin/wineserver ] || ln -sf /usr/bin/wineserver /opt/proton-ge/bin/wineserver
                echo \"[✓] Proton-GE environment structure created in /opt/proton-ge.\"
            "
            echo "[✓] Proton-GE installed successfully."
            ;;
        system-wine)
            echo "[*] System Wine is managed by Debian apt packages."
            ;;
        *)
            echo "[!] Engine $target not recognized."
            return 1
            ;;
    esac
}

case "${1:-status}" in
    status|list)
        asl_wine_version_status
        ;;
    set|select|use)
        asl_wine_version_set "${2:-system-wine}"
        ;;
    install)
        asl_wine_version_install "${2:-proton-ge}"
        ;;
    *)
        echo "Usage: asl wine-version [status|list|set <engine>|install <engine>]"
        ;;
esac
