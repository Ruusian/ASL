#!/bin/bash
# ASL: Memory Management & Swap Tuning
# Optimizes memory usage for constrained Android environments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_swap_status() {
    local c_reset=$'\033[0m' c_bold=$'\033[1m' c_cyan=$'\033[36m'
    local c_green=$'\033[32m' c_yellow=$'\033[33m' c_red=$'\033[31m'

    printf '%s=== ASL Memory & Swap Status ===%s\n' "$c_cyan$c_bold" "$c_reset"

    # Physical memory
    echo ""
    echo "Physical Memory:"
    free -h 2>/dev/null | grep -E "^Mem:|^Swap:" || echo "  Unable to read memory info"

    # ZRAM status
    echo ""
    echo "ZRAM Status:"
    if [ -d /sys/block/zram0 ]; then
        local zram_size zram_used zram_comp algo
        zram_size=$(cat /sys/block/zram0/disksize 2>/dev/null || echo "0")
        zram_used=$(cat /sys/block/zram0/mm_stat 2>/dev/null | awk '{print $3}' || echo "0")
        algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "unknown")
        
        if [ "$zram_size" -gt 0 ]; then
            local zram_size_mb=$((zram_size / 1024 / 1024))
            local zram_used_mb=$((zram_used / 1024 / 1024))
            echo "  Algorithm: $algo"
            echo "  Size: ${zram_size_mb}MB"
            echo "  Used: ${zram_used_mb}MB"
            echo "  Usage: $((zram_used * 100 / zram_size))%"
        else
            echo "  ZRAM not active"
        fi
    else
        echo "  ZRAM not available"
    fi

    # File swap status
    echo ""
    echo "File Swap:"
    local swap_info
    swap_info=$(swapon --show 2>/dev/null | grep -v "Name" || true)
    if [ -n "$swap_info" ]; then
        echo "$swap_info"
    else
        echo "  No file swap active"
    fi

    # OOM protection status
    echo ""
    echo "OOM Protection:"
    local asl_pid
    asl_pid=$(pgrep -f "asl.*service" 2>/dev/null | head -1 || true)
    if [ -n "$asl_pid" ]; then
        local oom_score
        oom_score=$(cat /proc/$asl_pid/oom_score_adj 2>/dev/null || echo "unknown")
        echo "  ASL PID: $asl_pid (oom_score_adj: $oom_score)"
    else
        echo "  ASL service not running"
    fi

    # Top memory consumers
    echo ""
    echo "Top Memory Consumers:"
    ps aux 2>/dev/null | sort -rnk4 | head -5 | awk '{printf "  %-8s %5s%% %s\n", $1, $4, $11}'
}

asl_swap_setup() {
    echo "[*] Setting up memory optimization..."

    # Create 2GB swap file if it doesn't exist
    local swapfile="$HOME/swapfile"
    if [ ! -f "$swapfile" ]; then
        echo "[*] Creating 2GB swap file..."
        fallocate -l 2G "$swapfile" 2>/dev/null || dd if=/dev/zero of="$swapfile" bs=1M count=2048 2>/dev/null
        chmod 600 "$swapfile"
        mkswap "$swapfile" 2>/dev/null
        echo "[✓] Swap file created"
    fi

    # Enable swap if not already active
    if ! swapon --show 2>/dev/null | grep -q "$swapfile"; then
        echo "[*] Enabling swap..."
        swapon "$swapfile" 2>/dev/null
        echo "[✓] Swap enabled"
    fi

    # Set swappiness (prefer keeping Linux processes in RAM)
    echo "[*] Setting swappiness to 10..."
    sysctl -w vm.swappiness=10 2>/dev/null || su -c "sysctl -w vm.swappiness=10" 2>/dev/null || echo "  Warning: Could not set swappiness (needs root)"

    # Protect critical processes from OOM killer
    echo "[*] Setting OOM protection for critical processes..."
    local critical_pids
    critical_pids=$(pgrep -f "(box64|wine|pulseaudio|sshd)" 2>/dev/null || true)
    for pid in $critical_pids; do
        echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
    done

    echo "[✓] Memory optimization complete"
}

asl_swap_optimize() {
    echo "[*] Running memory optimization..."

    # Drop caches to free up memory
    echo "[*] Dropping caches..."
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || su -c "echo 3 > /proc/sys/vm/drop_caches" 2>/dev/null || echo "  Warning: Could not drop caches (needs root)"

    # Compress memory more aggressively
    echo "[*] Optimizing ZRAM compression..."
    if [ -d /sys/block/zram0 ]; then
        echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || su -c "echo lz4 > /sys/block/zram0/comp_algorithm" 2>/dev/null || true
    fi

    # Kill unnecessary background apps
    echo "[*] Stopping unnecessary background apps..."
    local heavy_apps
    heavy_apps=$(ps aux 2>/dev/null | awk '$4 > 5.0 {print $2}' | head -5 || true)
    for pid in $heavy_apps; do
        local proc_name
        proc_name=$(ps -p "$pid" -o comm= 2>/dev/null || true)
        case "$proc_name" in
            *chrome*|*firefox*|*gallery*|*camera*)
                echo "  Stopping $proc_name (PID: $pid)"
                kill -STOP "$pid" 2>/dev/null || true
                ;;
        esac
    done

    echo "[✓] Memory optimization complete"
}

asl_swap_cleanup() {
    echo "[*] Cleaning up swap configuration..."

    # Disable swap
    local swapfile="$HOME/swapfile"
    if [ -f "$swapfile" ]; then
        swapoff "$swapfile" 2>/dev/null || true
        echo "[✓] Swap disabled"
    fi

    echo "[✓] Cleanup complete"
}

case "${1:-status}" in
    status|report|info)
        asl_swap_status
        ;;
    setup|init)
        asl_swap_setup
        ;;
    optimize|clean)
        asl_swap_optimize
        ;;
    cleanup|remove)
        asl_swap_cleanup
        ;;
    *)
        echo "Usage: $0 {status|setup|optimize|cleanup}"
        ;;
esac
