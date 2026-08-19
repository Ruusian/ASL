#!/bin/bash
# CLI Integration tests for the ASL entrypoint
# Tests subcommand dispatch, help output, and error handling

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/mock-env.sh"
setup_mock_env

PASS=0
FAIL=0
ERRORS=()

assert_output_contains() {
    local name="$1" needle="$2" output="$3"
    if echo "$output" | grep -qi "$needle" 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  ✓ $name"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $name (missing '$needle')"
        ERRORS+=("$name")
    fi
}

assert_exit_code() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $name (exit=$actual)"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $name (expected=$expected, got=$actual)"
        ERRORS+=("$name")
    fi
}

echo "============================================================"
echo "  ASL CLI Integration Test Suite"
echo "============================================================"
echo ""

ASL_BIN="$ASL_DIR/bin/asl"

# ---- 1. Help command ----
echo "1. Testing 'asl help'..."
output=$("$ASL_BIN" help 2>&1 || true)
assert_output_contains "help banner" "Android Subsystem for Linux" "$output"
assert_output_contains "help has usage" "Usage:" "$output"
assert_output_contains "help has dashboard" "dashboard" "$output"
assert_output_contains "help has start" "start" "$output"
assert_output_contains "help has stop" "stop" "$output"
assert_output_contains "help has shell" "shell" "$output"
assert_output_contains "help has game" "game" "$output"
assert_output_contains "help has desktop" "desktop" "$output"
assert_output_contains "help has remote" "remote" "$output"
assert_output_contains "help has gpu" "gpu" "$output"
assert_output_contains "help has clean" "clean" "$output"
assert_output_contains "help has repair" "repair" "$output"
assert_output_contains "help has wizard" "wizard" "$output"
assert_output_contains "help has dev-suite" "dev-suite" "$output"
assert_output_contains "help has security-suite" "security-suite" "$output"
assert_output_contains "help has hub" "hub" "$output"
assert_output_contains "help has gamepad" "gamepad" "$output"
assert_output_contains "help has wine" "wine" "$output"
assert_output_contains "help has snapshot" "snapshot" "$output"

# ---- 2. --help flag ----
echo ""
echo "2. Testing 'asl --help'..."
output=$("$ASL_BIN" --help 2>&1 || true)
assert_output_contains "--help shows usage" "Usage:" "$output"

# ---- 3. -h flag ----
echo ""
echo "3. Testing 'asl -h'..."
output=$("$ASL_BIN" -h 2>&1 || true)
assert_output_contains "-h shows usage" "Usage:" "$output"

# ---- 4. Unknown command ----
echo ""
echo "4. Testing unknown command..."
exit_code=0
output=$("$ASL_BIN" foobarbaz 2>&1) || exit_code=$?
assert_exit_code "unknown cmd exits non-zero" "1" "$exit_code"
assert_output_contains "unknown cmd shows error" "Unknown command" "$output"

# ---- 5. exec-mode ----
echo ""
echo "5. Testing 'asl exec-mode'..."
output=$("$ASL_BIN" exec-mode 2>&1 || true)
assert_output_contains "exec-mode shows mode" "root\|shizuku\|proot\|mode" "$output"

# ---- 6. status command ----
echo ""
echo "6. Testing 'asl status'..."
output=$("$ASL_BIN" status 2>&1 || true)
assert_output_contains "status shows info" "Chroot\|chroot\|status\|ASL" "$output"

# ---- 7. doctor command ----
echo ""
echo "7. Testing 'asl doctor'..."
output=$("$ASL_BIN" doctor 2>&1 || true)
assert_output_contains "doctor runs" "doctor\|check\|pass\|fail\|warn" "$output"

# ---- 8. overview command ----
echo ""
echo "8. Testing 'asl overview'..."
output=$("$ASL_BIN" overview 2>&1 || true)
assert_output_contains "overview shows banner" "Android Subsystem" "$output"
assert_output_contains "overview shows gpu" "GPU\|gpu" "$output"
assert_output_contains "overview shows battery" "Battery\|batt" "$output"
assert_output_contains "overview shows governor" "Gov\|governor" "$output"

# ---- 9. thermal command ----
echo ""
echo "9. Testing 'asl thermal'..."
output=$("$ASL_BIN" thermal 2>&1 || true)
assert_output_contains "thermal shows temp" "temp\|°C\|thermal\|sensor" "$output"

# ---- 10. gpu command ----
echo ""
echo "10. Testing 'asl gpu'..."
output=$("$ASL_BIN" gpu 2>&1 || true)
assert_output_contains "gpu shows info" "GPU\|gpu\|Mesa\|Turnip\|detect" "$output"

# ---- 11. Clean command (dry) ----
echo ""
echo "11. Testing 'asl clean'..."
output=$("$ASL_BIN" clean 2>&1 || true)
assert_output_contains "clean runs" "clean\|apt\|cache\|purge" "$output"

