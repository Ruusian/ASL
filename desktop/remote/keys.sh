#!/bin/bash
# ASL Remote Access - SSH Public Key Management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"

sync_key_to_oracle() {
    local key_data="$1"
    if [ -f "$SCRIPT_DIR/desktop/remote/oracle.sh" ]; then
        source "$SCRIPT_DIR/desktop/remote/oracle.sh" >/dev/null 2>&1 || true
        load_oracle_config 2>/dev/null || true
    fi
    local oracle_key="${ORACLE_KEY:-$HOME/.ssh/oracle_vps.key}"
    local oracle_host="${ORACLE_HOST:-${ASL_ORACLE_HOST:-}}"
    local oracle_user="${ORACLE_USER:-${ASL_ORACLE_USER:-ubuntu}}"

    if [ -n "$oracle_host" ] && [ -f "$oracle_key" ] && [ -n "$key_data" ]; then
        echo "$key_data" | ssh -i "$oracle_key" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${oracle_user}@${oracle_host}" \
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" >/dev/null 2>&1 || true
    fi
}

key_control() {
    local action="${1:-list}"
    local key_file="$HOME/.ssh/authorized_keys"
    case "$action" in
        add)
            local key="${2:-}"
            if [ -z "$key" ] || ! printf '%s\n' "$key" | grep -qE '^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2-)[[:space:]]+[A-Za-z0-9+/]+=*([[:space:]]+[^[:space:]]+)?$'; then
                echo "Usage: asl remote keys add \"<ssh-pubkey-string>\""
                return 1
            fi
            mkdir -p "$HOME/.ssh"
            echo "$key" >> "$key_file"
            chmod 600 "$key_file"
            sync_key_to_oracle "$key"
            echo "[✓] SSH Public Key added successfully to host and Oracle VPS."
            ;;
        import-github|github)
            local gh_user="$2"
            if [ -z "$gh_user" ] || [[ ! "$gh_user" =~ ^[A-Za-z0-9-]+$ ]]; then
                echo "Usage: asl remote keys import-github <github_username>"
                return 1
            fi
            echo "[*] Fetching SSH public keys for GitHub user '$gh_user'..."
            local fetched_keys valid_keys invalid_count
            fetched_keys=$(curl -fsSL --max-time 20 --connect-timeout 10 "https://github.com/${gh_user}.keys" 2>/dev/null || true)
            if [ -n "$fetched_keys" ] && [ "${#fetched_keys}" -le 65536 ]; then
                valid_keys=""
                invalid_count=0
                while IFS= read -r line; do
                    if printf '%s\n' "$line" | grep -qE '^(ssh-(rsa|ed25519|ecdsa)|ecdsa-sha2-)[[:space:]]+[A-Za-z0-9+/]+=*([[:space:]]+[^[:space:]]+)?$'; then
                        valid_keys="${valid_keys}${line}"$'\n'
                    else
                        invalid_count=$((invalid_count + 1))
                    fi
                done <<< "$fetched_keys"
                if [ -z "$valid_keys" ]; then
                    echo "Error: No valid SSH keys found for GitHub user '$gh_user'."
                    return 1
                fi
                if [ "$invalid_count" -gt 0 ]; then
                    echo "[!] Skipped $invalid_count invalid line(s) from the fetched key list."
                fi
                mkdir -p "$HOME/.ssh"
                chmod 700 "$HOME/.ssh"
                printf '%s' "$valid_keys" >> "$key_file"
                chmod 600 "$key_file"
                sync_key_to_oracle "$valid_keys"
                echo "[✓] Successfully imported SSH key(s) from GitHub user '$gh_user' to host and Oracle VPS."
            else
                echo "Error: Could not fetch SSH keys for GitHub user '$gh_user' (empty, timed out, or oversized response)."
                return 1
            fi
            ;;
        list|show)
            echo "=== Authorized SSH Public Keys ==="
            if [ -f "$key_file" ] && [ -s "$key_file" ]; then
                cat "$key_file"
            else
                echo "(No public keys authorized yet. Add using 'asl remote keys add' or 'asl remote keys import-github <user>')"
            fi
            ;;
        clear|purge)
            rm -f "$key_file"
            echo "[✓] Authorized SSH keys cleared."
            ;;
        *)
            echo "Usage: asl remote keys [list|add <key>|import-github <username>|clear]"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    key_control "$@"
fi
