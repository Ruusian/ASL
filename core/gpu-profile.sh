#!/bin/bash
# Source-only GPU profile selection for SuperKit.

superkit_gpu_detect() {
    SUPERKIT_GPU_PLATFORM=$(getprop ro.board.platform 2>/dev/null || true)
    SUPERKIT_GPU_PLATFORM=${SUPERKIT_GPU_PLATFORM,,}
    SUPERKIT_GPU_PROFILE="generic-virgl"

    case "$SUPERKIT_GPU_PLATFORM" in
        msm*|sm*|qcom*)
            DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
            if [ -d "$DEBIANPATH" ] && su -c "chroot '$DEBIANPATH' /bin/bash -c 'compgen -G /usr/lib/*/dri/zink_dri.so >/dev/null || [ -d /usr/share/vulkan/icd.d ]'" 2>/dev/null; then
                SUPERKIT_GPU_PROFILE="adreno-turnip-zink"
            else
                SUPERKIT_GPU_PROFILE="generic-virgl"
            fi
            ;;
        exynos*|mali*|mt*|dimensity*) SUPERKIT_GPU_PROFILE="mali-virgl" ;;
    esac
}

superkit_gpu_apply() {
    superkit_gpu_detect
    unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE MESA_VK_WINSYS TU_DEBUG

    if pgrep -x virgl_test_server_android >/dev/null 2>&1 || pgrep -f virgl_test_server >/dev/null 2>&1; then
        export GALLIUM_DRIVER=virpipe
        export MESA_GL_VERSION_OVERRIDE=4.0
        export MESA_VK_WINSYS=x11
        return 0
    fi

    case "$SUPERKIT_GPU_PROFILE" in
        adreno-turnip-zink)
            export GALLIUM_DRIVER=zink
            export MESA_LOADER_DRIVER_OVERRIDE=zink
            export MESA_VK_WINSYS=x11
            case "$SUPERKIT_GPU_PLATFORM" in
                sm8450|sm8475|sm7475) export TU_DEBUG=noconform ;;
            esac
            ;;
        mali-virgl|generic-virgl)
            export GALLIUM_DRIVER=virpipe
            export MESA_GL_VERSION_OVERRIDE=4.0
            export MESA_VK_WINSYS=x11
            ;;
    esac
}

superkit_gpu_report() {
    superkit_gpu_apply
    printf 'Profile: %s\n' "$SUPERKIT_GPU_PROFILE"
    printf 'Platform: %s\n' "${SUPERKIT_GPU_PLATFORM:-unknown}"
    printf 'GALLIUM_DRIVER=%s\n' "${GALLIUM_DRIVER:-}"
    printf 'MESA_LOADER_DRIVER_OVERRIDE=%s\n' "${MESA_LOADER_DRIVER_OVERRIDE:-}"
    printf 'MESA_VK_WINSYS=%s\n' "${MESA_VK_WINSYS:-}"
    printf 'TU_DEBUG=%s\n' "${TU_DEBUG:-}"
}
