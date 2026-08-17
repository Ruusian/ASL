#!/bin/bash
# Source-only GPU profile selection for ASL.

asl_gpu_detect() {
    ASL_GPU_PLATFORM=$(getprop ro.board.platform 2>/dev/null || true)
    ASL_GPU_PLATFORM=${ASL_GPU_PLATFORM,,}
    ASL_GPU_PROFILE="generic-virgl"

    local is_adreno=0
    case "$ASL_GPU_PLATFORM" in
        msm*|sm*|qcom*|sdm*|lahaina*|taro*|cape*|kalama*|pineapple*|sun*|yupik*|crow*|clivo*|bengal*|lito*|atoll*|trinket*)
            is_adreno=1
            ;;
        *)
            if [ -c /dev/kgsl-3d0 ] || [ -d /sys/class/kgsl/kgsl-3d0 ] || [ -c /dev/dri/renderD128 ] || [ -c /dev/dri/card0 ]; then
                is_adreno=1
            fi
            ;;
    esac

    if [ "$is_adreno" -eq 1 ]; then
        DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
        if [ -d "$DEBIANPATH" ] && asl_chroot_exec "compgen -G /usr/lib/*/dri/zink_dri.so >/dev/null || compgen -G /usr/share/vulkan/icd.d/*freedreno*.json >/dev/null || compgen -G /usr/share/vulkan/icd.d/*turnip*.json >/dev/null || compgen -G /usr/local/share/vulkan/icd.d/*.json >/dev/null" 2>/dev/null; then
            ASL_GPU_PROFILE="adreno-turnip-zink"
        else
            ASL_GPU_PROFILE="generic-virgl"
        fi
    elif [ "$ASL_GPU_PROFILE" = "generic-virgl" ]; then
        case "$ASL_GPU_PLATFORM" in
            exynos*|mali*|mt*|dimensity*) ASL_GPU_PROFILE="mali-virgl" ;;
        esac
    fi
}

asl_gpu_icd_in_chroot() {
    DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
    local found=""
    found=$(asl_chroot_exec "find /usr/share/vulkan/icd.d /usr/local/share/vulkan/icd.d /etc/vulkan/icd.d -type f \( -name '*freedreno*.json' -o -name '*turnip*.json' \) 2>/dev/null | head -n1" 2>/dev/null || true)
    if [ -n "$found" ]; then
        printf '%s' "$found"
    elif [ -f "$DEBIANPATH/usr/share/vulkan/icd.d/freedreno_icd.json" ]; then
        printf '%s' "/usr/share/vulkan/icd.d/freedreno_icd.json"
    else
        printf '%s' "/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    fi
}

asl_gpu_icd_name() {
    local icd_path
    icd_path=$(asl_gpu_icd_in_chroot)
    basename "$icd_path"
}

asl_gpu_apply() {
    asl_gpu_detect
    unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE MESA_VK_WINSYS TU_DEBUG MESA_SHADER_CACHE_DIR VK_ICD_FILENAMES VK_DRIVER_FILES MESA_GL_VERSION_OVERRIDE

    case "$ASL_GPU_PROFILE" in
        adreno-turnip-zink)
            export GALLIUM_DRIVER=zink
            export MESA_LOADER_DRIVER_OVERRIDE=zink
            export MESA_VK_WINSYS=x11
            local icd_chroot
            icd_chroot=$(asl_gpu_icd_in_chroot)
            export VK_ICD_FILENAMES="$DEBIANPATH$icd_chroot"
            export VK_DRIVER_FILES="$DEBIANPATH$icd_chroot"
            export MESA_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_GL_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_VK_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_SHADER_CACHE_MAX_SIZE="1G"
            export TU_DEBUG=noconform
            ;;
        mali-virgl|generic-virgl|*)
            export GALLIUM_DRIVER=virpipe
            export MESA_GL_VERSION_OVERRIDE=4.0
            export MESA_VK_WINSYS=x11
            export MESA_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_GL_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_VK_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_SHADER_CACHE_MAX_SIZE="1G"
            ;;
    esac
}

