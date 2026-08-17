#!/bin/bash
# ASL: Wine Mono & Gecko Offline Bundle Installer
# Downloads and packages offline MSI installers for Wine Mono (.NET Framework) and Wine Gecko (MSHTML engine).

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" != "proot" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

WINE_MONO_VERSION="9.4.0"
WINE_MONO_MSI="wine-mono-${WINE_MONO_VERSION}-x86.msi"
WINE_MONO_SHA256="48c48a7eb443a6d713bd73f8fb25875225c567ed3a2d596eeecbe33112349079"
WINE_MONO_URL="https://dl.winehq.org/wine/wine-mono/${WINE_MONO_VERSION}/${WINE_MONO_MSI}"

WINE_GECKO_VERSION="2.47.4"
WINE_GECKO_MSI="wine-gecko-${WINE_GECKO_VERSION}-x86_64.msi"
WINE_GECKO_SHA256="20b8b29c916298eb9f30b91d24c03473950fef99a80e0717208dcf6236b28800"
WINE_GECKO_URL="https://dl.winehq.org/wine/wine-gecko/${WINE_GECKO_VERSION}/${WINE_GECKO_MSI}"

ensure_chroot_mounted() {
    if ! is_mounted; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

asl_wine_bundle_install() {
    echo "[*] Installing Wine Mono ($WINE_MONO_VERSION) & Gecko ($WINE_GECKO_VERSION) offline bundles..."
    ensure_chroot_mounted || return 1

    asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        set -e
        mkdir -p /usr/share/wine/mono /usr/share/wine/gecko

        if command -v wget >/dev/null 2>&1; then
            DL_CMD=\"wget -q -O\"
        elif command -v curl >/dev/null 2>&1; then
            DL_CMD=\"curl -s -L -o\"
        else
            apt-get update && apt-get install -y wget curl
            DL_CMD=\"wget -q -O\"
        fi

        echo \"[*] Checking Wine Mono MSI...\"
        if [ ! -f \"/usr/share/wine/mono/$WINE_MONO_MSI\" ]; then
            echo \"[*] Downloading $WINE_MONO_MSI...\"
            \$DL_CMD \"/usr/share/wine/mono/$WINE_MONO_MSI.tmp\" \"$WINE_MONO_URL\" || {
                echo \"[!] Failed to download Wine Mono MSI. Ensure network connection.\" >&2
                rm -f \"/usr/share/wine/mono/$WINE_MONO_MSI.tmp\"
                exit 1
            }
            if command -v sha256sum >/dev/null 2>&1; then
                calc_hash=\$(sha256sum \"/usr/share/wine/mono/$WINE_MONO_MSI.tmp\" | cut -d' ' -f1)
                if [ -n \"$WINE_MONO_SHA256\" ] && [ \"\$calc_hash\" != \"$WINE_MONO_SHA256\" ]; then
                    echo \"[!] Wine Mono MSI SHA-256 verification failed (expected $WINE_MONO_SHA256, got \$calc_hash).\" >&2
                    rm -f \"/usr/share/wine/mono/$WINE_MONO_MSI.tmp\"
                    exit 1
                fi
            fi
            mv -f \"/usr/share/wine/mono/$WINE_MONO_MSI.tmp\" \"/usr/share/wine/mono/$WINE_MONO_MSI\"
        else
            echo \"[✓] Wine Mono MSI already present.\"
        fi

        echo \"[*] Checking Wine Gecko MSI...\"
        if [ ! -f \"/usr/share/wine/gecko/$WINE_GECKO_MSI\" ]; then
            echo \"[*] Downloading $WINE_GECKO_MSI...\"
            \$DL_CMD \"/usr/share/wine/gecko/$WINE_GECKO_MSI.tmp\" \"$WINE_GECKO_URL\" || {
                echo \"[!] Failed to download Wine Gecko MSI. Ensure network connection.\" >&2
                rm -f \"/usr/share/wine/gecko/$WINE_GECKO_MSI.tmp\"
                exit 1
            }
            if command -v sha256sum >/dev/null 2>&1; then
                calc_hash=\$(sha256sum \"/usr/share/wine/gecko/$WINE_GECKO_MSI.tmp\" | cut -d' ' -f1)
                if [ -n \"$WINE_GECKO_SHA256\" ] && [ \"\$calc_hash\" != \"$WINE_GECKO_SHA256\" ]; then
                    echo \"[!] Wine Gecko MSI SHA-256 verification failed (expected $WINE_GECKO_SHA256, got \$calc_hash).\" >&2
                    rm -f \"/usr/share/wine/gecko/$WINE_GECKO_MSI.tmp\"
                    exit 1
                fi
            fi
            mv -f \"/usr/share/wine/gecko/$WINE_GECKO_MSI.tmp\" \"/usr/share/wine/gecko/$WINE_GECKO_MSI\"
        else
            echo \"[✓] Wine Gecko MSI already present.\"
        fi
    " || { echo "[!] Offline bundle installation failed."; return 1; }

    echo "[✓] Wine Mono & Gecko offline bundles installed successfully."
}

asl_wine_bundle_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- Wine Mono & Gecko Offline Bundles ---"
    if [ -d "$DEBIANPATH/usr/share/wine/mono" ] && [ -f "$DEBIANPATH/usr/share/wine/mono/$WINE_MONO_MSI" ]; then
        echo "Wine Mono: INSTALLED ($WINE_MONO_MSI)"
    else
        echo "Wine Mono: NOT INSTALLED"
    fi

    if [ -d "$DEBIANPATH/usr/share/wine/gecko" ] && [ -f "$DEBIANPATH/usr/share/wine/gecko/$WINE_GECKO_MSI" ]; then
        echo "Wine Gecko: INSTALLED ($WINE_GECKO_MSI)"
    else
        echo "Wine Gecko: NOT INSTALLED"
    fi
}

asl_wine_bundle_clean() {
    echo "[*] Removing Wine Mono & Gecko offline bundles..."
    ensure_chroot_mounted || return 1
    asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        rm -rf /usr/share/wine/mono /usr/share/wine/gecko
    "
    echo "[✓] Wine offline bundles removed."
}

case "${1:-status}" in
    install|setup)
        asl_wine_bundle_install
        ;;
    status)
        asl_wine_bundle_status
        ;;
    clean|remove)
        asl_wine_bundle_clean
        ;;
    *)
        echo "Usage: asl wine-bundle [install|status|clean]"
        ;;
esac
