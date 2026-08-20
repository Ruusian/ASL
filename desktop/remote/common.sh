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
    local new_pass="${1:-}"
    if [ -z "$new_pass" ] || [[ "$new_pass" == *$'\n'* || "$new_pass" == *$'\r'* ]]; then
        echo "Error: Password cannot be empty or contain newlines."
        return 1
    fi
    
    # Validate password strength
    if [ ${#new_pass} -lt 8 ]; then
        echo "Error: Password must be at least 8 characters."
        return 1
    fi
    
    if ! printf '%s\n%s\n' "$new_pass" "$new_pass" | passwd >/dev/null 2>&1; then
        echo "Error: Could not update the host password."
        return 1
    fi
    if is_mounted; then
        local pass_b64
        pass_b64=$(printf '%s' "$new_pass" | base64 | tr -d '\n')
        if ! asl_exec "pass=\$(printf '%s' '$pass_b64' | base64 -d); printf '%s\n%s\n' \"\$pass\" \"\$pass\" | passwd >/dev/null 2>&1"; then
            echo "Error: Host password changed, but the chroot password update failed."
            return 1
        fi
    fi
    # Store salted hash instead of plain SHA256
    local salt
    salt=$(head -c 16 /dev/urandom | base64 | tr -d '\n' | head -c 16)
    local hash
    hash=$(printf '%s%s' "$salt" "$new_pass" | sha256sum | cut -d' ' -f1)
    printf '%s:%s' "$salt" "$hash" > "$PASS_FILE" || : > "$PASS_FILE"
    chmod 600 "$PASS_FILE"
    echo "[✓] ASL Remote SSH password updated."
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
    local pass_opts="-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no"
    if [ -s "$PASS_FILE" ]; then
        pass_opts="-o PasswordAuthentication=yes -o KbdInteractiveAuthentication=yes"
    fi
    if ! pgrep -f "sshd -p 8022" >/dev/null 2>&1 && ! su -c "pgrep -f 'sshd -p 8022'" >/dev/null 2>&1; then
        echo "[*] Starting Termux host SSH daemon on port 8022..."
        sshd -p 8022 $pass_opts 2>/dev/null || return 1
    fi
    pgrep -f "sshd -p 8022" >/dev/null 2>&1 || su -c "pgrep -f 'sshd -p 8022'" >/dev/null 2>&1 || return 1
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
            rm -f "$PASS_FILE"
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
