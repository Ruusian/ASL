#!/bin/bash
# Android Subsystem for Linux (ASL): Path Translation Utility (wslpath equivalent)
# Translates paths between Android host (Termux/sdcard) and ASL Linux container.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
elif [ -f "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh" ]; then
    source "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh"
elif [ -f "$HOME/ASL/core/common.sh" ]; then
    source "$HOME/ASL/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"

show_help() {
    echo "ASL Path Translation Utility (aslpath)"
    echo "Usage: aslpath [OPTIONS] <path>"
    echo ""
    echo "Options:"
    echo "  -u, --unix       Convert host path to container path (/sdcard/foo -> /mnt/sdcard/foo or /sdcard/foo)"
    echo "  -a, --android    Convert container path to host path (/sdcard/foo -> /storage/emulated/0/foo)"
    echo "  -c, --chroot     Convert relative container path to host chroot path (/etc -> /data/local/tmp/chrootDebian/etc)"
    echo "  -m, --mount      Show mount points for Android storage inside container"
    echo "  -h, --help       Show this help message"
}

asl_path_convert() {
    local mode="unix"
    local input_path=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -u|--unix) mode="unix"; shift ;;
            -a|--android|-w|--windows) mode="android"; shift ;;
            -c|--chroot) mode="chroot"; shift ;;
            -m|--mount) mode="mount"; shift ;;
            -h|--help) show_help; return 0 ;;
            *) input_path="$1"; shift ;;
        esac
    done

    if [ "$mode" = "mount" ]; then
        echo "ASL Storage Mount Points:"
        echo "  /sdcard                    -> /storage/emulated/0"
        echo "  /storage/emulated/0        -> /storage/emulated/0"
        echo "  /termux-home               -> /data/data/com.termux/files/home"
        echo "  /termux                    -> /data/data/com.termux"
        echo "  /data/data/com.termux      -> /data/data/com.termux"
        echo "  /tmp                       -> /data/data/com.termux/files/usr/tmp"
        return 0
    fi

    if [ -z "$input_path" ]; then
        show_help
        return 1
    fi

    # Normalize input path (strip trailing slashes, expand ~)
    input_path="${input_path%/}"
    input_path="${input_path/#\~/$HOME}"

    case "$mode" in
        unix)
            # Host -> Container path conversion
            if [[ "$input_path" == "/storage/emulated/0"* ]]; then
                echo "${input_path/#\/storage\/emulated\/0//sdcard}"
            elif [[ "$input_path" == "/sdcard"* ]]; then
                echo "$input_path"
            elif [[ "$input_path" == "/data/data/com.termux/files/home"* ]]; then
                echo "${input_path/#\/data\/data\/com.termux\/files\/home//termux-home}"
            elif [[ "$input_path" == "/data/data/com.termux/files/usr/tmp"* ]]; then
                echo "${input_path/#\/data\/data\/com.termux\/files\/usr\/tmp//tmp}"
            elif [ "$DEBIANPATH" != "/" ] && [[ "$input_path" == "$DEBIANPATH"* ]]; then
                local rel="${input_path#$DEBIANPATH}"
                [ -z "$rel" ] && rel="/"
                [ "${rel:0:1}" != "/" ] && rel="/$rel"
                echo "$rel"
            else
                echo "$input_path"
            fi
            ;;
        android)
            # Container -> Host path conversion
            if [[ "$input_path" == "/sdcard"* ]]; then
                echo "${input_path/#\/sdcard//storage/emulated/0}"
            elif [[ "$input_path" == "/mnt/sdcard"* ]]; then
                echo "${input_path/#\/mnt\/sdcard//storage/emulated/0}"
            elif [[ "$input_path" == "/termux-home"* ]]; then
                echo "${input_path/#\/termux-home//data/data/com.termux/files/home}"
            elif [[ "$input_path" == "/termux/home"* ]]; then
                echo "${input_path/#\/termux\/home//data/data/com.termux/files/home}"
            elif [[ "$input_path" == "/termux/files/home"* ]]; then
                echo "${input_path/#\/termux\/files\/home//data/data/com.termux/files/home}"
            elif [[ "$input_path" == "/termux"* ]]; then
                echo "${input_path/#\/termux//data/data/com.termux}"
            elif [[ "$input_path" == "/tmp"* ]]; then
                echo "${input_path/#\/tmp//data/data/com.termux/files/usr/tmp}"
            elif [[ "$input_path" == "/"* ]]; then
                if [ "$DEBIANPATH" = "/" ]; then
                    echo "$input_path"
                else
                    echo "$DEBIANPATH$input_path"
                fi
            else
                echo "/storage/emulated/0/$input_path"
            fi
            ;;
        chroot)
            # Container path -> Host chroot path
            if [ "$DEBIANPATH" = "/" ]; then
                [ "${input_path:0:1}" = "/" ] && echo "$input_path" || echo "/$input_path"
            elif [[ "$input_path" == "$DEBIANPATH"* ]]; then
                echo "$input_path"
            else
                local clean_p="${input_path#/}"
                echo "$DEBIANPATH/$clean_p"
            fi
            ;;
    esac
}

asl_path_convert "$@"
