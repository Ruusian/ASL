#!/bin/bash
# Android Subsystem for Linux (ASL): Shared Environment & Common Utilities
# Consolidates path checks, mount verification, color definitions, and logging.

MODE_CONFIG="$PREFIX/etc/asl_exec_mode"

asl_detect_mode() {
    if [ -n "${ASL_EXEC_MODE:-}" ]; then
        echo "$ASL_EXEC_MODE"
        return
    fi
    if [ -f /etc/debian_version ] && [ ! -d "/data/local/tmp/chrootDebian" ]; then
        echo "direct"
        return
    fi
    echo "root"
}

ASL_EXEC_MODE=$(asl_detect_mode)
export ASL_EXEC_MODE

# Self-contained mode: when running inside the Debian chroot, commands
# target the current rootfs directly instead of re-entering the chroot.
if [ "${ASL_CHROOT_SELF:-0}" = "1" ] || [ -f /etc/debian_version -a ! -d "/data/local/tmp/chrootDebian" ]; then
    ASL_EXEC_MODE="direct"
    DEBIANPATH="/"
fi
export ASL_EXEC_MODE DEBIANPATH

# Default DEBIANPATH fallback
if [ -z "${DEBIANPATH:-}" ] || [ "$DEBIANPATH" = "/data/local/tmp/chrootDebian" ]; then
    if [ "$ASL_EXEC_MODE" = "direct" ]; then
        DEBIANPATH="/"
    else
        DEBIANPATH="/data/local/tmp/chrootDebian"
    fi
fi
export DEBIANPATH

asl_exec() {
    local cmd="$1"
    case "$ASL_EXEC_MODE" in
        direct)
            bash -c "$cmd"
            ;;
        root|*)
            local enc_cmd
            enc_cmd=$(printf '%s' "$cmd" | base64 | tr -d '\n')
            su -c "ulimit -n 2048 2>/dev/null || true; export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/data/data/com.termux/files/usr/bin:\$PATH; printf '%s' '$enc_cmd' | base64 -d | bash"
            ;;
    esac
}