asl_gpu_env_exports() {
    asl_gpu_apply
    local icd_path_in_chroot=""
    if [ "$ASL_GPU_PROFILE" = "adreno-turnip-zink" ]; then
        icd_path_in_chroot=$(asl_gpu_icd_in_chroot)
    fi
    local res=""
    [ -n "${GALLIUM_DRIVER:-}" ] && res="${res}export GALLIUM_DRIVER=\"${GALLIUM_DRIVER}\"\n"
    [ -n "${MESA_LOADER_DRIVER_OVERRIDE:-}" ] && res="${res}export MESA_LOADER_DRIVER_OVERRIDE=\"${MESA_LOADER_DRIVER_OVERRIDE}\"\n"
    res="${res}export MESA_VK_WINSYS=\"${MESA_VK_WINSYS:-x11}\"\n"
    if [ -n "$icd_path_in_chroot" ]; then
        res="${res}export VK_ICD_FILENAMES=\"${icd_path_in_chroot}\"\n"
        res="${res}export VK_DRIVER_FILES=\"${icd_path_in_chroot}\"\n"
    fi
    [ -n "${TU_DEBUG:-}" ] && res="${res}export TU_DEBUG=\"${TU_DEBUG}\"\n"
    res="${res}export MESA_SHADER_CACHE_DIR=\"${MESA_SHADER_CACHE_DIR:-/tmp/.mesa_cache}\"\n"
    res="${res}export MESA_GL_SHADER_CACHE_DIR=\"${MESA_GL_SHADER_CACHE_DIR:-/tmp/.mesa_cache}\"\n"
    res="${res}export MESA_VK_SHADER_CACHE_DIR=\"${MESA_VK_SHADER_CACHE_DIR:-/tmp/.mesa_cache}\"\n"
    res="${res}export MESA_SHADER_CACHE_MAX_SIZE=\"${MESA_SHADER_CACHE_MAX_SIZE:-1G}\"\n"
    [ -n "${MESA_GL_VERSION_OVERRIDE:-}" ] && res="${res}export MESA_GL_VERSION_OVERRIDE=\"${MESA_GL_VERSION_OVERRIDE}\"\n"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/hud.sh" ]; then
        local hud_exp
        hud_exp=$("$script_dir/hud.sh" env 2>/dev/null || true)
        [ -n "$hud_exp" ] && res="${res}${hud_exp}\n"
    fi

    printf '%b' "$res"
}

asl_sync_chroot_env() {
    DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
    if [ -d "$DEBIANPATH/etc/profile.d" ]; then
        local env_script
        env_script="$(asl_gpu_env_exports)"
        asl_exec "cat << 'EOF' > '$DEBIANPATH/etc/profile.d/asl_env.sh'
#!/bin/sh
# ASL Dynamic Environment
$env_script
EOF
chmod 644 '$DEBIANPATH/etc/profile.d/asl_env.sh'
" 2>/dev/null || true
    fi
}

asl_gpu_report() {
    asl_gpu_apply
    printf 'Profile: %s\n' "$ASL_GPU_PROFILE"
    printf 'Platform: %s\n' "${ASL_GPU_PLATFORM:-unknown}"
    printf 'GALLIUM_DRIVER=%s\n' "${GALLIUM_DRIVER:-}"
    printf 'MESA_LOADER_DRIVER_OVERRIDE=%s\n' "${MESA_LOADER_DRIVER_OVERRIDE:-}"
    printf 'MESA_VK_WINSYS=%s\n' "${MESA_VK_WINSYS:-}"
    printf 'TU_DEBUG=%s\n' "${TU_DEBUG:-}"
}

asl_gpu_install_drivers() {
    asl_gpu_detect
    DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
    echo "[*] Auto-installing prebuilt GPU drivers for profile: $ASL_GPU_PROFILE ($ASL_GPU_PLATFORM)..."
    if [ ! -d "$DEBIANPATH" ]; then
        echo "[!] Error: Chroot directory does not exist at $DEBIANPATH"
        return 1
    fi

    if ! is_mounted "$DEBIANPATH"; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$script_dir/mount-chroot.sh" ]; then
            bash "$script_dir/mount-chroot.sh" || return 1
        elif [ -f "$script_dir/../core/mount-chroot.sh" ]; then
            bash "$script_dir/../core/mount-chroot.sh" || return 1
        fi
    fi

    if asl_chroot_exec "/usr/bin/test -f /etc/debian_version" 2>/dev/null; then
        if ! asl_chroot_exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/bin; apt-get update && apt-get install -y mesa-vulkan-drivers libgl1-mesa-dri vulkan-tools libvulkan1"; then
            echo "[!] GPU driver package installation failed."
            return 1
        fi
        echo "[✓] Prebuilt GPU hardware acceleration drivers installed."
    else
        echo "[*] Non-Debian rootfs detected; skipping Debian apt driver package auto-installation."
    fi
}

