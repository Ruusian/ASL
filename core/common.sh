#!/bin/bash
# Android Subsystem for Linux (ASL): Shared Environment & Common Utilities
# Consolidates path checks, mount verification, color definitions, and logging.

MODE_CONFIG="$PREFIX/etc/asl_exec_mode"

asl_detect_mode() {
    if [ -n "${ASL_EXEC_MODE:-}" ]; then
        echo "$ASL_EXEC_MODE"
        return
    fi
    if [ -f "$MODE_CONFIG" ]; then
        local saved_mode=""
        read -r saved_mode < "$MODE_CONFIG" 2>/dev/null || true
        saved_mode="${saved_mode//[[:space:]]/}"
        if [ -n "$saved_mode" ]; then
            echo "$saved_mode"
            return
        fi
    fi

    if su -c "id -u" >/dev/null 2>&1; then
        echo "root"
    elif command -v rish >/dev/null 2>&1 && rish -c "id" >/dev/null 2>&1; then
        echo "shizuku"
    elif command -v shizuku-exec >/dev/null 2>&1; then
        echo "shizuku"
    else
        echo "proot"
    fi
}

ASL_EXEC_MODE=$(asl_detect_mode)
export ASL_EXEC_MODE

# Default DEBIANPATH fallback based on execution mode
if [ -z "${DEBIANPATH:-}" ] || [ "$DEBIANPATH" = "/data/local/tmp/chrootDebian" ]; then
    if [ "$ASL_EXEC_MODE" = "proot" ]; then
        DEBIANPATH="$HOME/.asl/chrootDebian"
    else
        DEBIANPATH="/data/local/tmp/chrootDebian"
    fi
fi
export DEBIANPATH

asl_exec() {
    local cmd="$1"
    case "$ASL_EXEC_MODE" in
        root)
            if [[ "$cmd" == *$'\n'* ]]; then
                local b64
                b64=$(printf '%s' "$cmd" | base64 | tr -d '\n')
                su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; printf '%s' '$b64' | base64 -d | bash"
            else
                su -c "$cmd"
            fi
            ;;
        shizuku)
            if [[ "$cmd" == *$'\n'* ]]; then
                local b64
                b64=$(printf '%s' "$cmd" | base64 | tr -d '\n')
                if command -v rish >/dev/null 2>&1; then
                    rish -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; printf '%s' '$b64' | base64 -d | bash"
                elif command -v shizuku-exec >/dev/null 2>&1; then
                    shizuku-exec "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; printf '%s' '$b64' | base64 -d | bash"
                else
                    bash -c "$cmd"
                fi
            else
                if command -v rish >/dev/null 2>&1; then
                    rish -c "$cmd"
                elif command -v shizuku-exec >/dev/null 2>&1; then
                    shizuku-exec "$cmd"
                else
                    bash -c "$cmd"
                fi
            fi
            ;;
        proot|*)
            bash -c "$cmd"
            ;;
    esac
}

