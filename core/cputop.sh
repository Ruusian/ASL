#!/bin/bash
# ASL: Real-Time Process CPU & Resource Monitor
# Measures true sustained CPU utilization per process by sampling /proc/[pid]/stat delta.
# Avoids misleading lifetime-averaged %CPU reported by standard ps.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
SECS="${1:-4}"
# Ensure valid integer interval
[[ "$SECS" =~ ^[0-9]+$ ]] || SECS=4
[ "$SECS" -lt 1 ] && SECS=1

TD="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
mkdir -p "$TD" 2>/dev/null || true
BASE="$TD/.asl_cputop_base.$$"
NOW="$TD/.asl_cputop_now.$$"

cleanup() {
    rm -f "$BASE" "$NOW" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

snapshot() {
    local pid line rest ut st
    for p in /proc/[0-9]*; do
        pid=${p#/proc/}
        read -r line < "$p/stat" 2>/dev/null || continue
        rest=${line#*") "}
        # shellcheck disable=SC2086
        set -- $rest
        ut=${12}
        st=${13}
        [ -n "$ut" ] && echo "$pid $((ut + st))"
    done
}

echo "=== ASL Real-Time Sustained CPU Monitor ==="
echo "Sampling active processes for ${SECS}s (CLK_TCK=$HZ)..."

snapshot > "$BASE"
sleep "$SECS"
snapshot > "$NOW"

echo ""
printf "  %-8s %6s  %-12s %-6s %s\n" "PID" "%CPU" "RSS (RAM)" "THREAD" "COMMAND"
printf "  %-8s %6s  %-12s %-6s %s\n" "---" "----" "---------" "------" "-------"

awk -v hz="$HZ" -v secs="$SECS" '
  NR==FNR { base[$1]=$2; next }
  { pid=$1; cur=$2;
    if (pid in base) {
      d = cur - base[pid]
      if (d > 0) printf "%d\t%d\n", pid, int(d*100/(hz*secs))
    }
  }' "$BASE" "$NOW" |
while IFS=$'\t' read -r pid pct; do
    [ "$pct" -ge 1 ] || continue
    name=$(cat "/proc/$pid/comm" 2>/dev/null)
    rss=$(awk '/^VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null)
    th=$(awk '/^Threads/{print $2}' "/proc/$pid/status" 2>/dev/null)
    [ -n "$rss" ] && rss="${rss}k" || rss="-"
    printf "  %-8s %5s%%  %-12s %-6s %s\n" "$pid" "$pct" "$rss" "${th:--}" "$name"
done | sort -k2 -rn | head -25
