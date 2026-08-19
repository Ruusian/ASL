#!/bin/bash
# ShellCheck lint suite for all ASL bash scripts
# Tests: syntax correctness, common bugs, security issues

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0
RESULTS=()

log_pass() { PASS=$((PASS + 1)); RESULTS+=("PASS  $1"); }
log_fail() { FAIL=$((FAIL + 1)); RESULTS+=("FAIL  $1: $2"); }
log_skip() { SKIP=$((SKIP + 1)); RESULTS+=("SKIP  $1: $2"); }

echo "============================================================"
echo "  ASL ShellCheck Lint Suite"
echo "============================================================"
echo ""

# Collect all bash scripts (skip symlinks, .git, tests)
mapfile -t SCRIPTS < <(find "$SCRIPT_DIR" -name "*.sh" -type f | grep -v '.git/' | grep -v 'tests/' | sort)
# Add bin/asl specifically (no extension)
[ -f "$SCRIPT_DIR/bin/asl" ] && [ ! -L "$SCRIPT_DIR/bin/asl" ] && SCRIPTS+=("$SCRIPT_DIR/bin/asl")
# Add bin/superkit only if it's a real file (not symlink)
[ -f "$SCRIPT_DIR/bin/superkit" ] && [ ! -L "$SCRIPT_DIR/bin/superkit" ] && SCRIPTS+=("$SCRIPT_DIR/bin/superkit")

echo "Found ${#SCRIPTS[@]} scripts to lint"
echo ""

for script in "${SCRIPTS[@]}"; do
    rel="${script#$SCRIPT_DIR/}"

    if [ ! -f "$script" ]; then
        log_skip "$rel" "file not found"
        continue
    fi

    # Skip symlinks (they duplicate the target)
    if [ -L "$script" ]; then
        log_skip "$rel" "symlink (linting target instead)"
        continue
    fi

    # Check if file has content
    if [ ! -s "$script" ]; then
        log_skip "$rel" "empty file"
        continue
    fi

    # Determine shell type
    first_line=$(head -1 "$script" 2>/dev/null || echo "")
    case "$first_line" in
        *bash*) shell="bash" ;;
        *sh*) shell="sh" ;;
        *python*) shell="python" ;;
        *)
            if file "$script" 2>/dev/null | grep -q "text"; then
                shell="bash"
            else
                log_skip "$rel" "not a text script"
                continue
            fi
            ;;
    esac

    if [ "$shell" = "python" ]; then
        log_skip "$rel" "python script (handled separately)"
        continue
    fi

    # Run shellcheck — capture output
    sc_exit=0
    sc_output=$(shellcheck -S warning -e SC1090,SC1091,SC2034,SC2154,SC2086,SC2046,SC2001,SC2116,SC2166 -x "$script" 2>&1) || sc_exit=$?

    if [ "$sc_exit" -eq 0 ]; then
        log_pass "$rel"
    else
        # Count actual warnings/errors
        warn_count=$(echo "$sc_output" | grep -c "^In\|^  " 2>/dev/null || echo 0)
        first_err=$(echo "$sc_output" | grep -m1 "SC[0-9]" | sed 's/.*\(SC[0-9]*\).*/\1/' 2>/dev/null || echo "unknown")
        log_fail "$rel" "${first_err} (exit=$sc_exit)"
    fi
done

echo ""
echo "============================================================"
echo "  ShellCheck Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "============================================================"

# Print failures
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "FAILURES:"
    for r in "${RESULTS[@]}"; do
        case "$r" in
            FAIL*) echo "  $r" ;;
        esac
    done
fi

echo ""
for r in "${RESULTS[@]}"; do
    case "$r" in
        PASS*) echo "  ✓ $r" ;;
        FAIL*) echo "  ✗ $r" ;;
        SKIP*) echo "  - $r" ;;
    esac
done

exit "$FAIL"
