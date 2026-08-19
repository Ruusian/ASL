#!/bin/bash
# ASL: Guided First-Time Setup Wizard & Initialization Engine
# Interactive configuration for new users (Gaming, Development, Security, or Full Workstation).

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_require_default_debianpath

ensure_chroot_mounted() {
    if ! is_mounted; then
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || return 1
        fi
    fi
}

run_preset_gaming() {
    echo ""
    echo "[*] Setting up Gaming Workstation environment..."
    ensure_chroot_mounted || return 1
    local err_count=0

    echo "[1/4] Auto-detecting GPU hardware and applying acceleration..."
    source "$SCRIPT_DIR/core/gpu-profile.sh"
    asl_gpu_apply || err_count=$((err_count + 1))

    echo "[2/4] Deploying Wine, Box64, and offline Mono/Gecko bundles..."
    if [ -f "$SCRIPT_DIR/core/wine-bundle.sh" ]; then
        bash "$SCRIPT_DIR/core/wine-bundle.sh" install || err_count=$((err_count + 1))
    fi

    echo "[3/4] Enabling MangoHud performance overlay..."
    if [ -f "$SCRIPT_DIR/core/hud.sh" ]; then
        bash "$SCRIPT_DIR/core/hud.sh" on || err_count=$((err_count + 1))
    fi

    echo "[4/4] Synchronizing Bluetooth & USB gamepad input nodes..."
    if [ -f "$SCRIPT_DIR/core/gamepad.sh" ]; then
        bash "$SCRIPT_DIR/core/gamepad.sh" sync || err_count=$((err_count + 1))
    fi

    if [ "$err_count" -eq 0 ]; then
        echo "[✓] Gaming Workstation setup completed!"
    else
        echo "[!] Gaming Workstation setup completed with $err_count warning(s)."
    fi
}

run_preset_dev() {
    echo ""
    echo "[*] Setting up Software Development environment..."
    ensure_chroot_mounted || return 1

    if [ -f "$SCRIPT_DIR/core/dev-suite.sh" ]; then
        bash "$SCRIPT_DIR/core/dev-suite.sh" install all || true
    fi

    echo "[✓] Software Development setup completed!"
}

run_preset_security() {
    echo ""
    echo "[*] Setting up Defensive Security Auditing environment..."
    ensure_chroot_mounted || return 1

    if [ -f "$SCRIPT_DIR/core/security-suite.sh" ]; then
        bash "$SCRIPT_DIR/core/security-suite.sh" install basic || true
    fi

    echo "[✓] Security Auditing setup completed!"
}

run_preset_workstation() {
    echo ""
    echo "[*] Setting up Full Linux Workstation..."
    ensure_chroot_mounted || return 1

    run_preset_gaming
    run_preset_dev
    run_preset_security

    echo "[*] Deploying ASL Hub GTK3 Control Center to Debian Desktop..."
    if [ -f "$SCRIPT_DIR/desktop/asl-hub-installer.sh" ]; then
        bash "$SCRIPT_DIR/desktop/asl-hub-installer.sh" install || true
    fi

    echo "[✓] Full Linux Workstation setup completed!"
}

asl_wizard_interactive() {
    clear
    echo "============================================================"
    echo "       🚀 ASL Guided First-Time Setup Wizard v1.0"
    echo "============================================================"
    echo " Welcome to Android Subsystem for Linux!"
    echo " Let's configure your environment in a few quick steps."
    echo ""
    echo " Select your primary use case:"
    echo "   [1] 🎮 Gaming Workstation  (Wine, Box64, Turnip Vulkan, MangoHud, Gamepad)"
    echo "   [2] 💻 Software Developer   (Python, Node.js, Neovim, Go, Rust, VS Code)"
    echo "   [3] 🛡️ Security Auditing    (Nmap, Wireshark/TShark, Netcat, Socat)"
    echo "   [4] 🚀 Full Workstation    (Install All Toolsuites + ASL Hub Desktop App)"
    echo ""
    read -p " Enter choice [1-4] (default: 4): " choice
    choice="${choice:-4}"

    case "$choice" in
        1) run_preset_gaming ;;
        2) run_preset_dev ;;
        3) run_preset_security ;;
        4|*) run_preset_workstation ;;
    esac

    echo ""
    echo " Select Display Resolution for Termux:X11:"
    echo "   [1] 720p   (1280x720  - Fast, best battery life & FPS)"
    echo "   [2] 1080p  (1920x1080 - Balanced crispness & speed)"
    echo "   [3] Native (Device screen native resolution)"
    echo ""
    read -p " Enter resolution choice [1-3] (default: 1): " res_choice
    res_choice="${res_choice:-1}"

    case "$res_choice" in
        1) res_preset="720p" ;;
        2) res_preset="1080p" ;;
        3) res_preset="native" ;;
        *) res_preset="720p" ;;
    esac

    if [ -f "$SCRIPT_DIR/desktop/start-desktop.sh" ]; then
        bash "$SCRIPT_DIR/desktop/start-desktop.sh" resolution "$res_preset" || true
    fi

    echo ""
    echo "============================================================"
    echo " 🎉 Setup Completed Successfully!"
    echo "============================================================"
    echo " Next steps:"
    echo "   • Launch Linux Desktop: run 'asl desktop start'"
    echo "   • Open Control Center:  run 'asl hub' or click 'ASL Hub' on Desktop"
    echo "   • Launch Interactive Console: run 'asl'"
    echo "============================================================"
}

case "${1:-}" in
    --preset|preset|-p)
        shift
        preset="${1:-workstation}"
        case "$preset" in
            gaming) run_preset_gaming ;;
            dev) run_preset_dev ;;
            security|sec) run_preset_security ;;
            workstation|full|all) run_preset_workstation ;;
            *) echo "Unknown preset: $preset. Valid: gaming, dev, security, workstation" ;;
        esac
        ;;
    *)
        asl_wizard_interactive
        ;;
esac
