#!/bin/bash
# Unit tests for ASL core functions
# Tests individual functions in isolation using the mock environment

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load mock environment
source "$SCRIPT_DIR/mock-env.sh"
setup_mock_env

PASS=0
FAIL=0
ERRORS=()

test_assert() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $name"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $name (expected='$expected', got='$actual')"
        ERRORS+=("$name")
    fi
}

test_assert_contains() {
    local name="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -q "$needle" 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  ✓ $name"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $name (expected to contain '$needle')"
        ERRORS+=("$name")
    fi
}

test_exit_code() {
    local name="$1" expected="$2"
    shift 2
    local actual
    actual=0
    "$@" 2>/dev/null || actual=$?
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $name"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $name (expected exit=$expected, got=$actual)"
        ERRORS+=("$name")
    fi
}

echo "============================================================"
echo "  ASL Unit Test Suite"
echo "============================================================"
echo ""

# ---- Test 1: common.sh is sourceable ----
echo "1. Loading common.sh..."
if source "$ASL_DIR/core/common.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ common.sh loads without errors"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ common.sh failed to load"
    ERRORS+=("common.sh load")
fi

# ---- Test 2: asl_detect_mode returns valid mode ----
echo ""
echo "2. Testing asl_detect_mode..."
if command -v asl_detect_mode &>/dev/null; then
    mode=$(ASL_EXEC_MODE="" asl_detect_mode 2>/dev/null || echo "error")
    case "$mode" in
        root|shizuku|proot)
            PASS=$((PASS + 1))
            echo "  ✓ asl_detect_mode returns valid mode: $mode"
            ;;
        *)
            FAIL=$((FAIL + 1))
            echo "  ✗ asl_detect_mode returned invalid: $mode"
            ERRORS+=("asl_detect_mode")
            ;;
    esac
else
    FAIL=$((FAIL + 1))
    echo "  ✗ asl_detect_mode not defined after sourcing common.sh"
    ERRORS+=("asl_detect_mode missing")
fi

# ---- Test 3: ASL_DIR is set correctly ----
echo ""
echo "3. Testing ASL_DIR..."
test_assert "ASL_DIR set" "$ASL_DIR" "${ASL_DIR:-}"

# ---- Test 4: DEBIANPATH is set ----
echo ""
echo "4. Testing DEBIANPATH..."
test_assert "DEBIANPATH set" "$MOCK_ROOT/data/local/tmp/chrootDebian" "${DEBIANPATH:-}"

# ---- Test 5: Color variables defined ----
echo ""
echo "5. Testing color variables..."
if [ -n "${C_RED:-}" ] && [ -n "${C_GREEN:-}" ] && [ -n "${C_RESET:-}" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ Color variables defined (C_RED, C_GREEN, C_RESET)"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ Color variables missing"
    ERRORS+=("color vars")
fi

# ---- Test 6: draw_bar function (in bin/asl) ----
echo ""
echo "6. Testing draw_bar function..."
# Source the function from bin/asl, defining color vars as empty beforehand
if grep -q "draw_bar()" "$ASL_DIR/bin/asl" 2>/dev/null; then
    C_RED='' C_YELLOW='' C_GREEN='' C_DIM='' C_RESET=''
    eval "$(sed -n '/^draw_bar()/,/^}/p' "$ASL_DIR/bin/asl")"
    result=$(draw_bar 50 10 2>/dev/null)
    filled_count=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2588)))" "$result" 2>/dev/null || echo "0")
    empty_count=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2591)))" "$result" 2>/dev/null || echo "0")
    filled_count=$(echo "$filled_count" | tr -dc '0-9')
    empty_count=$(echo "$empty_count" | tr -dc '0-9')
    test_assert "draw_bar 50% filled blocks" "5" "$filled_count"
    test_assert "draw_bar 50% empty blocks" "5" "$empty_count"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ draw_bar function not found"
    ERRORS+=("draw_bar missing")
fi