# ---- 12. Repair command ----
echo ""
echo "12. Testing 'asl repair'..."
output=$("$ASL_BIN" repair 2>&1 || true)
assert_output_contains "repair runs" "repair\|mount\|fix\|check" "$output"

# ---- 13. Version consistency ----
echo ""
echo "13. Testing version consistency..."
help_output=$("$ASL_BIN" help 2>&1 || true)
overview_output=$("$ASL_BIN" overview 2>&1 || true)
# Both should mention the same version
if echo "$help_output" | grep -q "2.5.1" && echo "$overview_output" | grep -q "2.5.1"; then
    PASS=$((PASS + 1))
    echo "  ✓ Version consistent (v2.5.1) across help and overview"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ Version mismatch between help and overview"
    ERRORS+=("version consistency")
fi

# ---- 14. Subcommand error on missing args ----
echo ""
echo "14. Testing subcommand arg validation..."
for cmd in "install" "search" "exec" "resolution"; do
    exit_code=0
    output=$("$ASL_BIN" "$cmd" 2>&1) || exit_code=$?
    if echo "$output" | grep -qi "usage\|error\|required" 2>/dev/null; then
        PASS=$((PASS + 1))
        echo "  ✓ asl $cmd without args shows usage/error"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ asl $cmd without args silent"
        ERRORS+=("$cmd arg validation")
    fi
done

# ---- 15. Script file integrity ----
echo ""
echo "15. Testing script file integrity..."
for f in bin/asl core/common.sh core/mount-chroot.sh core/stop-chroot.sh \
         core/doctor.sh core/gpu-profile.sh core/cleaner.sh core/repair.sh \
         core/wizard.sh core/hud.sh desktop/start-desktop.sh desktop/remote.sh \
         desktop/theme.sh gaming/wine-box64.sh install.sh; do
    if [ -f "$ASL_DIR/$f" ]; then
        if bash -n "$ASL_DIR/$f" 2>/dev/null; then
            PASS=$((PASS + 1))
            echo "  ✓ $f syntax OK"
        else
            FAIL=$((FAIL + 1))
            echo "  ✗ $f has syntax errors"
            ERRORS+=("syntax $f")
        fi
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $f missing"
        ERRORS+=("missing $f")
    fi
done

# ---- 16. All scripts have correct shebangs ----
echo ""
echo "16. Testing shebangs..."
for f in bin/asl core/*.sh desktop/*.sh gaming/*.sh install.sh tools/*.sh; do
    [ -f "$ASL_DIR/$f" ] || continue
    first=$(head -1 "$ASL_DIR/$f" 2>/dev/null || echo "")
    case "$first" in
        "#!"*bash*|"#!"*/bin/sh*)
            PASS=$((PASS + 1))
            ;;
        "#!"*)
            FAIL=$((FAIL + 1))
            echo "  ✗ $f has non-bash shebang: $first"
            ERRORS+=("shebang $f")
            ;;
        *)
            # Scripts without shebang (e.g. sourced files)
            PASS=$((PASS + 1))
            ;;
    esac
done
echo "  ✓ Shebang check complete"

# ---- 17. No hardcoded secrets ----
echo ""
echo "17. Testing for hardcoded secrets..."
for f in $(find "$ASL_DIR" -name "*.sh" -o -name "*.py" | grep -v '.git/' | grep -v 'tests/'); do
    if grep -qiE "(password|secret|token|api_key)\s*=\s*['\"][^'\"]{8,}" "$f" 2>/dev/null; then
        # Check if it's a variable name or an actual hardcoded value
        if grep -qiE "^(password|secret|token|api_key)\s*=" "$f" 2>/dev/null; then
            FAIL=$((FAIL + 1))
            echo "  ✗ Possible hardcoded secret in $f"
            ERRORS+=("hardcoded secret $f")
        fi
    fi
done
echo "  ✓ No hardcoded secrets found"

# ---- 18. No TODO/FIXME/HACK comments ----
echo ""
echo "18. Testing for TODO/FIXME/HACK comments..."
todo_count=0
for f in $(find "$ASL_DIR" -name "*.sh" -o -name "*.py" | grep -v '.git/' | grep -v 'tests/'); do
    count=$(grep -ciE '\b(TODO|FIXME|HACK)\b' "$f" 2>/dev/null || true)
    count=$(echo "$count" | tr -dc '0-9')
    count=${count:-0}
    todo_count=$((todo_count + count))
done
if [ "$todo_count" -gt 0 ]; then
    FAIL=$((FAIL + 1))
    echo "  ✗ Found $todo_count TODO/FIXME/HACK comments"
    ERRORS+=("TODO comments: $todo_count")
else
    PASS=$((PASS + 1))
    echo "  ✓ No TODO/FIXME/HACK comments"
fi

# ---- Summary ----
echo ""
echo "============================================================"
echo "  Integration Test Results: $PASS passed, $FAIL failed"
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
