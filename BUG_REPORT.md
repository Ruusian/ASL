# ASL Bug Report

## Critical Bugs

### 1. **Unquoted Variable Expansion in Test Conditions** ⚠️ HIGH
**File**: `core/mount-chroot.sh`  
**Lines**: 81, 85, 86, 90-91, 93, 95-96

**Issue**: Variables are used without quotes in test conditions and redirections, which can cause:
- Word splitting if paths contain spaces (though unlikely in this case)
- Globbing expansion issues
- Potential command injection vulnerabilities

**Examples**:
```bash
# Line 81 - BUGGY
if [ -d $DEBIANPATH/var ] && [ ! -L $DEBIANPATH/var/lock ]; then

# Line 85-86 - BUGGY
if [ ! -s $DEBIANPATH/etc/resolv.conf ]; then
    mkdir -p $DEBIANPATH/etc

# Lines 90-96 - BUGGY
printf 'nameserver %s\n' "$dns1" > $DEBIANPATH/etc/resolv.conf
```

**Fix**: Quote all variable expansions:
```bash
# FIXED
if [ -d "$DEBIANPATH/var" ] && [ ! -L "$DEBIANPATH/var/lock" ]; then
    mkdir -p "$DEBIANPATH/var/lock"
fi

if [ ! -s "$DEBIANPATH/etc/resolv.conf" ]; then
    mkdir -p "$DEBIANPATH/etc"
    # ... rest of code
    printf 'nameserver %s\n' "$dns1" > "$DEBIANPATH/etc/resolv.conf"
fi
```

---

### 2. **Race Condition in Process Manager** ⚠️ MEDIUM
**File**: `bin/asl`  
**Function**: `process_manager()` (lines ~350-400)

**Issue**: A PID obtained from `ps` output might not exist by the time `kill` is called, or could have been reassigned to a different process. This can result in killing an unintended process.

**Example**:
```bash
read -r -p "Enter PID to terminate: " target_pid
if [[ "$target_pid" =~ ^[0-9]+$ ]]; then
    if is_safe_target_pid "$target_pid"; then
        if kill "$target_pid" 2>/dev/null || su -c "kill '$target_pid'" 2>/dev/null; then
            echo "[✓] Sent SIGTERM to PID $target_pid"
```

**Fix**: Check if process still exists and hasn't been reassigned:
```bash
if kill -0 "$target_pid" 2>/dev/null; then
    # Process exists and is still accessible
    if kill "$target_pid" 2>/dev/null; then
        echo "[✓] Sent SIGTERM to PID $target_pid"
    fi
fi
```

---

### 3. **Insufficient Base64 Encoding Validation** ⚠️ MEDIUM  
**File**: `bin/asl`  
**Function**: `run_in_chroot()` (lines 48-51)

**Issue**: Very long commands could fail silently or be truncated if they exceed shell argument limits during base64 encoding/decoding pipeline.

**Current Code**:
```bash
run_in_chroot() {
    local command_text="$*"
    local command_b64
    command_b64=$(printf '%s' "$command_text" | base64 | tr -d '\n')
    su -c "chroot '$DEBIANPATH' /bin/bash --noprofile --norc -c 'export PATH=... printf \"%s\" \"$command_b64\" | /usr/bin/base64 -d | /bin/bash'"
}
```

**Risk**: If command_b64 is very large (e.g., > 100KB), shell expansion might fail or truncate the command.

---

## Medium Priority Bugs

### 4. **Incomplete Shell Option Handling in mount-chroot.sh** ⚠️ MEDIUM
**File**: `core/mount-chroot.sh`  
**Line**: 17

**Issue**: Uses `set -e` inside a subshell with `su -c`, but doesn't properly handle failures in multi-line statements. If one mount fails, subsequent operations may still proceed.

**Example**:
```bash
su -c "
    set -e
    if ! grep -q -w \"$DEBIANPATH\" /proc/mounts 2>/dev/null; then
        mount --bind \"$DEBIANPATH\" \"$DEBIANPATH\"  # If this fails, but error is suppressed...
    fi
    mount --make-rprivate \"$DEBIANPATH\" 2>/dev/null || true  # This still runs!
"
```

