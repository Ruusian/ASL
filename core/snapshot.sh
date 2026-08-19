#!/bin/bash
# ASL: Chroot Snapshot Manager

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
elif [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi
SNAPSHOT_DIR="${ASL_SNAPSHOT_DIR:-/data/local/tmp/.asl-snapshots}"

if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ] && [ "${ASL_EXEC_MODE:-root}" = "root" ] && [ ! -d "$DEBIANPATH" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi

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

    required_mb=$(asl_exec "du -sm '$DEBIANPATH' 2>/dev/null" | awk '{print $1}')
    target_free_mb=$(df -m "/data/local/tmp" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$required_mb" ] && [ -n "$target_free_mb" ] && [ "$target_free_mb" -lt "$required_mb" ]; then
        echo "[!] Insufficient disk space: ${target_free_mb}MB free, ~${required_mb}MB required."
        remount_if_needed "$was_mounted"
        return 1
    fi

    if ! asl_exec "mkdir -p '$SNAPSHOT_DIR'"; then
        remount_if_needed "$was_mounted"
        return 1
    fi
    echo "[*] Creating snapshot '$name' (~${required_mb}MB)..."
    if ! asl_exec "cp -a '$DEBIANPATH' '$target'"; then
        asl_exec "rm -rf '$target'" 2>/dev/null
        echo "[!] Snapshot creation failed."
        remount_if_needed "$was_mounted"
        return 1
    fi
    echo "[✓] Snapshot '$name' created successfully."
    remount_if_needed "$was_mounted"
}

list_snapshots() {
    echo "=== ASL Snapshots ==="
    if [ ! -d "$SNAPSHOT_DIR" ] || [ -z "$(asl_exec "ls -A '$SNAPSHOT_DIR' 2>/dev/null")" ]; then
        echo " No snapshots found."
        return 0
    fi
    asl_exec "du -sh '$SNAPSHOT_DIR'/* 2>/dev/null" | awk '{split($2, a, "/"); print " - " a[length(a)] " (" $1 ")"}'
}

restore_snapshot() {
    local name="${1:-}" was_mounted=0 required_mb target_free_mb source rollback
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required. Usage: asl snapshot restore <name>"
        return 1
    fi
    source="$SNAPSHOT_DIR/$name"
    if ! asl_exec "test -d '$source'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        return 1
    fi

    if is_mounted; then
        was_mounted=1
    fi
    required_mb=$(asl_exec "du -sm '$source' 2>/dev/null" | awk '{print $1}')
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
    if ! asl_exec "mv '$DEBIANPATH' '$rollback'"; then
        echo "[!] Failed to move current chroot to rollback location."
        remount_if_needed "$was_mounted"
        return 1
    fi
    if ! asl_exec "cp -a '$source' '$DEBIANPATH'"; then
        echo "[!] Restore failed; cleaning up incomplete copy and rolling back original state."
        if ! asl_exec "rm -rf '$DEBIANPATH' && mv '$rollback' '$DEBIANPATH'"; then
            echo "[!] Rollback failed; manual recovery may be required at $rollback."
        fi
        remount_if_needed "$was_mounted"
        return 1
    fi
    asl_exec "rm -rf '$rollback'" 2>/dev/null || true
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
    if ! asl_exec "test -d '$target'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        return 1
    fi
    asl_exec "rm -rf '$target'"
    echo "[✓] Snapshot '$name' deleted."
}

export_snapshot() {
    local name="${1:-}" out_file="${2:-}"
    if [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Valid snapshot name required. Usage: asl snapshot export <name> [output.tar.zst|tar.xz]"
        return 1
    fi
    local target="$SNAPSHOT_DIR/$name"
    if ! asl_exec "test -d '$target'" 2>/dev/null; then
        echo "[!] Snapshot '$name' does not exist."
        return 1
    fi
    out_file="${out_file:-/sdcard/Download/${name}.tar.zst}"
    local out_dir
    out_dir=$(dirname "$out_file")
    local req_mb avail_mb
    req_mb=$(asl_exec "du -sm '$target' 2>/dev/null | cut -f1" || echo 1000)
    avail_mb=$(asl_exec "df -m '$out_dir' 2>/dev/null | awk 'NR==2 {print \$4}'" || echo 5000)
    if [ -n "$avail_mb" ] && [ "$avail_mb" -lt "$req_mb" ]; then
        echo "[!] Storage error: Insufficient space in $out_dir (Required: ~${req_mb}MB, Available: ${avail_mb}MB)."
        return 1
    fi
    echo "[*] Exporting snapshot '$name' to '$out_file'..."
    local out_q target_q comp_flag="--zstd"
    case "$out_file" in
        *.tar.xz|*.txz) comp_flag="-J" ;;
        *.tar.gz|*.tgz) comp_flag="-z" ;;
        *.tar.bz2|*.tbz2) comp_flag="-j" ;;
        *.tar.zst|*.tzst|*)
            if asl_exec "command -v zstd >/dev/null 2>&1" || command -v zstd >/dev/null 2>&1; then
                comp_flag="--zstd"
            else
                comp_flag="-J"
                out_file="${out_file%.tar.zst}.tar.xz"
            fi
            ;;
    esac
    out_q=$(printf '%q' "$out_file")
    target_q=$(printf '%q' "$target")
    if asl_exec "tar $comp_flag -cf $out_q -C $target_q ."; then
        echo "[✓] Snapshot successfully exported to '$out_file'."
    else
        echo "[!] Export failed."
        return 1
    fi
}

import_snapshot() {
    local file="${1:-}" name="${2:-}"
    if [ -z "$file" ] || [ -z "$name" ] || ! safe_name "$name"; then
        echo "Error: Usage: asl snapshot import <archive.tar.zst|tar.xz> <snapshot_name>"
        return 1
    fi
    local target="$SNAPSHOT_DIR/$name"
    if asl_exec "test -d '$target'" 2>/dev/null; then
        echo "[!] Snapshot '$name' already exists."
        return 1
    fi
    asl_exec "mkdir -p '$target'"
    echo "[*] Importing snapshot from '$file' as '$name'..."
    local file_q target_q comp_flag="--zstd"
    case "$file" in
        *.tar.xz|*.txz) comp_flag="-J" ;;
        *.tar.gz|*.tgz) comp_flag="-z" ;;
        *.tar.bz2|*.tbz2) comp_flag="-j" ;;
        *.tar.zst|*.tzst|*) comp_flag="--zstd" ;;
    esac
    file_q=$(printf '%q' "$file")
    target_q=$(printf '%q' "$target")
    # Reject archives that attempt path traversal or absolute paths so a
    # malicious tar cannot write outside the snapshot directory.
    if asl_exec "tar $comp_flag -tf $file_q 2>/dev/null" | grep -qE '(^|/)\.\.(/|$)|^/'; then
        echo "[!] Import failed: archive contains unsafe paths (absolute or ../ traversal)."
        asl_exec "rm -rf '$target'" 2>/dev/null
        return 1
    fi
    if asl_exec "tar $comp_flag -xf $file_q -C $target_q"; then
        echo "[✓] Snapshot '$name' imported successfully."
    else
        echo "[!] Import failed."
        asl_exec "rm -rf '$target'" 2>/dev/null
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

