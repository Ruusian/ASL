#!/bin/bash
# ASL: Chroot Snapshot Manager

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_DIR="/data/local/tmp/.asl-snapshots"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

is_mounted() {
    su -c "grep -E -q -w '$DEBIANPATH(/.*)?' /proc/mounts" 2>/dev/null
}

safe_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

create_snapshot() {
    local name="${1:-}"
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required (alphanumeric, underscore, hyphen)."
        exit 1
    fi
    local target="$SNAPSHOT_DIR/$name"
    if [ -d "$target" ]; then
        echo "[!] Snapshot '$name' already exists. Delete it first or use a different name."
        exit 1
    fi

    if is_mounted; then
        echo "[!] Stopping chroot before creating snapshot..."
        bash "$SCRIPT_DIR/stop-chroot.sh" || exit 1
    fi

    local required_mb target_free_mb
    required_mb=$(su -c "du -sm '$DEBIANPATH' 2>/dev/null" | awk '{print $1}')
    target_free_mb=$(df -m "/data/local/tmp" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$required_mb" ] && [ -n "$target_free_mb" ] && [ "$target_free_mb" -lt "$required_mb" ]; then
        echo "[!] Insufficient disk space: ${target_free_mb}MB free, ~${required_mb}MB required."
        exit 1
    fi

    su -c "mkdir -p '$SNAPSHOT_DIR'" || exit 1
    echo "[*] Creating snapshot '$name' (~${required_mb}MB)..."
    if su -c "cp -a '$DEBIANPATH' '$target'"; then
        echo "[✓] Snapshot '$name' created successfully."
        echo "[*] Re-mounting chroot..."
        bash "$SCRIPT_DIR/mount-chroot.sh" || echo "[!] Warning: chroot remount failed; run 'asl start' to mount it."
    else
        su -c "rm -rf '$target'" 2>/dev/null
        echo "[!] Snapshot creation failed."
        exit 1
    fi
}

list_snapshots() {
    echo "=== ASL Snapshots ==="
    if [ ! -d "$SNAPSHOT_DIR" ] || [ -z "$(su -c "ls -A '$SNAPSHOT_DIR' 2>/dev/null")" ]; then
        echo " No snapshots found."
        return 0
    fi
    su -c "du -sh '$SNAPSHOT_DIR'/* 2>/dev/null" | awk '{print " - " $2 " (" $1 ")"}' | sed 's|.*/||'
}

restore_snapshot() {
    local name="${1:-}"
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required. Usage: asl snapshot restore <name>"
        exit 1
    fi
    local source="$SNAPSHOT_DIR/$name"
    if ! su -c "test -d '$source'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        exit 1
    fi

    if is_mounted; then
        echo "[!] Stopping chroot before restoring snapshot..."
        bash "$SCRIPT_DIR/stop-chroot.sh" || exit 1
    fi

    echo "[*] Restoring snapshot '$name'..."
    local rollback="$DEBIANPATH.pre-snapshot-restore-$(date +%Y%m%d_%H%M%S)"
    if su -c "mv '$DEBIANPATH' '$rollback'"; then
        if su -c "cp -a '$source' '$DEBIANPATH'"; then
            su -c "rm -rf '$rollback'" 2>/dev/null || true
            echo "[✓] Snapshot '$name' restored successfully."
        else
            echo "[!] Restore failed; cleaning up incomplete copy and rolling back original state."
            su -c "rm -rf '$DEBIANPATH' && mv '$rollback' '$DEBIANPATH'" 2>/dev/null
            exit 1
        fi
    else
        echo "[!] Failed to move current chroot to rollback location."
        exit 1
    fi
}

delete_snapshot() {
    local name="${1:-}"
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required. Usage: asl snapshot delete <name>"
        exit 1
    fi
    local target="$SNAPSHOT_DIR/$name"
    if ! su -c "test -d '$target'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        exit 1
    fi
    su -c "rm -rf '$target'"
    echo "[✓] Snapshot '$name' deleted."
}

case "${1:-list}" in
    create) shift; create_snapshot "$@" ;;
    list) list_snapshots ;;
    restore) shift; restore_snapshot "$@" ;;
    delete|remove) shift; delete_snapshot "$@" ;;
    *) echo "Usage: asl snapshot [create|list|restore|delete] <name>"; exit 1 ;;
esac