asl_chroot_exec() {
    local cmd="$1"
    case "$ASL_EXEC_MODE" in
        root)
            if [[ "$cmd" == *$'\n'* ]] || [[ "$cmd" == *"'"* ]]; then
                local b64
                b64=$(printf '%s' "$cmd" | base64 | tr -d '\n')
                su -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; chroot '$DEBIANPATH' /bin/bash -c \"printf '%s' '$b64' | /data/data/com.termux/files/usr/bin/base64 -d | bash\""
            else
                su -c "chroot '$DEBIANPATH' /bin/bash -c '$cmd'"
            fi
            ;;
        shizuku)
            if [[ "$cmd" == *$'\n'* ]] || [[ "$cmd" == *"'"* ]]; then
                local b64
                b64=$(printf '%s' "$cmd" | base64 | tr -d '\n')
                rish -c "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; chroot '$DEBIANPATH' /bin/bash -c \"printf '%s' '$b64' | /data/data/com.termux/files/usr/bin/base64 -d | bash\"" 2>/dev/null || \
                proot-distro login asl-debian -- /bin/bash -c "printf '%s' '$b64' | base64 -d | bash"
            else
                rish -c "chroot '$DEBIANPATH' /bin/bash -c '$cmd'" 2>/dev/null || \
                proot-distro login asl-debian -- /bin/bash -c "$cmd"
            fi
            ;;
        proot|*)
            if [[ "$cmd" == *$'\n'* ]] || [[ "$cmd" == *"'"* ]]; then
                local b64
                b64=$(printf '%s' "$cmd" | base64 | tr -d '\n')
                proot-distro login asl-debian -- /bin/bash -c "printf '%s' '$b64' | base64 -d | bash" 2>/dev/null || \
                proot --link2symlink -0 -r "$DEBIANPATH" -b /dev -b /proc -b /sys -b /data/data/com.termux/files/home /bin/bash -c "printf '%s' '$b64' | base64 -d | bash"
            else
                proot-distro login asl-debian -- /bin/bash -c "$cmd" 2>/dev/null || \
                proot --link2symlink -0 -r "$DEBIANPATH" -b /dev -b /proc -b /sys -b /data/data/com.termux/files/home /bin/bash -c "$cmd"
            fi
            ;;
    esac
}

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "$ASL_EXEC_MODE" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian or a valid directory" >&2
    exit 2
fi

if [ "${NO_COLOR:-}" = "" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_CYAN=$'\033[36m'
    C_BLUE=$'\033[34m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_PURPLE=$'\033[35m'
    C_DIM=$'\033[2m'
    C_SHADOW=$'\033[90m'
else
    C_RESET= C_BOLD= C_CYAN= C_BLUE= C_GREEN= C_YELLOW= C_RED= C_PURPLE= C_DIM= C_SHADOW=
fi
export C_RESET C_BOLD C_CYAN C_BLUE C_GREEN C_YELLOW C_RED C_PURPLE C_DIM C_SHADOW

is_mounted() {
    local target="${1:-$DEBIANPATH}"
    (grep -q -F " $target/proc " /proc/mounts 2>/dev/null || grep -q -F " $target " /proc/mounts 2>/dev/null) && return 0
    case "$ASL_EXEC_MODE" in
        root)
            su -c "grep -q -F ' $target/proc ' /proc/mounts" 2>/dev/null || \
            su -c "grep -q -F ' $target ' /proc/mounts" 2>/dev/null
            ;;
        shizuku)
            rish -c "grep -q -F ' $target/proc ' /proc/mounts" 2>/dev/null || \
            grep -q -F " $target/proc " /proc/mounts 2>/dev/null || \
            proot-distro login asl-debian -- true 2>/dev/null
            ;;
        proot|*)
            pgrep -f "proot.*(asl-debian|$target)" >/dev/null 2>&1
            ;;
    esac
}

status_label() {
    local state="$1"
    case "$state" in
        ACTIVE|RUNNING|READY|ON) printf '%s[%s]%s' "$C_GREEN$C_BOLD" "$state" "$C_RESET" ;;
        INACTIVE|STOPPED|OFF) printf '%s[%s]%s' "$C_DIM" "$state" "$C_RESET" ;;
        *) printf '%s[%s]%s' "$C_YELLOW$C_BOLD" "$state" "$C_RESET" ;;
    esac
}

asl_log_info()  { printf '%s[*] %s%s\n' "$C_CYAN$C_BOLD" "$*" "$C_RESET"; }
asl_log_ok()    { printf '%s[✓] %s%s\n' "$C_GREEN$C_BOLD" "$*" "$C_RESET"; }
asl_log_warn()  { printf '%s[!] %s%s\n' "$C_YELLOW$C_BOLD" "$*" "$C_RESET"; }
asl_log_error() { printf '%s[✗] %s%s\n' "$C_RED$C_BOLD" "$*" "$C_RESET" >&2; }
asl_log_hint()  { printf '%s    💡 Hint: %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