asl_chroot_exec() {
    local cmd="$1"
    case "$ASL_EXEC_MODE" in
        direct)
            bash -c "$cmd"
            ;;
        root|*)
            local enc_cmd
            enc_cmd=$(printf '%s' "$cmd" | base64 | tr -d '\n')
            su -c "ulimit -n 2048 2>/dev/null || true; printf '%s' '$enc_cmd' | base64 -d | chroot '$DEBIANPATH' /usr/bin/env -i HOME=/root USER=root LOGNAME=root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TERM=${TERM:-xterm-256color} LANG=C.UTF-8 LC_ALL=C.UTF-8 TMPDIR=/tmp /bin/bash -s"
            ;;
    esac
}

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "$DEBIANPATH" != "$HOME/.asl/chrootDebian" ] && [ "$ASL_EXEC_MODE" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Warning: Custom DEBIANPATH $DEBIANPATH does not exist yet" >&2
fi

# Refuse unsafe/non-standard DEBIANPATH in root mode (centralized guard,
# replaces the copy-pasted block duplicated across the core scripts).
asl_require_default_debianpath() {
    if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
        echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian" >&2
        exit 2
    fi
}

# Shared state directory
ASL_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/asl"
asl_ensure_state_dir() {
    mkdir -p "$ASL_STATE_DIR" 2>/dev/null || return 1
    chmod 700 "$ASL_STATE_DIR" 2>/dev/null || true
}

# Advisory lock to serialize chroot-mutating operations across processes.
ASL_LOCK_DIR="${HOME:-/data/data/com.termux/files/home}/.asl"
asl_acquire_lock() {
    mkdir -p "$ASL_LOCK_DIR" 2>/dev/null || return 0
    local lock="$ASL_LOCK_DIR/.chroot.lock" tries=0 holder
    while :; do
        if mkdir "$lock" 2>/dev/null; then
            echo "$$" > "$lock/pid" 2>/dev/null
            return 0
        fi
        holder=$(cat "$lock/pid" 2>/dev/null)
        if [ -n "$holder" ]; then
            if ! kill -0 "$holder" 2>/dev/null; then
                rm -rf "$lock" 2>/dev/null
                continue
            fi
        else
            if [ "$tries" -gt 4 ]; then
                rm -rf "$lock" 2>/dev/null
                continue
            fi
        fi
        tries=$((tries + 1))
        [ "$tries" -ge 60 ] && return 1
        sleep 0.5
    done
}
asl_release_lock() {
    local lock="$ASL_LOCK_DIR/.chroot.lock" holder
    holder=$(cat "$lock/pid" 2>/dev/null)
    if [ "$holder" = "$$" ] || [ -z "$holder" ]; then
        rm -rf "$lock" 2>/dev/null
    fi
}

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
    C_RESET='' C_BOLD='' C_CYAN='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_PURPLE='' C_DIM='' C_SHADOW=''
fi
export C_RESET C_BOLD C_CYAN C_BLUE C_GREEN C_YELLOW C_RED C_PURPLE C_DIM C_SHADOW

is_mounted() {
    if [ "${ASL_CHROOT_SELF:-0}" = "1" ] || [ "${ASL_EXEC_MODE:-}" = "direct" ]; then
        return 0
    fi
    local target="${1:-$DEBIANPATH}"
    if [ "$target" = "/" ]; then
        return 0
    fi
    (awk -v target="$target" '$2 == target "/dev" || $2 == target "/proc" || $2 == target {found=1; exit} END {exit !found}' /proc/mounts 2>/dev/null) && return 0
    local enc_target
    enc_target=$(printf '%s' "$target" | base64 | tr -d '\n')
    su -c "target=\$(echo $enc_target | base64 -d); awk -v target=\"\$target\" '\$2 == target \"/dev\" || \$2 == target \"/proc\" || \$2 == target {found=1; exit} END {exit !found}' /proc/mounts" 2>/dev/null
}

status_label() {
    local state="$1"
    case "$state" in
        ACTIVE|RUNNING|READY|ON|ENABLED) printf '%s[%s]%s' "$C_GREEN$C_BOLD" "$state" "$C_RESET" ;;
        INACTIVE|STOPPED|OFF|DISABLED) printf '%s[%s]%s' "$C_DIM" "$state" "$C_RESET" ;;
        *) printf '%s[%s]%s' "$C_YELLOW$C_BOLD" "$state" "$C_RESET" ;;
    esac
}

