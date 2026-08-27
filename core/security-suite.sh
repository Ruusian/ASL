#!/bin/bash
# ASL: Containerized Defensive Security & Audit Toolsuite
# Provides isolated network security auditing, packet inspection, and penetration testing tools inside Debian chroot.

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_require_default_debianpath

asl_security_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- ASL Defensive Security Toolsuite Status ---"

    check_sec_tool() {
        local name="$1" cmd="$2"
        if asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; command -v $cmd >/dev/null 2>&1" 2>/dev/null; then
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

asl_security_audit() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "=== ASL Defensive Network & Port Security Audit ==="
    echo ""
    echo "[*] Local Listening Sockets & Ports:"
    asl_chroot_exec '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        if command -v ss >/dev/null 2>&1; then
            ss -tuln
        elif command -v netstat >/dev/null 2>&1; then
            netstat -tuln
        else
            cat /proc/net/tcp 2>/dev/null || echo "Unable to inspect listening sockets."
        fi
    ' 2>/dev/null || true

    echo ""
    echo "[*] Quick Localhost Port Scan (Top Services):"
    asl_chroot_exec '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        if command -v nmap >/dev/null 2>&1; then
            nmap -sT -T4 127.0.0.1 2>/dev/null | grep -E "^[0-9]+/tcp" || echo "  No open standard ports detected."
        else
            echo "  Nmap not installed (run '\''asl security-suite install basic'\'' for full audit capabilities)."
        fi
    ' 2>/dev/null || true
    echo ""
    echo "[✓] Local security audit completed."
}

asl_security_install() {
    local preset="${1:-basic}"
    case "$preset" in
        basic|network|audit|full|all|nmap|wireshark|tshark) ;;
        *)
            if [[ ! "$preset" =~ ^[A-Za-z0-9][A-Za-z0-9+.-]*$ ]]; then
                echo "[!] Invalid package name: $preset"
                return 1
            fi
            ;;
    esac
    ensure_chroot_mounted || return 1
    echo "[*] Installing defensive security toolsuite preset: $preset..."

    asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        export DEBIAN_FRONTEND=noninteractive
        set -e
        apt-get update

        case '$preset' in
            basic|network)
                echo '[*] Installing basic network auditing tools...'
                apt-get install -y nmap tcpdump netcat-openbsd socat iperf3 traceroute dnsutils
                ;;
            audit|full|all)
                echo '[*] Installing full security audit suite...'
                echo 'wireshark-common wireshark-common/install-setuid boolean true' | debconf-set-selections 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get install -y nmap tshark tcpdump socat hydra aircrack-ng john hashcat
                ;;
            nmap) apt-get install -y nmap ;;
            wireshark|tshark)
                echo 'wireshark-common wireshark-common/install-setuid boolean true' | debconf-set-selections 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get install -y tshark
                ;;
            *)
                echo '[*] Installing custom package: $preset'
                apt-get install -y '$preset'
                ;;
        esac
    " || { echo "[!] Security suite installation failed."; return 1; }

    echo "[✓] Defensive security toolsuite preset '$preset' installed successfully."
}

case "${1:-status}" in
    status|list)
        asl_security_status
        ;;
    audit|scan|check)
        asl_security_audit
        ;;
    install|setup)
        asl_security_install "${2:-basic}"
        ;;
    basic|network|full|all|nmap|wireshark|tshark)
        asl_security_install "$1"
        ;;
    *)
        echo "Usage: asl security-suite [status|audit|install <preset|package>]"
        echo "Presets: basic, audit, all, nmap, wireshark"
        ;;
esac
