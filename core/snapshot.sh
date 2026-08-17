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

remount_if_needed() {
    if [ "${1:-0}" -eq 1 ]; then
        echo "[*] Re-mounting chroot..."
        bash "$SCRIPT_DIR/mount-chroot.sh" || echo "[!] Warning: chroot remount failed; run 'asl start' to mount it."
    fi
}

create_snapshot() {
    local name="${1:-}" was_mounted=0 required_mb target_free_mb target
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required (alphanumeric, underscore, hyphen)."
        return 1
    fi
    target="$SNAPSHOT_DIR/$name"
    if [ -d "$target" ]; then
        echo "[!] Snapshot '$name' already exists. Delete it first or use a different name."
        return 1
    fi

    if is_mounted; then
        was_mounted=1
        echo "[!] Stopping chroot before creating snapshot..."
        bash "$SCRIPT_DIR/stop-chroot.sh" || return 1
    fi

    required_mb=$(su -c "du -sm '$DEBIANPATH' 2>/dev/null" | awk '{print $1}')
    target_free_mb=$(df -m "/data/local/tmp" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$required_mb" ] && [ -n "$target_free_mb" ] && [ "$target_free_mb" -lt "$required_mb" ]; then
        echo "[!] Insufficient disk space: ${target_free_mb}MB free, ~${required_mb}MB required."
        remount_if_needed "$was_mounted"
        return 1
    fi

    if ! su -c "mkdir -p '$SNAPSHOT_DIR'"; then
        remount_if_needed "$was_mounted"
        return 1
    fi
    echo "[*] Creating snapshot '$name' (~${required_mb}MB)..."
    if ! su -c "cp -a '$DEBIANPATH' '$target'"; then
        su -c "rm -rf '$target'" 2>/dev/null
        echo "[!] Snapshot creation failed."
        remount_if_needed "$was_mounted"
        return 1
    fi
    echo "[✓] Snapshot '$name' created successfully."
    remount_if_needed "$was_mounted"
}

list_snapshots() {
    echo "=== ASL Snapshots ==="
    if [ ! -d "$SNAPSHOT_DIR" ] || [ -z "$(su -c "ls -A '$SNAPSHOT_DIR' 2>/dev/null")" ]; then
        echo " No snapshots found."
        return 0
    fi
    su -c "du -sh '$SNAPSHOT_DIR'/* 2>/dev/null" | awk '{split($2, a, "/"); print " - " a[length(a)] " (" $1 ")"}'
}

restore_snapshot() {
    local name="${1:-}" was_mounted=0 required_mb target_free_mb source rollback
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required. Usage: asl snapshot restore <name>"
        return 1
    fi
    source="$SNAPSHOT_DIR/$name"
    if ! su -c "test -d '$source'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        return 1
    fi

    if is_mounted; then
        was_mounted=1
    fi
    required_mb=$(su -c "du -sm '$source' 2>/dev/null" | awk '{print $1}')
    target_free_mb=$(df -m "/data/local/tmp" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$required_mb" ] && [ -n "$target_free_mb" ] && [ "$target_free_mb" -lt "$required_mb" ]; then
        echo "[!] Insufficient disk space to restore snapshot: ${target_free_mb}MB free, ~${required_mb}MB required."
        return 1
    fi

    if [ "$was_mounted" -eq 1 ] || is_mounted; then
        echo "[!] Stopping chroot before restoring snapshot..."
        bash "$SCRIPT_DIR/stop-chroot.sh" || return 1
    fi

    if is_mounted; then
        echo "[!] Cannot restore snapshot: active mounts remain below $DEBIANPATH."
        return 1
    fi

    echo "[*] Restoring snapshot '$name'..."
    rollback="$DEBIANPATH.pre-snapshot-restore-$(date +%Y%m%d_%H%M%S)"
    if ! su -c "mv '$DEBIANPATH' '$rollback'"; then
        echo "[!] Failed to move current chroot to rollback location."
        remount_if_needed "$was_mounted"
        return 1
    fi
    if ! su -c "cp -a '$source' '$DEBIANPATH'"; then
        echo "[!] Restore failed; cleaning up incomplete copy and rolling back original state."
        if ! su -c "rm -rf '$DEBIANPATH' && mv '$rollback' '$DEBIANPATH'"; then
            echo "[!] Rollback failed; manual recovery may be required at $rollback."
        fi
        remount_if_needed "$was_mounted"
        return 1
    fi
    su -c "rm -rf '$rollback'" 2>/dev/null || true
    echo "[✓] Snapshot '$name' restored successfully."
    remount_if_needed "$was_mounted"
}

delete_snapshot() {
    local name="${1:-}"
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required. Usage: asl snapshot delete <name>"
        return 1
    fi
    local target="$SNAPSHOT_DIR/$name"
    if ! su -c "test -d '$target'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        return 1
    fi
    su -c "rm -rf '$target'"
    echo "[✓] Snapshot '$name' deleted."
}

export_snapshot() {
    local name="${1:-}" out_file="${2:-}"
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required. Usage: asl snapshot export <name> [output.tar.xz]"
        return 1
    fi
    local target="$SNAPSHOT_DIR/$name"
    if ! su -c "test -d '$target'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        return 1
    fi
    out_file="${out_file:-/sdcard/Download/${name}.tar.xz}"
    echo "[*] Exporting snapshot '$name' to '$out_file'..."
    if su -c "tar -cJf '$out_file' -C '$target' ."; then
        echo "[✓] Snapshot successfully exported to '$out_file'."
    else
        echo "[!] Export failed."
        return 1
    fi
}

import_snapshot() {
    local file="${1:-}" name="${2:-}"
    if [ -z "$file" ] || [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Usage: asl snapshot import <archive.tar.xz> <snapshot_name>"
        return 1
    fi
    local target="$SNAPSHOT_DIR/$name"
    if su -c "test -d '$target'" 2>/dev/null; then
        echo "[!] Snapshot '$name' already exists."
        return 1
    fi
    su -c "mkdir -p '$target'"
    echo "[*] Importing snapshot from '$file' as '$name'..."
    if su -c "tar -xJf '$file' -C '$target'"; then
        echo "[✓] Snapshot '$name' imported successfully."
    else
        echo "[!] Import failed."
        su -c "rm -rf '$target'" 2>/dev/null
        return 1
    fi
}

case "${1:-list}" in
    create) shift; create_snapshot "$@" ;;
    list) list_snapshots ;;
    restore) shift; restore_snapshot "$@" ;;
    delete|remove) shift; delete_snapshot "$@" ;;
    export) shift; export_snapshot "$@" ;;
    import) shift; import_snapshot "$@" ;;
    *) echo "Usage: asl snapshot [create|list|restore|delete|export|import] <name>"; exit 1 ;;
esac

