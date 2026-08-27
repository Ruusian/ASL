#!/bin/bash
# ASL: IDE & Developer Environment Suite Installer
# One-click installation and management for development environments (VS Code Server, Neovim, Python, Node, Go, Rust).

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_require_default_debianpath

asl_dev_suite_status() {
    ensure_chroot_mounted 2>/dev/null || true
    echo "--- ASL Developer Environment Suite Status ---"

    check_pkg() {
        local name="$1" cmd="$2"
        if asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; command -v \"$cmd\" >/dev/null 2>&1" 2>/dev/null; then
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
        export DEBIAN_FRONTEND=noninteractive
        set -e
        apt-get update

        install_python() {
            echo '[*] Installing Python3 development toolchain...'
            apt-get install -y python3 python3-pip python3-venv python3-dev build-essential
        }

        install_webdev() {
            echo '[*] Installing Node.js & Web Development toolchain...'
            apt-get install -y nodejs npm
        }

        install_neovim() {
            echo '[*] Installing Neovim & Git tooling...'
            apt-get install -y neovim git curl ripgrep fd-find
        }

        install_golang() {
            echo '[*] Installing Golang toolchain...'
            apt-get install -y golang-go
        }

        install_rust() {
            echo '[*] Installing Rust & Cargo toolchain...'
            apt-get install -y rustc cargo
        }

        install_vscode() {
            echo '[*] Installing VS Code Server (code-server)...'
            if ! command -v code-server >/dev/null 2>&1; then
                if command -v npm >/dev/null 2>&1; then
                    echo '[*] Installing code-server via npm (integrity-checked)...'
                    npm install -g code-server || { echo '[!] npm install of code-server failed.'; }
                else
                    echo '[*] Installing code-server from pinned GitHub release...'
                    CS_VER=v4.96.4
                    case \"\$(uname -m 2>/dev/null)\" in
                        aarch64|arm64) CS_ARCH=arm64 ;;
                        armv7l|armhf)  CS_ARCH=armv7l ;;
                        x86_64|amd64)  CS_ARCH=amd64 ;;
                        *) echo '[!] Unsupported architecture for code-server.'; return 1 ;;
                    esac
                    TMP_DIR=\$(mktemp -d) || return 1
                    CS_URL=\"https://github.com/coder/code-server/releases/download/\${CS_VER}/code-server-\${CS_VER#v}-linux-\${CS_ARCH}.tar.gz\"
                    if ! curl -fsSL --connect-timeout 15 --max-time 120 -o \"\$TMP_DIR/cs.tar.gz\" \"\$CS_URL\"; then
                        echo '[!] Failed to download code-server.'
                        rm -rf \"\$TMP_DIR\"
                        return 1
                    fi
                    SHA_URL=\"https://github.com/coder/code-server/releases/download/\${CS_VER}/SHA256SUMS\"
                    EXPECTED=\$(curl -fsSL --connect-timeout 15 --max-time 30 \"\$SHA_URL\" 2>/dev/null | grep -E \"code-server-\${CS_VER#v}-linux-\${CS_ARCH}.tar.gz\" | awk '{print \$1}' | head -n1)
                    if [ -z \"\$EXPECTED\" ]; then
                        echo '[!] Could not fetch checksum for code-server; continuing (HTTPS download).'
                    elif ! echo \"\$EXPECTED  \$TMP_DIR/cs.tar.gz\" | sha256sum -c - >/dev/null 2>&1; then
                        echo '[!] code-server checksum verification failed; aborting.'
                        rm -rf \"\$TMP_DIR\"
                        return 1
                    fi
                    tar -xzf \"\$TMP_DIR/cs.tar.gz\" -C /usr/local/lib 2>/dev/null || {
                        echo '[!] Failed to extract code-server.'
                        rm -rf \"\$TMP_DIR\"
                        return 1
                    }
                    ln -sf \"/usr/local/lib/code-server-\${CS_VER#v}-linux-\${CS_ARCH}/bin/code-server\" /usr/local/bin/code-server 2>/dev/null || true
                    rm -rf \"\$TMP_DIR\"
                fi
            fi
        }
        case '$preset' in
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
                echo '[!] Unknown dev suite preset: $preset'
                echo 'Valid presets: python, webdev, neovim, go, rust, vscode, all'
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
    python|webdev|node|neovim|nvim|go|golang|rust|vscode|code-server|all)
        asl_dev_suite_install "$1"
        ;;
    *)
        echo "Usage: asl dev-suite [status|install <preset>]"
        echo "Presets: python, webdev, neovim, go, rust, vscode, all"
        ;;
esac
