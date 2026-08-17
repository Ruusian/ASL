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
            if [ -c /dev/kgsl-3d0 ] || [ -d /sys/class/kgsl/kgsl-3d0 ]; then
                is_adreno=1
            fi
            ;;
    esac

    if [ "$is_adreno" -eq 1 ]; then
        DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
        if [ -d "$DEBIANPATH" ] && su -c "chroot '$DEBIANPATH' /bin/bash -c 'compgen -G /usr/lib/*/dri/zink_dri.so >/dev/null || compgen -G /usr/share/vulkan/icd.d/freedreno_icd*.json >/dev/null || [ -f /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json ]'" 2>/dev/null; then
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

asl_gpu_icd_name() {
    DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
    if [ -f "$DEBIANPATH/usr/share/vulkan/icd.d/freedreno_icd.json" ]; then
        printf '%s' "freedreno_icd.json"
    elif [ -f "$DEBIANPATH/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json" ]; then
        printf '%s' "freedreno_icd.aarch64.json"
    else
        printf '%s' "freedreno_icd.aarch64.json"
    fi
}

asl_gpu_apply() {
    asl_gpu_detect
    unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE MESA_VK_WINSYS TU_DEBUG MESA_SHADER_CACHE_DIR VK_ICD_FILENAMES VK_DRIVER_FILES MESA_GL_VERSION_OVERRIDE

    case "$ASL_GPU_PROFILE" in
        adreno-turnip-zink)
            export GALLIUM_DRIVER=zink
            export MESA_LOADER_DRIVER_OVERRIDE=zink
            export MESA_VK_WINSYS=x11
            local icd_name
            icd_name=$(asl_gpu_icd_name)
            export VK_ICD_FILENAMES="$DEBIANPATH/usr/share/vulkan/icd.d/$icd_name"
            export VK_DRIVER_FILES="$DEBIANPATH/usr/share/vulkan/icd.d/$icd_name"
            export MESA_SHADER_CACHE_DIR="/dev/shm/mesa_shader_cache"
            export TU_DEBUG=noconform
            ;;
        mali-virgl|generic-virgl|*)
            export GALLIUM_DRIVER=virpipe
            export MESA_GL_VERSION_OVERRIDE=4.0
            export MESA_VK_WINSYS=x11
            export MESA_SHADER_CACHE_DIR="/dev/shm/mesa_shader_cache"
            ;;
    esac
}

asl_gpu_env_exports() {
    asl_gpu_apply
    local icd_path_in_chroot=""
    if [ "$ASL_GPU_PROFILE" = "adreno-turnip-zink" ]; then
        icd_path_in_chroot="/usr/share/vulkan/icd.d/$(asl_gpu_icd_name)"
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
    res="${res}export MESA_SHADER_CACHE_DIR=\"${MESA_SHADER_CACHE_DIR:-/dev/shm/mesa_shader_cache}\"\n"
    [ -n "${MESA_GL_VERSION_OVERRIDE:-}" ] && res="${res}export MESA_GL_VERSION_OVERRIDE=\"${MESA_GL_VERSION_OVERRIDE}\"\n"
    printf '%b' "$res"
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

    if su -c "chroot '$DEBIANPATH' /usr/bin/test -f /etc/debian_version" 2>/dev/null; then
        if ! su -c "chroot '$DEBIANPATH' /bin/bash -c '
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            apt-get update && apt-get install -y mesa-vulkan-drivers libgl1-mesa-dri vulkan-tools libvulkan1
        '"; then
            echo "[!] GPU driver package installation failed."
            return 1
        fi
        echo "[✓] Prebuilt GPU hardware acceleration drivers installed."
    else
        echo "[*] Non-Debian rootfs detected; skipping Debian apt driver package auto-installation."
    fi
}