asl_log_info()  { printf '%s[*] %s%s\n' "$C_CYAN$C_BOLD" "$*" "$C_RESET"; }
asl_log_ok()    { printf '%s[✓] %s%s\n' "$C_GREEN$C_BOLD" "$*" "$C_RESET"; }
asl_log_warn()  { printf '%s[!] %s%s\n' "$C_YELLOW$C_BOLD" "$*" "$C_RESET"; }
asl_log_error() { printf '%s[✗] %s%s\n' "$C_RED$C_BOLD" "$*" "$C_RESET" >&2; }
asl_log_hint()  { printf '%s    💡 Hint: %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }

# Auto-detect performance CPU core affinity mask (all CPU cores for maximum performance)
asl_get_perf_cpu_mask() {
    local ncpu
    ncpu=$(nproc 2>/dev/null || echo 8)
    printf '0-%d' "$((ncpu - 1))"
}

asl_host_ip() {
    local ip
    ip=$(ip -o -4 addr show 2>/dev/null | awk '$2 != "lo" {sub(/\/.*/, "", $4); print $4; exit}')
    [ -n "$ip" ] || ip=$(ifconfig 2>/dev/null | awk '/inet / && !/127.0.0.1/ {sub(/addr:/, ""); print $2; exit}')
    printf '%s' "${ip:-127.0.0.1}"
}
lan_host_ip() { asl_host_ip "$@"; }

asl_is_sshd_running() {
    pgrep -f "sshd" >/dev/null 2>&1 || su -c "pgrep -f sshd" >/dev/null 2>&1 || asl_exec "pgrep -f sshd" >/dev/null 2>&1
}

asl_is_omniroute_running() {
    pgrep -f "omniroute" >/dev/null 2>&1 || su -c "pgrep -f omniroute" >/dev/null 2>&1 || (timeout 1 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/20128') 2>/dev/null
}

batt_temp_c() {
    local raw p
    for p in /sys/class/power_supply/battery/temp /sys/class/power_supply/bms/temp /sys/class/thermal/thermal_zone81/temp /sys/class/thermal/thermal_zone80/temp; do
        raw=$(cat "$p" 2>/dev/null | tr -d '[:space:]')
        if [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -gt 0 ]; then
            if [ "$raw" -gt 1000 ]; then printf '%d' "$((raw / 1000))"; return
            elif [ "$raw" -gt 100 ]; then printf '%d' "$((raw / 10))"; return
            else printf '%d' "$raw"; return; fi
        fi
    done
    (timeout 1 dumpsys battery 2>/dev/null || timeout 1 asl_exec "dumpsys battery" 2>/dev/null) | awk '/temperature:/ {printf "%d", int($2 / 10); exit}'
}
asl_batt_temp_c() { batt_temp_c "$@"; }

asl_cpu_temp_c() {
    local cache_f="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}/.asl_cpu_zones"
    if [ -z "${ASL_CPU_ZONES:-}" ]; then
        if [ -f "$cache_f" ]; then
            ASL_CPU_ZONES=$(cat "$cache_f" 2>/dev/null)
        fi
        if [ -z "${ASL_CPU_ZONES:-}" ]; then
            ASL_CPU_ZONES=$(grep -l -i -E "cpu|soc|tsens|ap-thermal|mtk|exynos|qcom" /sys/class/thermal/thermal_zone*/type 2>/dev/null | sed "s/type$/temp/" | tr "\n" " ")
            [ -n "$ASL_CPU_ZONES" ] && printf "%s" "$ASL_CPU_ZONES" > "$cache_f" 2>/dev/null || true
        fi
    fi
    local temp_val=""
    if [ -n "$ASL_CPU_ZONES" ]; then
        temp_val=$(cat $ASL_CPU_ZONES 2>/dev/null | awk '
            {
                t = $1 + 0;
                if (t > 1000) t = int(t / 1000);
                if (t >= 1 && t <= 115 && t > max) max = t;
            }
            END { if (max > 0) print max }
        ')
    fi
    if [ -z "$temp_val" ]; then
        temp_val=$( (timeout 1 dumpsys hardware_properties 2>/dev/null || timeout 1 asl_exec "dumpsys hardware_properties" 2>/dev/null) | awk '/CPU temperatures:/ {match($0, /[0-9]+\.?[0-9]*/); if (RSTART) print int(substr($0, RSTART, RLENGTH))}' )
    fi
    printf '%s' "$temp_val"
}

asl_find_script() {
    local s="$1"
    local candidates=(
        "${SCRIPT_DIR:-}/core/$s"
        "${SCRIPT_DIR:-}/desktop/$s"
        "${SCRIPT_DIR:-}/desktop/remote/$s"
        "${SCRIPT_DIR:-}/tools/$s"
        "${SCRIPT_DIR:-}/$s"
        "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/$s"
        "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/desktop/$s"
        "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/desktop/remote/$s"
        "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/tools/$s"
        "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/$s"
        "${HOME:-/data/data/com.termux/files/home}/ASL/core/$s"
        "${HOME:-/data/data/com.termux/files/home}/ASL/desktop/$s"
        "${HOME:-/data/data/com.termux/files/home}/ASL/desktop/remote/$s"
        "${HOME:-/data/data/com.termux/files/home}/ASL/tools/$s"
        "${HOME:-/data/data/com.termux/files/home}/ASL/$s"
    )
    for c in "${candidates[@]}"; do
        if [ -f "$c" ]; then
            echo "$c"
            return 0
        fi
    done
    echo "${SCRIPT_DIR:-}/core/$s"
}

asl_ensure_chroot_mounted() {
    if is_mounted "${1:-$DEBIANPATH}"; then
        return 0
    fi
    local mount_script
    mount_script=$(asl_find_script "mount-chroot.sh")
    if [ -f "$mount_script" ]; then
        bash "$mount_script" || return 1
    else
        return 1
    fi
}
ensure_chroot_mounted() {
    asl_ensure_chroot_mounted "$@"
}


