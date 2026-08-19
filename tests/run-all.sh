#!/bin/bash
# Master test runner for ASL
# Runs all test suites and produces a consolidated report

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            ASL Test Suite — Full Test Run                   ║"
echo "║            $(date '+%Y-%m-%d %H:%M:%S')                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SUITES_RUN=0
SUITES_PASSED=0

run_suite() {
    local name="$1" script="$2"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    SUITES_RUN=$((SUITES_RUN + 1))
    local exit_code=0
    local log_file="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/asl-test-$script.log"
    bash "$SCRIPT_DIR/$script" 2>&1 | tee "$log_file" || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        SUITES_PASSED=$((SUITES_PASSED + 1))
    fi

    # Parse results from the log
    local pass fail skip
    pass=$(awk '/[0-9]+ passed/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1) ~ /^passed/) print $i}' "$log_file" 2>/dev/null | tail -n 1 || echo "0")
    fail=$(awk '/[0-9]+ failed/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1) ~ /^failed/) print $i}' "$log_file" 2>/dev/null | tail -n 1 || echo "0")
    skip=$(awk '/[0-9]+ skipped/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1) ~ /^skipped/) print $i}' "$log_file" 2>/dev/null | tail -n 1 || echo "0")

    TOTAL_PASS=$((TOTAL_PASS + ${pass:-0}))
    TOTAL_FAIL=$((TOTAL_FAIL + ${fail:-0}))
    TOTAL_SKIP=$((TOTAL_SKIP + ${skip:-0}))

    echo ""
    echo ""
}

# Run all suites
run_suite "ShellCheck Lint Suite" "test-shellcheck.sh"
run_suite "Unit Test Suite" "test-unit.sh"
run_suite "CLI Integration Test Suite" "test-integration.sh"
run_suite "Stress Test Suite" "test-stress.sh"

# ---- Final Report ----
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   CONSOLIDATED RESULTS                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Suites Run:     $SUITES_RUN / 4                                         ║"
echo "║  Suites Passed:  $SUITES_PASSED / 4                                         ║"
echo "║                                                             ║"
echo "║  Total Passed:   $TOTAL_PASS                                            ║"
echo "║  Total Failed:   $TOTAL_FAIL                                            ║"
echo "║  Total Skipped:  $TOTAL_SKIP                                            ║"
echo "║                                                             ║"

TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
if [ "$TOTAL" -gt 0 ]; then
    RATE=$((TOTAL_PASS * 100 / TOTAL))
    echo "║  Pass Rate:      ${RATE}%                                             ║"
fi

echo "╠══════════════════════════════════════════════════════════════╣"

if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "║  STATUS:  ✓ ALL TESTS PASSED                               ║"
else
    echo "║  STATUS:  ✗ $TOTAL_FAIL TESTS FAILED                                ║"
fi

echo "╚══════════════════════════════════════════════════════════════╝"

# Cleanup
rm -rf /tmp/asl-test-*.log /tmp/asl-mock 2>/dev/null

exit "$TOTAL_FAIL"
