#!/bin/bash
# ASL Remote Access - Common functions & shared state

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

CONFIG_DIR="$HOME/.asl"
mkdir -p "$CONFIG_DIR" "$HOME/.ssh" 2>/dev/null || true
chmod 700 "$CONFIG_DIR" "$HOME/.ssh" 2>/dev/null || true
if [ -d "$CONFIG_DIR" ] && [ ! -w "$CONFIG_DIR" ]; then
    su -c "chown $(id -u):$(id -g) '$CONFIG_DIR'" 2>/dev/null || true
fi

PASS_FILE="$CONFIG_DIR/remote_password"

get_password() {
    if [ -f "$PASS_FILE" ]; then
        local stored
        stored=$(cat "$PASS_FILE" 2>/dev/null)
        if [[ "$stored" == *:* ]]; then
            # Salted hash format: salt:hash
            echo "$stored"
        else
            # Legacy plain SHA256 format
            echo "$stored"
        fi
    fi
}

set_password() {
    local new_pass="${1:-0000}"
    if [ -z "$new_pass" ] || [[ "$new_pass" == *$'\n'* || "$new_pass" == *$'\r'* ]]; then
        echo "Error: Password cannot be empty or contain newlines."
        return 1
    fi

    # Reset termux-auth info first so passwd does not prompt for old password
    rm -f "$HOME/.termux_authinfo" 2>/dev/null || true
    if ! printf '%s\n%s\n' "$new_pass" "$new_pass" | passwd >/dev/null 2>&1; then
        echo "Error: Could not update the host password."
        return 1
    fi
    # Store salted hash instead of plain SHA256
    local salt
    salt=$(head -c 16 /dev/urandom | base64 | tr -d '\n' | head -c 16)
    local hash
    hash=$(printf '%s%s' "$salt" "$new_pass" | sha256sum | cut -d' ' -f1)
    printf '%s:%s' "$salt" "$hash" > "$PASS_FILE" || : > "$PASS_FILE"
    chmod 600 "$PASS_FILE"

    # Sync password across Debian chroot if available
    if [ -d "$DEBIANPATH" ] && [ -x "$DEBIANPATH/sbin/chpasswd" ]; then
        if su -c "id -u" >/dev/null 2>&1; then
            su -c "chroot '$DEBIANPATH' /bin/sh -c 'echo \"root:$new_pass\" | /sbin/chpasswd' 2>/dev/null" || true
        fi
    fi

    echo "[✓] ASL All Remote Passwords successfully updated."
}

ensure_host_dns() {
    if [ ! -f /etc/resolv.conf ] || [ ! -s /etc/resolv.conf ]; then
        if su -c "id -u" >/dev/null 2>&1; then
            su -c "mount -o remount,rw / 2>/dev/null && mkdir -p /etc && echo 'nameserver 8.8.8.8' > /etc/resolv.conf && echo 'nameserver 1.1.1.1' >> /etc/resolv.conf" 2>/dev/null || true
        fi
    fi
}

ensure_host_sshd() {
    mkdir -p "$PREFIX/etc/ssh"
    if [ ! -f "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]; then
        ssh-keygen -A >/dev/null 2>&1 || return 1
    fi
    local pass_opts="-o PasswordAuthentication=yes -o KbdInteractiveAuthentication=yes -o AllowTcpForwarding=yes -o GatewayPorts=yes"
    if ! pgrep -x sshd >/dev/null 2>&1 && ! pgrep -f "sshd -p 8022" >/dev/null 2>&1 && ! su -c "pgrep -f sshd" >/dev/null 2>&1; then
        echo "[*] Starting Termux host SSH daemon on port 8022..."
        local termux_user
        termux_user=$(stat -c '%U' "$HOME" 2>/dev/null || echo "u0_a566")
        if [ "$(id -u)" -eq 0 ]; then
            su "$termux_user" -c "export PATH=\"$PREFIX/bin:\$PATH\" HOME=\"$HOME\"; $PREFIX/bin/sshd -p 8022 $pass_opts" || return 1
        else
            "$PREFIX/bin/sshd" -p 8022 $pass_opts 2>/dev/null || return 1
        fi
    fi
    pgrep -x sshd >/dev/null 2>&1 || pgrep -f "sshd -p 8022" >/dev/null 2>&1 || su -c "pgrep -f 'sshd -p 8022'" >/dev/null 2>&1 || return 1
}

password_control() {
    local action="${1:-show}"
    case "$action" in
        set|change)
            local new_p="${2:-}"
            if [ -z "$new_p" ]; then
                echo "Usage: asl remote password set <new_password>"
                return 1
            fi
            set_password "$new_p"
            ;;
        clear|unset|remove)
            rm -f "$PASS_FILE" "$HOME/.termux_authinfo" 2>/dev/null || true
            echo "[✓] Remote password removed; SSH key-based access required."
            ;;
        show|*)
            if [ -n "$(get_password)" ]; then
                echo "A remote password is configured."
            else
                echo "No remote password is configured; key-based access is required."
            fi
            echo "Set a password using: asl remote password set <new_password>"
            ;;
    esac
}
