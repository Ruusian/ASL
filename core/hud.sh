#!/bin/bash
# ASL: MangoHud & DXVK Performance Overlay Manager

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/asl"
HUD_STATE_FILE="$STATE_DIR/hud_state"
DEFAULT_DXVK_HUD="fps,gpuname,frametime"
DEFAULT_MANGOHUD_CONFIG="fps,cpu_temp,gpu_temp,ram,vram,font_size=16,position=top-left"

ensure_state_dir() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    chmod 700 "$STATE_DIR" 2>/dev/null || true
}

sanitize_hud_value() {
    printf '%s' "$1" | tr -d '\n\r"\`$\\'
}

asl_hud_is_enabled() {
    [ -f "$HUD_STATE_FILE" ] && grep -q '^ENABLED=1$' "$HUD_STATE_FILE" 2>/dev/null
}

asl_hud_get_dxvk() {
    local val
    if [ -f "$HUD_STATE_FILE" ]; then
        val=$(grep '^DXVK_HUD=' "$HUD_STATE_FILE" 2>/dev/null | cut -d'=' -f2-)
        sanitize_hud_value "${val:-$DEFAULT_DXVK_HUD}"
    else
        echo "$DEFAULT_DXVK_HUD"
    fi
}

asl_hud_get_mangohud() {
    local val
    if [ -f "$HUD_STATE_FILE" ]; then
        val=$(grep '^MANGOHUD_CONFIG=' "$HUD_STATE_FILE" 2>/dev/null | cut -d'=' -f2-)
        sanitize_hud_value "${val:-$DEFAULT_MANGOHUD_CONFIG}"
    else
        echo "$DEFAULT_MANGOHUD_CONFIG"
    fi
}

sync_chroot() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/gpu-profile.sh" ]; then
        (source "$script_dir/gpu-profile.sh" && asl_sync_chroot_env 2>/dev/null) || true
    fi
}

asl_hud_enable() {
    ensure_state_dir
    local dxvk_cfg mango_cfg
    dxvk_cfg=$(sanitize_hud_value "${1:-$DEFAULT_DXVK_HUD}")
    mango_cfg=$(sanitize_hud_value "${2:-$DEFAULT_MANGOHUD_CONFIG}")
    printf 'ENABLED=1\nDXVK_HUD=%s\nMANGOHUD_CONFIG=%s\n' "$dxvk_cfg" "$mango_cfg" > "$HUD_STATE_FILE"
    chmod 600 "$HUD_STATE_FILE" 2>/dev/null || true
    echo "[✓] Performance Overlay (MangoHud / DXVK HUD) ENABLED."
    echo "    DXVK_HUD: $dxvk_cfg"
    echo "    MANGOHUD_CONFIG: $mango_cfg"
    sync_chroot
}

asl_hud_disable() {
    ensure_state_dir
    printf 'ENABLED=0\n' > "$HUD_STATE_FILE"
    chmod 600 "$HUD_STATE_FILE" 2>/dev/null || true
    echo "[✓] Performance Overlay DISABLED."
    sync_chroot
}

asl_hud_toggle() {
    if asl_hud_is_enabled; then
        asl_hud_disable
    else
        asl_hud_enable
    fi
}

asl_hud_status() {
    if asl_hud_is_enabled; then
        echo "Performance Overlay: ENABLED"
        echo "  - DXVK HUD:       $(asl_hud_get_dxvk)"
        echo "  - MangoHud Config: $(asl_hud_get_mangohud)"
    else
        echo "Performance Overlay: DISABLED"
    fi
}

asl_hud_env_exports() {
    if asl_hud_is_enabled; then
        local dxvk_cfg mango_cfg
        dxvk_cfg=$(asl_hud_get_dxvk)
        mango_cfg=$(asl_hud_get_mangohud)
        printf 'export DXVK_HUD="%s"\n' "$dxvk_cfg"
        printf 'export MANGOHUD="1"\n'
        printf 'export MANGOHUD_CONFIG="%s"\n' "$mango_cfg"
    else
        printf 'unset DXVK_HUD MANGOHUD MANGOHUD_CONFIG\n'
    fi
}

case "${1:-status}" in
    on|enable)
        shift
        asl_hud_enable "$@"
        ;;
    off|disable)
        asl_hud_disable
        ;;
    toggle)
        asl_hud_toggle
        ;;
    status)
        asl_hud_status
        ;;
    env|exports)
        asl_hud_env_exports
        ;;
    *)
        echo "Usage: asl hud [on|off|toggle|status|env]"
        ;;
esac