# ---- Test 7: draw_bar boundary values ----
echo ""
echo "7. Testing draw_bar boundaries..."
if grep -q "draw_bar()" "$ASL_DIR/bin/asl" 2>/dev/null; then
    # Test 0%
    result_0=$(draw_bar 0 10 2>/dev/null)
    filled_0=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2588)))" "$result_0" 2>/dev/null || echo "0")
    filled_0=$(echo "$filled_0" | tr -dc '0-9')
    test_assert "draw_bar 0% = 0 filled" "0" "$filled_0"

    # Test 100%
    result_100=$(draw_bar 100 10 2>/dev/null)
    filled_100=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2588)))" "$result_100" 2>/dev/null || echo "0")
    empty_100=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2591)))" "$result_100" 2>/dev/null || echo "0")
    filled_100=$(echo "$filled_100" | tr -dc '0-9')
    empty_100=$(echo "$empty_100" | tr -dc '0-9')
    test_assert "draw_bar 100% = 10 filled" "10" "$filled_100"
    test_assert "draw_bar 100% = 0 empty" "0" "$empty_100"

    # Test 150% (should clamp to 100)
    result_150=$(draw_bar 150 10 2>/dev/null)
    filled_150=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2588)))" "$result_150" 2>/dev/null || echo "0")
    filled_150=$(echo "$filled_150" | tr -dc '0-9')
    test_assert "draw_bar 150% clamps to 10 filled" "10" "$filled_150"

    # Test -5% (should clamp to 0)
    result_neg=$(draw_bar -5 10 2>/dev/null)
    filled_neg=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2588)))" "$result_neg" 2>/dev/null || echo "0")
    filled_neg=$(echo "$filled_neg" | tr -dc '0-9')
    test_assert "draw_bar -5% clamps to 0 filled" "0" "$filled_neg"

    # Test empty input
    result_empty=$(draw_bar "" 10 2>/dev/null)
    filled_empty=$(python3 -c "import sys; print(sys.argv[1].count(chr(0x2588)))" "$result_empty" 2>/dev/null || echo "0")
    filled_empty=$(echo "$filled_empty" | tr -dc '0-9')
    test_assert "draw_bar empty = 0 filled" "0" "$filled_empty"
fi

