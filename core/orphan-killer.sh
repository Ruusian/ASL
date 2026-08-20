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
    local pid comm cmd

    # Find processes matching rogue patterns or high-cpu spin loops
    while read -r pid comm cmd; do
        [ -n "$pid" ] || continue
        # Exclude self and openclaude agent
        [ "$pid" -eq "$$" ] 2>/dev/null && continue
        echo "$cmd" | grep -q "openclaude" && continue

        if echo "$cmd" | grep -qE "hermes-agent|ensurepip|render_dashboard_header" || \
           ([ "$comm" = "python" ] && echo "$cmd" | grep -q "default-pip"); then
            rogue_pids+=("$pid")
            echo "[!] Detected rogue process: PID $pid ($comm) -> $cmd"
        fi
    done < <(ps -ef | awk 'NR>1 {print $2, $8, $0}')

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
    run|scan|kill)
        asl_orphan_kill
        ;;
    *)
        echo "Usage: $0 [run|scan|kill]"
        ;;
esac
