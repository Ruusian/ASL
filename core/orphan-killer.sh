#!/bin/bash
# ASL: Automated Orphan Process Killer & Fail-Safe Reboot System
# Detects and terminates rogue background spin-loops (e.g. hermes-agent, stuck python pip, orphaned dashboards).
# If a stuck process cannot be killed due to kernel D-state lock, triggers an automatic system reboot.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_orphan_kill() {
    echo "[*] Running ASL Orphan Process Scan & Cleanup..."
    local rogue_pids=()
    local pid comm pcpu etime cmd
    local my_pid="$$"

    # Find processes matching rogue patterns or high-cpu python/agent spin loops
    while read -r pid comm pcpu etime cmd; do
        [ -n "$pid" ] || continue
        # Exclude self, openclaude, and hermes agent runner
        [ "$pid" -eq "$my_pid" ] 2>/dev/null && continue
        echo "$cmd" | grep -qE "openclaude|claude-code|hermes" && continue

        # Match known stuck background spin-loop signatures (py3compile, node-gyp, stuck pip)
        if echo "$cmd" | grep -qE "ensurepip|render_dashboard_header|py3compile|gyp_main\.py|node-gyp" || \
           (echo "$comm" | grep -qE "python|python3" && (echo "$cmd" | grep -qE "default-pip|pkg_resources" || [ "${pcpu%.*}" -gt 30 2>/dev/null ])); then
            rogue_pids+=("$pid")
            echo "[!] Detected rogue/stuck process: PID $pid ($comm, CPU: ${pcpu}%, Time: $etime) -> $cmd"
        fi
    done < <(ps -eo pid,comm,pcpu,etime,args 2>/dev/null | awk 'NR>1 {pid=$1; comm=$2; pcpu=$3; etime=$4; $1=""; $2=""; $3=""; $4=""; print pid, comm, pcpu, etime, $0}')

    # Also scan inside Debian chroot if mounted
    if is_mounted "$DEBIANPATH" 2>/dev/null; then
        while read -r pid comm pcpu etime cmd; do
            [ -n "$pid" ] || continue
            [ "$pid" -eq "$my_pid" ] 2>/dev/null && continue
            echo "$cmd" | grep -qE "openclaude|claude-code|hermes" && continue
            if echo "$cmd" | grep -qE "ensurepip|render_dashboard_header|py3compile|gyp_main\.py|node-gyp" || \
               (echo "$comm" | grep -qE "python|python3" && (echo "$cmd" | grep -qE "default-pip|pkg_resources" || [ "${pcpu%.*}" -gt 30 2>/dev/null ])); then
                # Check if already added
                local already=0
                for existing in "${rogue_pids[@]}"; do
                    [ "$existing" -eq "$pid" ] 2>/dev/null && { already=1; break; }
                done
                if [ "$already" -eq 0 ]; then
                    rogue_pids+=("$pid")
                    echo "[!] Detected rogue chroot process: PID $pid ($comm, CPU: ${pcpu}%, Time: $etime) -> $cmd"
                fi
            fi
        done < <(asl_exec "ps -eo pid,comm,pcpu,etime,args" 2>/dev/null | awk 'NR>1 {pid=$1; comm=$2; pcpu=$3; etime=$4; $1=""; $2=""; $3=""; $4=""; print pid, comm, pcpu, etime, $0}')
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

    sleep 2

    # Check if any rogue PID is still alive (kernel D-state lock)
    local unkillable=0
    for rpid in "${rogue_pids[@]}"; do
        if ps -p "$rpid" >/dev/null 2>&1 || su -c "ps -p $rpid" >/dev/null 2>&1; then
            echo "[!] CRITICAL: PID $rpid is stuck in uninterruptible kernel state (unkillable)."
            unkillable=1
        fi
    done

    if [ "$unkillable" -eq 1 ]; then
        echo "[!] WARNING: Unkillable kernel threads detected (processes in D-state)."
        echo "[!] Recommended action: Run 'asl restart' or restart the container."
        if [ "$ASL_FORCE_REBOOT" = "1" ] || [ "$1" = "--force-reboot" ]; then
            echo "[!] Fail-Safe System Triggered: Force-reboot flag detected. Rebooting in 3s..."
            sleep 3
            if command -v su &>/dev/null; then
                su -c "reboot"
            else
                echo "[!] su not available to reboot."
            fi
            exit 1
        else
            echo "[*] Skipping automatic reboot (pass --force-reboot or ASL_FORCE_REBOOT=1 to force)."
            return 1
        fi
    else
        echo "[✓] All rogue orphan processes successfully killed."
        return 0
    fi
}

case "${1:-run}" in
    run|scan|kill|status|check|list)
        asl_orphan_kill
        ;;
    *)
        echo "Usage: $0 [run|scan|kill|status]"
        ;;
esac
