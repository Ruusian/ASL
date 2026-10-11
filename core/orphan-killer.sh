#!/bin/bash
# ASL: Automated Orphan Process Killer & Fail-Safe Reboot System
# Detects and terminates rogue background spin-loops (e.g. stuck python pip, orphaned processes).
# Optimized with awk for instant sub-second scan times.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

filter_orphans() {
    awk -v my_pid="$$" 'NR>1 {
        pid = $1
        comm = $2
        pcpu = $3 + 0
        etime = $4
        cmd = $0
        sub(/^ *[0-9]+ +[^ ]+ +[^ ]+ +[^ ]+ +/, "", cmd)

        if (pid == my_pid) next
        if (cmd ~ /(openclaude|claude-code|free-web-search)/) next

        if (cmd ~ /(ensurepip|render_dashboard_header|py3compile|gyp_main\.py|node-gyp)/ ||
           (comm ~ /python/ && (cmd ~ /(default-pip|pkg_resources)/ || pcpu > 30))) {
            print pid, comm, pcpu, etime, cmd
        }
    }'
}

asl_orphan_kill() {
    local force_reboot="${1:-}"
    echo "[*] Running ASL Orphan Process Scan & Cleanup..."
    local rogue_pids=()

    # 1. Fast scan host processes
    while read -r pid comm pcpu etime cmd; do
        [ -n "$pid" ] || continue
        rogue_pids+=("$pid")
        echo "[!] Detected rogue/stuck process: PID $pid ($comm, CPU: ${pcpu}%, Time: $etime) -> $cmd"
    done < <(ps -eo pid,comm,pcpu,etime,args 2>/dev/null | filter_orphans)

    # 2. Fast scan chroot processes if mounted
    if is_mounted 2>/dev/null; then
        while read -r pid comm pcpu etime cmd; do
            [ -n "$pid" ] || continue
            local already=0
            for existing in "${rogue_pids[@]}"; do
                [ "$existing" -eq "$pid" ] 2>/dev/null && { already=1; break; }
            done
            if [ "$already" -eq 0 ]; then
                rogue_pids+=("$pid")
                echo "[!] Detected rogue chroot process: PID $pid ($comm, CPU: ${pcpu}%, Time: $etime) -> $cmd"
            fi
        done < <(asl_exec "ps -eo pid,comm,pcpu,etime,args" 2>/dev/null | filter_orphans)
    fi

    if [ ${#rogue_pids[@]} -eq 0 ]; then
        echo "[✓] No rogue orphan processes detected."
        return 0
    fi

    echo "[*] Attempting SIGKILL on ${#rogue_pids[@]} rogue process(es)..."
    for rpid in "${rogue_pids[@]}"; do
        if su -c "kill -9 $rpid" 2>/dev/null || kill -9 "$rpid" 2>/dev/null; then
            echo "  - Sent SIGKILL to PID $rpid"
        fi
    done

    sleep 1

    # Check if any rogue PID is still alive
    local unkillable=0
    for rpid in "${rogue_pids[@]}"; do
        if ps -p "$rpid" >/dev/null 2>&1 || su -c "ps -p $rpid" >/dev/null 2>&1; then
            echo "[!] CRITICAL: PID $rpid is stuck in uninterruptible kernel state (unkillable)."
            unkillable=1
        fi
    done

    if [ "$unkillable" -eq 1 ]; then
        echo "[!] WARNING: Unkillable kernel threads detected (processes in D-state)."
        return 1
    else
        echo "[✓] All rogue orphan processes successfully killed."
        return 0
    fi
}

case "${1:-run}" in
    run|scan|kill|status|check|list)
        asl_orphan_kill "${2:-}"
        ;;
    *)
        echo "Usage: $0 [run|scan|kill|status]"
        ;;
esac
