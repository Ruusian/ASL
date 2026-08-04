#!/bin/bash
# AndroidLinux-SuperKit: Gaming Layer (MoBox Inspired)
# Wine + Box64/Box86 + DXVK/VKD3D Helper & Launcher

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/core/gpu-profile.sh"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

set_box64_env() {
    export BOX64_LOG=1
    export BOX64_DYNAREC_FASTNAN=1
    export BOX64_DYNAREC_FASTROUND=1
    export BOX64_DYNAREC_SAFEFLAGS=1
    export BOX64_DYNAREC_BIGBLOCK=1
    export BOX64_DYNAREC_FORWARD=128
    export BOX64_DYNAREC_CALLRET=1
    export BOX64_DYNAREC_WAIT=1
    export BOX64_DYNAREC_X87=1
    export BOX64_SHOWFLOATS=0
    echo "[+] Applied Box64 high-performance Dynarec presets."
}

set_dxvk_env() {
    export DXVK_HUD="${DXVK_HUD:-fps,githash}"
    export DXVK_ASYNC=1
    export DXVK_STATE_CACHE=1
    echo "[+] Applied DXVK performance presets."
}

show_gaming_menu() {
    echo "=========================================="
    echo "       MoBox-Style Gaming Launcher"
    echo "=========================================="
    echo "1) Launch Wine Config (winecfg)"
    echo "2) Run Windows Executable (.exe)"
    echo "3) Apply Performance Dynarec Tweaks"
    echo "4) Create New Wine Container / Prefix"
    echo "5) Exit"
    echo ""
}

run_wine_exe() {
    EXE_PATH="${1:-}"
    if [ -z "$EXE_PATH" ]; then
        echo -n "Enter full path to .exe file: "
        read -r EXE_PATH
    fi

    if [ ! -f "$EXE_PATH" ]; then
        echo "[!] File not found: $EXE_PATH"
        return 1
    fi

    set_box64_env
    set_dxvk_env

    local exe_b64 gpu_env
    exe_b64=$(printf '%s' "$EXE_PATH" | base64 | tr -d '\n')
    superkit_gpu_apply
    gpu_env="GALLIUM_DRIVER=$GALLIUM_DRIVER MESA_VK_WINSYS=$MESA_VK_WINSYS"
    [ -n "${MESA_LOADER_DRIVER_OVERRIDE:-}" ] && gpu_env="$gpu_env MESA_LOADER_DRIVER_OVERRIDE=$MESA_LOADER_DRIVER_OVERRIDE"
    [ -n "${TU_DEBUG:-}" ] && gpu_env="$gpu_env TU_DEBUG=$TU_DEBUG"

    echo "[*] Executing $EXE_PATH inside chroot with $SUPERKIT_GPU_PROFILE..."
    su -c "chroot '$DEBIANPATH' /bin/bash --noprofile --norc -c 'export DISPLAY=:0 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=xterm LANG=C.UTF-8 $gpu_env BOX64_LOG=1 BOX64_DYNAREC_FASTNAN=1 BOX64_DYNAREC_FASTROUND=1 BOX64_DYNAREC_SAFEFLAGS=1 BOX64_DYNAREC_BIGBLOCK=1 BOX64_DYNAREC_FORWARD=128 BOX64_DYNAREC_CALLRET=1 BOX64_DYNAREC_WAIT=1 BOX64_DYNAREC_X87=1 BOX64_SHOWFLOATS=0 DXVK_HUD=\"${DXVK_HUD:-fps,githash}\" DXVK_ASYNC=1 DXVK_STATE_CACHE=1; exe_path=\$(printf %s $exe_b64 | /usr/bin/base64 -d); exec box64 wine \"\$exe_path\"'"
}

case "${1:-}" in
    run)
        shift
        run_wine_exe "$@"
        ;;
    menu|"")
        show_gaming_menu
        ;;
    *)
        run_wine_exe "$@"
        ;;
esac
