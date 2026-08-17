#!/bin/bash
# ASL: IDE & Developer Environment Suite Installer
# One-click installation and management for development environments (VS Code Server, Neovim, Python, Node, Go, Rust).

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

ensure_chroot_mounted() {
    if ! is_mounted; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

asl_dev_suite_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- ASL Developer Environment Suite Status ---"

    check_pkg() {
        local name="$1" cmd="$2"
        if asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; command -v $cmd >/dev/null 2>&1" 2>/dev/null; then
            printf "  %-12s : INSTALLED\n" "$name"
        else
            printf "  %-12s : NOT INSTALLED\n" "$name"
        fi
    }

    check_pkg "Neovim" "nvim"
    check_pkg "Python3" "python3"
    check_pkg "Node.js" "node"
    check_pkg "Golang" "go"
    check_pkg "Rust" "rustc"
    check_pkg "VS Code" "code-server"
}

asl_dev_suite_install() {
    local preset="${1:-all}"
    ensure_chroot_mounted || return 1
    echo "[*] Installing developer suite preset: $preset..."

    asl_chroot_exec "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        set -e
        apt-get update

        install_python() {
            echo \"[*] Installing Python3 development toolchain...\"
            apt-get install -y python3 python3-pip python3-venv python3-dev build-essential
        }

        install_webdev() {
            echo \"[*] Installing Node.js & Web Development toolchain...\"
            apt-get install -y nodejs npm
        }

        install_neovim() {
            echo \"[*] Installing Neovim & Git tooling...\"
            apt-get install -y neovim git curl ripgrep fd-find
        }

        install_golang() {
            echo \"[*] Installing Golang toolchain...\"
            apt-get install -y golang-go
        }

        install_rust() {
            echo \"[*] Installing Rust & Cargo toolchain...\"
            apt-get install -y rustc cargo
        }

        install_vscode() {
            echo \"[*] Installing VS Code Server (code-server)...\"
            if ! command -v code-server >/dev/null 2>&1; then
                curl -fsSL https://code-server.dev/install.sh | sh || {
                    echo \"[!] code-server script installation skipped or failed.\"
                }
            fi
        }

        case \"$preset\" in
            python) install_python ;;
            webdev|node) install_webdev ;;
            neovim|nvim) install_neovim ;;
            go|golang) install_golang ;;
            rust) install_rust ;;
            vscode|code-server) install_vscode ;;
            all)
                install_python
                install_webdev
                install_neovim
                install_golang
                install_rust
                ;;
            *)
                echo \"[!] Unknown dev suite preset: $preset\"
                echo \"Valid presets: python, webdev, neovim, go, rust, vscode, all\"
                exit 1
                ;;
        esac
    " || { echo "[!] Dev suite installation failed."; return 1; }

    echo "[✓] Developer suite preset '$preset' installed successfully."
}

case "${1:-status}" in
    status|list)
        asl_dev_suite_status
        ;;
    install|setup)
        asl_dev_suite_install "${2:-all}"
        ;;
    *)
        echo "Usage: asl dev-suite [status|install <preset>]"
        echo "Presets: python, webdev, neovim, go, rust, vscode, all"
        ;;
esac
