#!/bin/bash
# Source-only GPU profile selection for ASL.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
elif [ -f "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh" ]; then
    source "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh"
elif [ -f "$HOME/ASL/core/common.sh" ]; then
    source "$HOME/ASL/core/common.sh"
fi

asl_gpu_turnip_usable() {
    # Return 0 only when a real hardware Adreno Vulkan device is present.
    # A software device (llvmpipe/lavapipe) means turnip is NOT usable.
    DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
    [ -d "$DEBIANPATH" ] || return 1
    local out
    out=$(asl_chroot_exec 'command -v vulkaninfo >/dev/null 2>&1 || exit 1
for icd in /usr/share/vulkan/icd.d/*freedreno*.json /usr/share/vulkan/icd.d/*turnip*.json; do
    [ -e "$icd" ] || continue
    info=$(VK_DRIVER_FILES="$icd" VK_ICD_FILENAMES="$icd" timeout 25 vulkaninfo --summary 2>/dev/null)
    echo "$info" | grep -q "deviceType.*INTEGRATED\|deviceType.*DISCRETE" && { echo "$info"; exit 0; }
    echo "$info" | grep -q "Adreno\|Turnip\|freedreno" && { echo "$info"; exit 0; }
done
exit 1' 2>/dev/null) || return 1
    [ -n "$out" ]
}

asl_gpu_detect() {
    ASL_GPU_PLATFORM=$(getprop ro.board.platform 2>/dev/null || true)
    ASL_GPU_PLATFORM=$(printf '%s' "$ASL_GPU_PLATFORM" | tr '[:upper:]' '[:lower:]')
    ASL_GPU_PROFILE="generic-virgl"
    ASL_GPU_MODEL="unknown"

    local is_adreno=0
    case "$ASL_GPU_PLATFORM" in
        msm*|sm*|qcom*|sdm*|lahaina*|taro*|cape*|kalama*|pineapple*|sun*|yupik*|crow*|clivo*|bengal*|lito*|atoll*|trinket*|pico*|titan*|kailua*|lanai*)
            is_adreno=1
            ;;
        *)
            if [ -c /dev/kgsl-3d0 ] || [ -d /sys/class/kgsl/kgsl-3d0 ] || [ -c /dev/dri/renderD128 ] || [ -c /dev/dri/card0 ]; then
                is_adreno=1
            fi
            ;;
    esac

    if [ "$is_adreno" -eq 1 ]; then
        # Detect Adreno GPU generation for optimal driver tuning.
        # Many Android kernels do not expose /sys/class/kgsl/kgsl-3d0/gpu_id,
        # so also read the human-readable gpu_model ("Adreno640v2") when present.
        if [ -d /sys/class/kgsl/kgsl-3d0 ]; then
            local gpu_id gpu_model
            gpu_id=$(cat /sys/class/kgsl/kgsl-3d0/gpu_id 2>/dev/null || true)
            gpu_model=$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null || true)
            case "$gpu_id" in
                7[0-9][0-9]) ASL_GPU_MODEL="adreno7xx" ;;  # Adreno 730, 740, 750
                8[0-9][0-9]) ASL_GPU_MODEL="adreno8xx" ;;  # Adreno 830, 840
                660) ASL_GPU_MODEL="adreno660" ;;
                6[0-9][0-9]) ASL_GPU_MODEL="adreno6xx" ;;  # Adreno 610-660
                *)
                    case "$gpu_model" in
                        *Adreno8*|*adreno8*) ASL_GPU_MODEL="adreno8xx" ;;
                        *Adreno7*|*adreno7*) ASL_GPU_MODEL="adreno7xx" ;;
                        *Adreno660*|*adreno660*) ASL_GPU_MODEL="adreno660" ;;
                        *Adreno6*|*adreno6*) ASL_GPU_MODEL="adreno6xx" ;;
                        *) ASL_GPU_MODEL="adreno-unknown" ;;
                    esac
                    ;;
            esac
        fi

        # Fallback if gpu_id is missing or failed (common on many Android kernels)
        if [ "$ASL_GPU_MODEL" = "adreno-unknown" ] || [ "$ASL_GPU_MODEL" = "unknown" ]; then
            case "$ASL_GPU_PLATFORM" in
                taro*|cape*|kalama*|pineapple*|sun*) ASL_GPU_MODEL="adreno7xx" ;;
                lahaina*|sm8350*) ASL_GPU_MODEL="adreno660" ;;
                kona*|msmnile*|lito*|atoll*|sm*|sdm*) ASL_GPU_MODEL="adreno6xx" ;;
            esac
        fi

        DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
        # File presence is NOT proof the driver works. Debian's mesa-vulkan-drivers is
        # frequently built WITHOUT the KGSL/turnip winsys, in which case
        # vkEnumeratePhysicalDevices fails and zink cannot create any GL context.
        # Only select turnip+zink when a real hardware Vulkan device is actually
        # enumerated; otherwise fall back to virglrenderer + ANGLE, which is the
        # accelerated path that does work on Android KGSL hardware.
        if [ -d "$DEBIANPATH" ] && asl_gpu_turnip_usable; then
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
    found=$(asl_chroot_exec "find /usr/share/vulkan/icd.d /usr/local/share/vulkan/icd.d /etc/vulkan/icd.d -type f \( -name '*freedreno*aarch64*.json' -o -name '*turnip*aarch64*.json' \) 2>/dev/null | head -n1" 2>/dev/null || true)
    if [ -n "$found" ]; then
        printf '%s' "$found"
    elif [ -f "$DEBIANPATH/usr/share/vulkan/icd.d/freedreno_icd.json" ]; then
        printf '%s' "/usr/share/vulkan/icd.d/freedreno_icd.json"
    else
        printf '%s' "/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    fi
}


asl_gpu_apply() {
    asl_gpu_detect
    unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE MESA_VK_WINSYS TU_DEBUG MESA_SHADER_CACHE_DIR VK_ICD_FILENAMES VK_DRIVER_FILES MESA_GL_VERSION_OVERRIDE MESA_GLES_VERSION_OVERRIDE ZINK_DESCRIPTORS MESA_NO_ERROR TU_PERF

    case "$ASL_GPU_PROFILE" in
        adreno-turnip-zink)
            export GALLIUM_DRIVER=zink
            export MESA_LOADER_DRIVER_OVERRIDE=zink
            export MESA_VK_WINSYS=x11
            ##export MESA_VK_WSI_DEBUG="sw" # DISABLED FOR HERMES
            export ZINK_DESCRIPTORS=lazy
            export MESA_NO_ERROR=1
            # Do NOT force MESA_GL_VERSION_OVERRIDE / MESA_GLES_VERSION_OVERRIDE.
            # The container Mesa (Mesa 26.x turnip/KGSL) already advertises GL 4.6 /
            # GLES 3.2 from the real device; advertising anything else makes Mesa
            # reject its own shader version query and breaks app feature detection.
            local icd_chroot
            icd_chroot=$(asl_gpu_icd_in_chroot)
            if [ -n "$icd_chroot" ]; then
                export VK_ICD_FILENAMES="$icd_chroot"
                export VK_DRIVER_FILES="$icd_chroot"
            fi
            export MESA_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_GL_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_VK_SHADER_CACHE_DIR="/tmp/.mesa_cache"
            export MESA_SHADER_CACHE_MAX_SIZE="2G"
            
            # GPU-specific TU_DEBUG settings for optimal performance
            case "${ASL_GPU_MODEL:-}" in
                adreno8xx)
                    # Adreno 8xx: Use flushall,syncdraw to avoid post-unlock race condition
                    export TU_DEBUG="flushall,syncdraw,noconform"
                    export TU_PERF="batched"
                    ;;
                adreno7xx)
                    # Adreno 7xx: Optimal settings for 730/740/750
                    export TU_DEBUG="noconform"
                    export TU_PERF="batched"
                    ;;
                adreno660)
                    # Adreno 660 / SDM 888: Hardware tiling bug causes crashes/glitches under full zink Vulkan load
                    export TU_DEBUG="noconform,sysmem"
                    ;;
                adreno6xx)
                    # Adreno 6xx: Conservative settings for older hardware
                    export TU_DEBUG="noconform"
                    ;;
                *)
                    # Fallback: safe default
                    export TU_DEBUG="noconform"
                    ;;
            esac
            ;;
        mali-virgl|generic-virgl|*)
            export GALLIUM_DRIVER=virpipe
            export LIBGL_ALWAYS_SOFTWARE=0
            # virgl_test_server_android cannot bind /tmp under Termux SELinux,
            # so it runs with an explicit socket path inside Termux TMPDIR.
            export VIRGL_TEST_PATH="${VIRGL_TEST_PATH:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}/.virgl_test}"
            # Do NOT force MESA_GL_VERSION_OVERRIDE: advertising a GL version the
            # virgl/ANGLE stack cannot actually back makes Mesa reject its own
            # shading_language_version() and breaks app-side GL feature detection.
            export MESA_VK_WINSYS=x11
            # Vulkan: prefer the Android KGSL turnip build exposed from Termux when it
            # enumerates a real GPU; otherwise fall back to lavapipe software Vulkan.
            local _vk_icd=""
            if [ -n "${VK_ICD_FILENAMES:-}" ] && [ -e "${VK_ICD_FILENAMES}" ]; then
                _vk_icd="$VK_ICD_FILENAMES"
            else
                _vk_icd="/usr/share/vulkan/icd.d/lvp_icd.json"
            fi
            export VK_ICD_FILENAMES="$_vk_icd"
            export VK_DRIVER_FILES="$_vk_icd"
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
    [ -n "${LIBGL_ALWAYS_SOFTWARE:-}" ] && res="${res}export LIBGL_ALWAYS_SOFTWARE=\"${LIBGL_ALWAYS_SOFTWARE}\"\n"
    # VIRGL_TEST_PATH is only meaningful for the virpipe profile. Emitting it while
    # running turnip/zink only confuses users into thinking virgl is in the path.
    if [ "$ASL_GPU_PROFILE" != "adreno-turnip-zink" ]; then
        [ -n "${VIRGL_TEST_PATH:-}" ] && res="${res}export VIRGL_TEST_PATH=\"${VIRGL_TEST_PATH}\"\n"
    fi
    res="${res}export MESA_VK_WINSYS=\"${MESA_VK_WINSYS:-x11}\"\n"
    # [ -n "${MESA_VK_WSI_DEBUG:-}" ] && res="${res}export MESA_VK_WSI_DEBUG=\"sw\"\n"
    if [ -n "$icd_path_in_chroot" ]; then
        res="${res}export VK_ICD_FILENAMES=\"${icd_path_in_chroot}\"\n"
        res="${res}export VK_DRIVER_FILES=\"${icd_path_in_chroot}\"\n"
    elif [ -n "${VK_ICD_FILENAMES:-}" ]; then
        res="${res}export VK_ICD_FILENAMES=\"${VK_ICD_FILENAMES}\"\n"
        res="${res}export VK_DRIVER_FILES=\"${VK_DRIVER_FILES:-${VK_ICD_FILENAMES}}\"\n"
    fi
    [ -n "${TU_DEBUG:-}" ] && res="${res}export TU_DEBUG=\"${TU_DEBUG}\"\n"
    [ -n "${TU_PERF:-}" ] && res="${res}export TU_PERF=\"${TU_PERF}\"\n"
    [ -n "${ZINK_DESCRIPTORS:-}" ] && res="${res}export ZINK_DESCRIPTORS=\"${ZINK_DESCRIPTORS}\"\n"
    [ -n "${MESA_NO_ERROR:-}" ] && res="${res}export MESA_NO_ERROR=\"${MESA_NO_ERROR}\"\n"
    res="${res}export MESA_SHADER_CACHE_DIR=\"${MESA_SHADER_CACHE_DIR:-/tmp/.mesa_cache}\"\n"
    res="${res}export MESA_GL_SHADER_CACHE_DIR=\"${MESA_GL_SHADER_CACHE_DIR:-/tmp/.mesa_cache}\"\n"
    res="${res}export MESA_VK_SHADER_CACHE_DIR=\"${MESA_VK_SHADER_CACHE_DIR:-/tmp/.mesa_cache}\"\n"
    res="${res}export MESA_SHADER_CACHE_MAX_SIZE=\"${MESA_SHADER_CACHE_MAX_SIZE:-1G}\"\n"
    [ -n "${MESA_GL_VERSION_OVERRIDE:-}" ] && res="${res}export MESA_GL_VERSION_OVERRIDE=\"${MESA_GL_VERSION_OVERRIDE}\"\n"
    [ -n "${MESA_GLES_VERSION_OVERRIDE:-}" ] && res="${res}export MESA_GLES_VERSION_OVERRIDE=\"${MESA_GLES_VERSION_OVERRIDE}\"\n"
    # Hardware rendering is mandatory. Mesa honours LIBGL_ALWAYS_SOFTWARE ahead of
    # every driver setting, so an inherited value from a parent shell, a wrapper
    # script or an application launcher silently switches the whole session to
    # llvmpipe. Clear it here so the GPU path below is always the one in effect.
    res="${res}unset LIBGL_ALWAYS_SOFTWARE\n"
    res="${res}unset MESA_LOADER_DRIVER_OVERRIDE_SW MESA_GL_VERSION_OVERRIDE_SW\n"

    local hud_script
    hud_script=$(asl_find_script "hud.sh")
    if [ -f "$hud_script" ]; then
        local hud_exp
        hud_exp=$("$hud_script" env 2>/dev/null || true)
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
    printf 'GPU Model: %s\n' "${ASL_GPU_MODEL:-unknown}"
    printf 'GALLIUM_DRIVER=%s\n' "${GALLIUM_DRIVER:-}"
    printf 'MESA_LOADER_DRIVER_OVERRIDE=%s\n' "${MESA_LOADER_DRIVER_OVERRIDE:-}"
    printf 'MESA_VK_WINSYS=%s\n' "${MESA_VK_WINSYS:-}"
    printf 'TU_DEBUG=%s\n' "${TU_DEBUG:-}"
    printf 'TU_PERF=%s\n' "${TU_PERF:-}"
    printf 'MESA_SHADER_CACHE_MAX_SIZE=%s\n' "${MESA_SHADER_CACHE_MAX_SIZE:-}"
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
        if ! asl_chroot_exec "export DEBIAN_FRONTEND=noninteractive PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; apt-get update -y 2>/dev/null && apt-get install -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' mesa-vulkan-drivers libgl1-mesa-dri vulkan-tools libvulkan1"; then
            echo "[!] GPU driver package installation failed."
            return 1
        fi
        asl_sync_chroot_env 2>/dev/null || true
        echo "[✓] Prebuilt GPU hardware acceleration drivers installed."
    else
        echo "[*] Non-Debian rootfs detected; skipping Debian apt driver package auto-installation."
    fi
}

