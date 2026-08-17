#!/bin/bash
# ASL: Containerized Defensive Security & Audit Toolsuite
# Provides isolated network security auditing, packet inspection, and penetration testing tools inside Debian chroot.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_chroot_mounted() {
    if ! su -c "grep -q -F ' $DEBIANPATH/proc ' /proc/mounts" 2>/dev/null; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

asl_security_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- ASL Defensive Security Toolsuite Status ---"

    check_sec_tool() {
        local name="$1" cmd="$2"
        if su -c "chroot '$DEBIANPATH' /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; command -v $cmd >/dev/null 2>&1'" 2>/dev/null; then
            printf "  %-14s : INSTALLED\n" "$name"
        else
            printf "  %-14s : NOT INSTALLED\n" "$name"
        fi
    }

    check_sec_tool "Nmap" "nmap"
    check_sec_tool "TShark/Wireshark" "tshark"
    check_sec_tool "TCPDump" "tcpdump"
    check_sec_tool "Netcat / Socat" "socat"
    check_sec_tool "Hydra" "hydra"
    check_sec_tool "Aircrack-ng" "aircrack-ng"
    check_sec_tool "Metasploit" "msfconsole"
}

asl_security_install() {
    local preset="${1:-basic}"
    ensure_chroot_mounted || return 1
    echo "[*] Installing defensive security toolsuite preset: $preset..."

    su -c "chroot '$DEBIANPATH' /bin/bash -c '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        set -e
        apt-get update

        case \"$preset\" in
            basic|network)
                echo \"[*] Installing basic network auditing tools...\"
                apt-get install -y nmap tcpdump netcat-openbsd socat iperf3 traceroute dnsutils
                ;;
            audit|full)
                echo \"[*] Installing full security audit suite...\"
                DEBIAN_FRONTEND=noninteractive apt-get install -y nmap tshark tcpdump socat hydra aircrack-ng john hashcat tshark
                ;;
            nmap) apt-get install -y nmap ;;
            wireshark|tshark) DEBIAN_FRONTEND=noninteractive apt-get install -y tshark ;;
            *)
                echo \"[*] Installing custom package: $preset\"
                apt-get install -y \"$preset\"
                ;;
        esac
    '" || { echo "[!] Security suite installation failed."; return 1; }

    echo "[✓] Defensive security toolsuite preset '$preset' installed successfully."
}

case "${1:-status}" in
    status|list)
        asl_security_status
        ;;
    install|setup)
        asl_security_install "${2:-basic}"
        ;;
    *)
        echo "Usage: asl security-suite [status|install <preset|package>]"
        echo "Presets: basic, audit, nmap, wireshark"
        ;;
esac
