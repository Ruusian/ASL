#!/bin/bash
# Termux Droid compatibility helpers for the unified ASL workflow.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASL_BIN="${ASL_DIR:-$SCRIPT_DIR}/bin/asl"
[ -f "$ASL_BIN" ] || ASL_BIN=$(command -v asl || echo "$SCRIPT_DIR/bin/asl")

termux_droid_help() {
    cat <<'EOF'
Termux Droid compatibility workflow

  asl termux-droid setup      Show the recommended ASL setup sequence
  asl termux-droid start      Start the ASL XFCE4 desktop
  asl termux-droid stop       Stop the ASL desktop and chroot
  asl termux-droid status     Show the ASL environment status
  asl termux-droid sync-apps  Sync Debian applications into the desktop menu
  asl termux-droid bridge     Show Raspberry Pi bridge usage

ASL provides the same root/proot, XFCE4, Termux:X11, and GPU workflow
without maintaining a second container or desktop configuration.
EOF
}

termux_droid_setup() {
    cat <<'EOF'
Recommended setup:
  1. Run: asl doctor
  2. Run: asl start
  3. Run: asl desktop start
  4. Run: asl dev-suite install   (optional development tools)
  5. Run: asl security-suite install (optional security tools)

For non-root devices ASL automatically uses proot mode. Rooted devices may
use chroot mode when configured during installation.
EOF
}

termux_droid_bridge() {
    cat <<EOF
The Raspberry Pi bridge is available at:
  $SCRIPT_DIR/desktop/pi-bridge.sh

Copy it to the Pi, install a VNC viewer, enable USB tethering, and run:
  bash pi-bridge.sh
EOF
}

termux_droid() {
    case "${1:-help}" in
        setup) termux_droid_setup ;;
        start)
            bash "$ASL_BIN" start && bash "$ASL_BIN" desktop start
            ;;
        stop)
            bash "$ASL_BIN" desktop stop || true
            bash "$ASL_BIN" stop
            ;;
        status) bash "$ASL_BIN" status ;;
        sync-apps) bash "$ASL_BIN" desktop sync-apps ;;
        bridge) termux_droid_bridge ;;
        help|-h|--help) termux_droid_help ;;
        *)
            echo "Error: unknown termux-droid action: $1" >&2
            termux_droid_help >&2
            return 1
            ;;
    esac
}