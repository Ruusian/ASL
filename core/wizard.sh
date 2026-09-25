#!/bin/bash
# ASL: Guided First-Time Setup Wizard & Initialization Engine
# Interactive configuration for new users (GPU/Graphics, Development, Security, or Full Workstation).

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_require_default_debianpath

run_preset_desktop() {
    echo ""
    echo "[*] Setting up XFCE4 Desktop & Termux:X11 GUI environment..."
    ensure_chroot_mounted || return 1
    local desk_script
    desk_script=$(asl_find_script "start-desktop.sh")
    if [ -f "$desk_script" ]; then
        bash "$desk_script" setup || echo "[!] Desktop setup notice."
    fi
    echo "[✓] XFCE4 Desktop environment setup completed!"
}

run_preset_graphics() {
    echo ""
    echo "[*] Setting up GPU & Graphics Acceleration environment..."
    ensure_chroot_mounted || return 1
    local err_count=0

    echo "[1/4] Auto-detecting GPU hardware and applying acceleration..."
    source "$SCRIPT_DIR/core/gpu-profile.sh"
    asl_gpu_install_drivers || err_count=$((err_count + 1))
    asl_gpu_apply || err_count=$((err_count + 1))

    echo "[2/4] Enabling MangoHud performance overlay..."
    if [ -f "$SCRIPT_DIR/core/hud.sh" ]; then
        bash "$SCRIPT_DIR/core/hud.sh" on || err_count=$((err_count + 1))
    fi

    echo "[3/4] Synchronizing Bluetooth & USB gamepad input nodes..."
    if [ -f "$SCRIPT_DIR/core/gamepad.sh" ]; then
        bash "$SCRIPT_DIR/core/gamepad.sh" sync || err_count=$((err_count + 1))
    fi

    echo "[4/4] Verifying XFCE4 Desktop environment..."
    if ! asl_chroot_exec "test -x /usr/bin/xfwm4 -o -x /usr/bin/xfce4-session" 2>/dev/null; then
        run_preset_desktop || err_count=$((err_count + 1))
    fi

    if [ "$err_count" -eq 0 ]; then
        echo "[✓] GPU & Graphics setup completed!"
    else
        echo "[!] GPU & Graphics setup completed with $err_count warning(s)."
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

    run_preset_graphics
    run_preset_dev
    run_preset_security

    echo "[✓] Full Linux Workstation setup completed!"
}

asl_wizard_interactive() {
    clear
    echo "============================================================"
    echo "       🚀 ASL Guided First-Time Setup Wizard"
    echo "============================================================"
    echo " Welcome to Android Subsystem for Linux!"
    echo " Let's configure your environment in a few quick steps."
    echo ""
    echo " Select your primary use case:"
    echo "   [1] 🖥️ XFCE4 Desktop        (XFCE4, D-Bus, PulseAudio, Termux:X11)"
    echo "   [2] 🎮 GPU & Graphics      (Turnip Vulkan, MangoHud, Gamepad)"
    echo "   [3] 💻 Software Developer   (Python, Node.js, Neovim, Go, Rust, VS Code)"
    echo "   [4] 🛡️ Security Auditing    (Nmap, Wireshark/TShark, Netcat, Socat)"
    echo "   [5] 🚀 Full Workstation    (Install All Toolsuites)"
    echo ""
    read -p " Enter choice [1-5] (default: 5): " choice
    choice="${choice:-5}"

    case "$choice" in
        1) run_preset_desktop ;;
        2) run_preset_graphics ;;
        3) run_preset_dev ;;
        4) run_preset_security ;;
        5|*) run_preset_workstation ;;
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

    if [ -f "$SCRIPT_DIR/bin/asl" ]; then
        bash "$SCRIPT_DIR/bin/asl" resolution "$res_preset" || true
    elif [ -x "${PREFIX:-/data/data/com.termux/files/usr}/bin/asl" ]; then
        "${PREFIX:-/data/data/com.termux/files/usr}/bin/asl" resolution "$res_preset" || true
    fi

    echo ""
    echo "============================================================"
    echo " 🎉 Setup Completed Successfully!"
    echo "============================================================"
    echo " Next steps:"
    echo "   • Launch Linux Desktop: run 'asl desktop start'"
    echo "   • Launch Interactive Console: run 'asl'"
    echo "============================================================"
}

case "${1:-}" in
    --preset|preset|-p)
        shift
        preset="${1:-workstation}"
        case "$preset" in
            desktop|xfce|gui) run_preset_desktop ;;
            gaming|graphics|gpu) run_preset_graphics ;;
            dev) run_preset_dev ;;
            security|sec) run_preset_security ;;
            workstation|full|all) run_preset_workstation ;;
            *) echo "Unknown preset: $preset. Valid: desktop, graphics, dev, security, workstation" ;;
        esac
        ;;
    *)
        asl_wizard_interactive
        ;;
esac