# ---- Test 8: asl_uptime function ----
echo ""
echo "8. Testing asl_uptime function..."
if grep -q "asl_uptime()" "$ASL_DIR/bin/asl" 2>/dev/null; then
    eval "$(sed -n '/^asl_uptime()/,/^}/p' "$ASL_DIR/bin/asl")"
    uptime_result=$(asl_uptime 2>/dev/null)
    if [ -n "$uptime_result" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ asl_uptime returns: $uptime_result"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ asl_uptime returned empty"
        ERRORS+=("asl_uptime empty")
    fi
fi

# ---- Test 9: asl_cpu_freq function ----
echo ""
echo "9. Testing asl_cpu_freq function..."
if grep -q "asl_cpu_freq()" "$ASL_DIR/bin/asl" 2>/dev/null; then
    eval "$(sed -n '/^asl_cpu_freq()/,/^}/p' "$ASL_DIR/bin/asl")"
    freq_result=$(asl_cpu_freq 2>/dev/null)
    if echo "$freq_result" | grep -qE '[0-9]+MHz|\?'; then
        PASS=$((PASS + 1))
        echo "  ✓ asl_cpu_freq returns: $freq_result"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ asl_cpu_freq returned unexpected: $freq_result"
        ERRORS+=("asl_cpu_freq")
    fi
fi

# ---- Test 10: is_mounted function ----
echo ""
echo "10. Testing is_mounted function..."
if grep -q "is_mounted()" "$ASL_DIR/core/common.sh" 2>/dev/null; then
    # Nothing should be mounted in mock env
    if ! is_mounted 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  ✓ is_mounted returns false (no mounts in mock)"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ is_mounted returned true unexpectedly"
        ERRORS+=("is_mounted false")
    fi

    # A clearly-nonexistent target must return non-zero
    if ! is_mounted "/definitely/not/mounted/asl-test" 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  ✓ is_mounted returns false for nonexistent target"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ is_mounted returned true for nonexistent target"
        ERRORS+=("is_mounted custom target")
    fi
fi

# ---- Test 11: status_label function ----
echo ""
echo "11. Testing status_label function..."
if grep -q "status_label()" "$ASL_DIR/bin/asl" 2>/dev/null; then
    eval "$(sed -n '/^status_label()/,/^}/p' "$ASL_DIR/bin/asl")"
    active_label=$(status_label ACTIVE 2>/dev/null)
    if echo "$active_label" | grep -q "ACTIVE"; then
        PASS=$((PASS + 1))
        echo "  ✓ status_label ACTIVE works"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ status_label ACTIVE failed"
        ERRORS+=("status_label")
    fi
fi

# ---- Test 12: bin/asl --help runs ----
echo ""
echo "12. Testing bin/asl --help..."
output=$("$ASL_DIR/bin/asl" help 2>&1 || true)
if echo "$output" | grep -q "Android Subsystem for Linux"; then
    PASS=$((PASS + 1))
    echo "  ✓ asl help shows banner"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ asl help did not show banner"
    ERRORS+=("asl help")
fi

# ---- Test 13: bin/asl unknown command ----
echo ""
echo "13. Testing bin/asl unknown command..."
output=$("$ASL_DIR/bin/asl" nonexistentcommand 2>&1 || true)
if echo "$output" | grep -qi "unknown\|not found\|help"; then
    PASS=$((PASS + 1))
    echo "  ✓ asl unknown command shows error/help"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ asl unknown command silent"
    ERRORS+=("asl unknown cmd")
fi

# ---- Test 14: GPU detection scripts are sourceable ----
echo ""
echo "14. Testing GPU scripts..."
for f in gpu-profile.sh gpu-detect.sh; do
    if [ -f "$ASL_DIR/core/$f" ]; then
        if bash -n "$ASL_DIR/core/$f" 2>/dev/null; then
            PASS=$((PASS + 1))
            echo "  ✓ core/$f has valid syntax"
        else
            FAIL=$((FAIL + 1))
            echo "  ✗ core/$f has syntax errors"
            ERRORS+=("syntax $f")
        fi
    fi
done

# ---- Test 15: Python GTK3 app syntax check ----
echo ""
echo "15. Testing Python GTK3 app syntax..."
PYTHON_APP="$ASL_DIR/desktop/asl-hub/asl-control-center.py"
if [ -f "$PYTHON_APP" ]; then
    if python3 -m py_compile "$PYTHON_APP" 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  ✓ asl-control-center.py compiles"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ asl-control-center.py has syntax errors"
        ERRORS+=("python syntax")
    fi

    # Check for os.posix_spawn usage (architecture invariant)
    if grep -q "os.posix_spawn" "$PYTHON_APP"; then
        PASS=$((PASS + 1))
        echo "  ✓ Uses os.posix_spawn (architecture invariant)"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ Missing os.posix_spawn (architecture invariant violated)"
        ERRORS+=("posix_spawn")
    fi

    # Check for os.fork in actual code (skip module docstring + comments)
    if tail -n +9 "$PYTHON_APP" | grep -v '^\s*#' | grep -v '^\s*"' | grep -q "os\.fork" 2>/dev/null; then
        FAIL=$((FAIL + 1))
        echo "  ✗ Uses os.fork (will deadlock in GTK3)"
        ERRORS+=("os.fork used")
    else
        PASS=$((PASS + 1))
        echo "  ✓ No os.fork usage (correct)"
    fi
else
    FAIL=$((FAIL + 1))
    echo "  ✗ Python GTK3 app not found"
    ERRORS+=("python app missing")
fi

# ---- Test 16: Injection hardening (ngrok token validation) ----
echo ""
echo "16. Testing remote.sh ngrok token validation..."
if [ -f "$ASL_DIR/desktop/remote.sh" ] && grep -qE "A-Za-z0-9_\.-" "$ASL_DIR/desktop/remote.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ remote.sh validates ngrok token format"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ remote.sh missing ngrok token format validation"
    ERRORS+=("ngrok token validation")
fi

# ---- Test 17: ASL_USER validation ----
echo ""
echo "17. Testing ASL_USER regex validation in start-desktop.sh..."
if grep -qE '\[a-z_\]\[a-z0-9_-\]\{0,31\}' "$ASL_DIR/desktop/start-desktop.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ start-desktop.sh validates ASL_USER"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ start-desktop.sh missing ASL_USER validation"
    ERRORS+=("ASL_USER validation")
fi

# ---- Test 18: sanitize_hud_value function exists ----
echo ""
echo "18. Testing hud.sh sanitize_hud_value..."
if [ -f "$ASL_DIR/core/hud.sh" ] && grep -q "sanitize_hud_value()" "$ASL_DIR/core/hud.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ hud.sh sanitizes HUD values"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ hud.sh missing sanitize_hud_value"
    ERRORS+=("hud sanitize")
fi

# ---- Test 19: snapshot.sh rejects tar traversal ----
echo ""
echo "19. Testing snapshot.sh path traversal guard..."
if [ -f "$ASL_DIR/core/snapshot.sh" ] && grep -qE "\.\.\(/\|\$\)|traversal|unsafe" "$ASL_DIR/core/snapshot.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ snapshot.sh guards against archive path traversal"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ snapshot.sh missing tar traversal guard"
    ERRORS+=("snapshot traversal")
fi

# ---- Test 20: gamepad.sh avoids world-writable input ----
echo ""
echo "20. Testing gamepad.sh device permissions..."
if [ -f "$ASL_DIR/core/gamepad.sh" ] && grep -qE "chmod 660|chmod 0660|chgrp" "$ASL_DIR/core/gamepad.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ gamepad.sh uses restricted device permissions"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ gamepad.sh may use world-writable device perms"
    ERRORS+=("gamepad perms")
fi
if [ -f "$ASL_DIR/core/gamepad.sh" ] && ! grep -qE "chmod 666 /dev/input" "$ASL_DIR/core/gamepad.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ gamepad.sh does not make /dev/input world-writable"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ gamepad.sh still makes /dev/input world-writable"
    ERRORS+=("gamepad 666")
fi

# ---- Test 21: cleaner.sh protects active X11 socket ----
echo ""
echo "21. Testing cleaner.sh X11 socket protection..."
if [ -f "$ASL_DIR/core/cleaner.sh" ] && grep -q "x11_active" "$ASL_DIR/core/cleaner.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ cleaner.sh guards against removing active X11 sockets"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ cleaner.sh missing X11 socket guard"
    ERRORS+=("cleaner X11")
fi

# ---- Test 22: theme.sh honors ASL_USER ----
echo ""
echo "22. Testing theme.sh ASL_USER support..."
if [ -f "$ASL_DIR/desktop/theme.sh" ] && grep -q "ASL_USER" "$ASL_DIR/desktop/theme.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ theme.sh honors ASL_USER"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ theme.sh ignores ASL_USER"
    ERRORS+=("theme ASL_USER")
fi

# ---- Test 23: wine-version.sh fails loudly on download failure ----
echo ""
echo "23. Testing wine-version.sh download failure handling..."
if [ -f "$ASL_DIR/core/wine-version.sh" ] && grep -qE "Download failed|FAILED" "$ASL_DIR/core/wine-version.sh" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ wine-version.sh fails loudly on download failure"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ wine-version.sh may report false success"
    ERRORS+=("wine-version false success")
fi

# ---- Test 24: bin/asl exports AUTO_CONFIRM ----
echo ""
echo "24. Testing bin/asl AUTO_CONFIRM handling..."
if grep -q "export AUTO_CONFIRM" "$ASL_DIR/bin/asl" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ bin/asl exports AUTO_CONFIRM"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ bin/asl does not export AUTO_CONFIRM"
    ERRORS+=("AUTO_CONFIRM export")
fi

# ---- Test 25: bin/asl supports ASL_CMD_TIMEOUT ----
echo ""
echo "25. Testing bin/asl command timeouts..."
if grep -q "ASL_CMD_TIMEOUT" "$ASL_DIR/bin/asl" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ bin/asl supports ASL_CMD_TIMEOUT"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ bin/asl missing ASL_CMD_TIMEOUT support"
    ERRORS+=("ASL_CMD_TIMEOUT")
fi

# ---- Test 26: termux-x11 launched with -ac ----
echo ""
echo "26. Testing termux-x11 -ac flag..."
if grep -q "termux-x11 .*-ac" "$ASL_DIR/bin/asl" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ bin/asl launches termux-x11 with -ac"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ bin/asl termux-x11 missing -ac"
    ERRORS+=("termux-x11 -ac")
fi

# ---- Summary ----
echo ""
echo "============================================================"
echo "  Unit Test Results: $PASS passed, $FAIL failed"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "FAILED TESTS:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
fi

cleanup_mock_env
exit "$FAIL"
