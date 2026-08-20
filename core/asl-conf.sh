#!/bin/bash
# Android Subsystem for Linux (ASL): Declarative Configuration Manager (/etc/asl.conf)
# Manages system configuration settings for ASL container, boot behavior, mounts, and interop.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
CONF_FILE="$DEBIANPATH/etc/asl.conf"
HOST_CONF_FILE="${PREFIX:-/data/data/com.termux/files/usr}/etc/asl.conf"

init_default_config() {
    local target="${1:-$CONF_FILE}"
    local target_dir="$(dirname "$target")"
    mkdir -p "$target_dir" 2>/dev/null || asl_exec "mkdir -p '$target_dir'" 2>/dev/null || true

    local default_content="# Android Subsystem for Linux (ASL) System Configuration
# File location: /etc/asl.conf (inside container) or \$PREFIX/etc/asl.conf

[boot]
systemd = false
autostart = true
default_user = root

[automount]
enabled = true
mount_sdcard = true
mount_termux = true
mount_dev = true

[interop]
enabled = true
aslenv = DISPLAY,PULSE_SERVER,TERMUX_VERSION
append_host_path = true

[network]
hostname = android-asl
generate_hosts = true

[gpu]
profile = turnip-zink
hud = off
"
    if [ -d "$DEBIANPATH" ]; then
        asl_chroot_exec "
            if [ ! -f /etc/asl.conf ]; then
                cat << 'ASLCONF_EOF' > /etc/asl.conf
$default_content
ASLCONF_EOF
            fi
        " 2>/dev/null || true
    fi
}

get_config_value() {
    local section="$1"
    local key="$2"
    local default_val="${3:-}"
    local file="$CONF_FILE"

    [ -f "$file" ] || file="$HOST_CONF_FILE"
    if [ ! -f "$file" ]; then
        echo "$default_val"
        return 0
    fi

    local val
    val=$(python3 -c "
import configparser, sys
config = configparser.ConfigParser()
try:
    config.read('$file')
    if '$section' in config and '$key' in config['$section']:
        print(config['$section']['$key'])
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$val" ]; then
        echo "$val"
    else
        echo "$default_val"
    fi
}

set_config_value() {
    local section="$1"
    local key="$2"
    local val="$3"

    init_default_config

    local target_file="$CONF_FILE"
    if [ ! -d "$(dirname "$CONF_FILE")" ]; then
        target_file="$HOST_CONF_FILE"
    fi

    mkdir -p "$(dirname "$target_file")" 2>/dev/null || true

    if python3 -c "
import configparser, os
conf_file = '$target_file'
config = configparser.ConfigParser()
if os.path.exists(conf_file):
    config.read(conf_file)
if '$section' not in config:
    config['$section'] = {}
config['$section']['$key'] = '$val'
with open(conf_file, 'w') as f:
    config.write(f)
" 2>/dev/null; then
        return 0
    fi

    asl_exec "
python3 -c '
import configparser, os
conf_file = \"$target_file\"
config = configparser.ConfigParser()
if os.path.exists(conf_file):
    config.read(conf_file)
if \"$section\" not in config:
    config[\"$section\"] = {}
config[\"$section\"][\"$key\"] = \"$val\"
with open(conf_file, \"w\") as f:
    config.write(f)
'
" 2>/dev/null || true
}

show_config() {
    echo "=== ASL Declarative Configuration (/etc/asl.conf) ==="
    if asl_chroot_exec "test -f /etc/asl.conf" 2>/dev/null; then
        asl_chroot_exec "cat /etc/asl.conf"
    elif [ -f "$HOST_CONF_FILE" ]; then
        cat "$HOST_CONF_FILE"
    else
        echo "[!] No /etc/asl.conf present; initializing defaults..."
        init_default_config
        asl_chroot_exec "cat /etc/asl.conf" 2>/dev/null || echo "[!] Default created."
    fi
}

case "${1:-show}" in
    init)
        init_default_config
        echo "[✓] ASL system configuration initialized at /etc/asl.conf"
        ;;
    get)
        get_config_value "${2:-boot}" "${3:-autostart}" "${4:-}"
        ;;
    set)
        if [ $# -lt 4 ]; then
            echo "Usage: asl config set <section> <key> <value>"
            exit 1
        fi
        set_config_value "$2" "$3" "$4"
        echo "[✓] Config updated: [$2] $3 = $4"
        ;;
    show|status|list)
        show_config
        ;;
    *)
        echo "Usage: asl config [show|init|get <sec> <key>|set <sec> <key> <val>]"
        ;;
esac