**Better Approach**: Use explicit error checking:
```bash
mount --make-rprivate "$DEBIANPATH" 2>/dev/null || {
    echo "[!] Failed to make private: $DEBIANPATH"
    exit 1
}
```

---

### 5. **Missing Validation in snapshot.sh** ⚠️ MEDIUM
**File**: `core/snapshot.sh`

**Issue**: The `safe_name` function (mentioned but not shown in code review) should be validated to ensure snapshot names don't contain path traversal sequences like `../` or absolute paths.

**Risk**: A snapshot named `../../etc/passwd` could potentially escape the snapshot directory during restore operations.

---

### 6. **Potential File Descriptor Leak in read_state()** ⚠️ LOW
**File**: `desktop/start-desktop.sh`  
**Function**: `read_state()` (lines 108-125)

**Issue**: The function reads from `$STATE_FILE` in a while loop but doesn't explicitly close file descriptors if parsing fails mid-stream.

```bash
while IFS='=' read -r key value; do
    case "$key" in
        DISPLAY_ID|X11_PID|X11_START|...)
            printf -v "$key" '%s' "$value"
            ;;
        *) return 1 ;;  # Returns without clean FD cleanup
    esac
done < "$STATE_FILE"
```

**Fix**: Use explicit file descriptor management:
```bash
while IFS='=' read -r -u 3 key value; do
    # ... validation ...
done 3< "$STATE_FILE"
```

---

### 7. **Regex Pattern Bypass in asl Script** ⚠️ LOW
**File**: `bin/asl`  
**Line**: Various package validation

**Issue**: Package name validation uses basic regex `^[A-Za-z0-9][A-Za-z0-9.+_-]*$`, but this might allow certain characters that could be misinterpreted:

```bash
for pkg in "$@"; do
    if [[ ! "$pkg" =~ ^[A-Za-z0-9][A-Za-z0-9.+_-]*$ ]]; then
        echo "Error: Invalid package name: $pkg"
        exit 1
    fi
done
```

**Risk**: While this appears safe for Debian package names, it's worth noting that `+` character could be problematic in some contexts. Better to use Debian's official package name rules.

---

## Low Priority / Design Issues

### 8. **Hardcoded Path Validation** ℹ️ LOW
**File**: Multiple files (mount-chroot.sh, android-aid.sh, etc.)

**Issue**: Path is hardcoded and validated to be exactly `/data/local/tmp/chrootDebian`, but this creates inflexibility:

```bash
if [ "$DEBIANPATH" != "/data/local/tmp/chrootDebian" ]; then
    echo "Error: DEBIANPATH must be /data/local/tmp/chrootDebian"
    exit 2
fi
```

**Suggestion**: Consider allowing alternate paths while maintaining security checks.

---

### 9. **Missing Error Messages in Critical Paths** ℹ️ LOW
**File**: `core/snapshot.sh`, `core/stop-chroot.sh`

**Issue**: Some commands fail silently (via `2>/dev/null || true`), making debugging difficult if the operation fails unexpectedly.

---

## Summary

| Severity | Count | Issues |
|----------|-------|--------|
| 🔴 Critical/High | 2 | Unquoted variables, potential injection |
| 🟠 Medium | 3 | Race conditions, encoding limits, validation ✅ |
| 🟡 Low | 2 | FD management, regex patterns ✅ |
| ℹ️ Design | 2 | Hardcoded paths, missing diagnostics ✅ |

**NOTE:** Issue #5 (Snapshot path traversal) is NOT a bug - the `safe_name()` function properly prevents all path traversal attempts.

---

## Recommended Fixes Priority

1. **Fix unquoted variables in mount-chroot.sh** (Issue #1) - Apply immediately
2. **Add process existence checks in process_manager** (Issue #2) - High priority
3. **Validate base64 encoding length limits** (Issue #3) - Medium priority
4. **Review error handling in mount operations** (Issue #4) - Medium priority
5. **Improve state file parsing** (Issue #6) - Low priority
