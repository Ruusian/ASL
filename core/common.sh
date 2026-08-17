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
                local tmp_dir="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
                mkdir -p "$tmp_dir" 2>/dev/null || true
                local tmpf="$tmp_dir/.asl_cmd_$$.sh"
                printf '%s\n' "$cmd" > "$tmpf"
                chmod 755 "$tmpf" 2>/dev/null || true
                su -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/data/data/com.termux/files/usr/bin:\$PATH; bash '$tmpf'"
                local res=$?
                rm -f "$tmpf" 2>/dev/null || true
                return $res
            else
                su -c "$cmd"
            fi
            ;;
        shizuku)
            if [[ "$cmd" == *$'\n'* ]]; then
                local tmp_dir="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
                mkdir -p "$tmp_dir" 2>/dev/null || true
                local tmpf="$tmp_dir/.asl_cmd_$$.sh"
                printf '%s\n' "$cmd" > "$tmpf"
                chmod 755 "$tmpf" 2>/dev/null || true
                if command -v rish >/dev/null 2>&1; then
                    rish -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/data/data/com.termux/files/usr/bin:\$PATH; bash '$tmpf'"
                elif command -v shizuku-exec >/dev/null 2>&1; then
                    shizuku-exec "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/data/data/com.termux/files/usr/bin:\$PATH; bash '$tmpf'"
                else
                    bash "$tmpf"
                fi
                local res=$?
                rm -f "$tmpf" 2>/dev/null || true
                return $res
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
                local tmpf="$DEBIANPATH/tmp/.asl_chroot_cmd_$$.sh"
                printf '%s\n' "$cmd" > "$tmpf" 2>/dev/null || asl_exec "cat << 'ASLEOF' > '$tmpf'
$cmd
ASLEOF"
                chmod 755 "$tmpf" 2>/dev/null || asl_exec "chmod 755 '$tmpf'"
                su -c "chroot '$DEBIANPATH' /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash /tmp/.asl_chroot_cmd_$$.sh"
                local res=$?
                rm -f "$tmpf" 2>/dev/null || asl_exec "rm -f '$tmpf'"
                return $res
            else
                su -c "chroot '$DEBIANPATH' /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c '$cmd'"
            fi
            ;;
        shizuku)
            if [[ "$cmd" == *$'\n'* ]] || [[ "$cmd" == *"'"* ]]; then
                local tmpf="$DEBIANPATH/tmp/.asl_chroot_cmd_$$.sh"
                printf '%s\n' "$cmd" > "$tmpf" 2>/dev/null || true
                chmod 755 "$tmpf" 2>/dev/null || true
                rish -c "chroot '$DEBIANPATH' /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash /tmp/.asl_chroot_cmd_$$.sh" 2>/dev/null || \
                proot-distro login asl-debian -- /bin/bash /tmp/.asl_chroot_cmd_$$.sh
                local res=$?
                rm -f "$tmpf" 2>/dev/null || true
                return $res
            else
                rish -c "chroot '$DEBIANPATH' /bin/bash -c '$cmd'" 2>/dev/null || \
                proot-distro login asl-debian -- /bin/bash -c "$cmd"
            fi
            ;;
        proot|*)
            if [[ "$cmd" == *$'\n'* ]] || [[ "$cmd" == *"'"* ]]; then
                local tmpf="$DEBIANPATH/tmp/.asl_chroot_cmd_$$.sh"
                printf '%s\n' "$cmd" > "$tmpf" 2>/dev/null || true
                chmod 755 "$tmpf" 2>/dev/null || true
                proot-distro login asl-debian -- /bin/bash /tmp/.asl_chroot_cmd_$$.sh 2>/dev/null || \
                proot --link2symlink -0 -r "$DEBIANPATH" -b /dev -b /proc -b /sys -b /data/data/com.termux/files/home /bin/bash /tmp/.asl_chroot_cmd_$$.sh
                local res=$?
                rm -f "$tmpf" 2>/dev/null || true
                return $res
            else
                proot-distro login asl-debian -- /bin/bash -c "$cmd" 2>/dev/null || \
                proot --link2symlink -0 -r "$DEBIANPATH" -b /dev -b /proc -b /sys -b /data/data/com.termux/files/home /bin/bash -c "$cmd"
            fi
            ;;
    esac
}

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "$DEBIANPATH" != "$HOME/.asl/chrootDebian" ] && [ "$ASL_EXEC_MODE" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Warning: Custom DEBIANPATH $DEBIANPATH does not exist yet" >&2
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
