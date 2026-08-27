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
        zram_size=$(cat /sys/block/zram0/disksize 2>/dev/null || su -c "cat /sys/block/zram0/disksize" 2>/dev/null)
        zram_size=$(printf '%s' "$zram_size" | tr -d '[:space:]')
        zram_used=$( (cat /sys/block/zram0/mm_stat 2>/dev/null || su -c "cat /sys/block/zram0/mm_stat" 2>/dev/null) | awk '{print $3}')
        zram_used=$(printf '%s' "$zram_used" | tr -d '[:space:]')
        algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || su -c "cat /sys/block/zram0/comp_algorithm" 2>/dev/null || echo "unknown")
        [[ "$zram_size" =~ ^[0-9]+$ ]] || zram_size=0
        [[ "$zram_used" =~ ^[0-9]+$ ]] || zram_used=0

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

    # Active Swap Devices
    echo ""
    echo "Active Swap Devices:"
    local swaps_out=""
    if [ "$(id -u)" -eq 0 ]; then
        swaps_out=$(cat /proc/swaps 2>/dev/null || true)
    elif su -c "id" >/dev/null 2>&1; then
        swaps_out=$(su -c "cat /proc/swaps" 2>/dev/null || true)
    fi
    if [ -n "$swaps_out" ]; then
        echo "$swaps_out"
    else
        echo "  No swap devices active"
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
    local target_size="${1:-5G}"
    echo "[*] Setting up $target_size virtual swap pool & memory optimization..."

    local swapfile="/data/local/tmp/asl_swap.img"
    if [ ! -f "$swapfile" ]; then
        echo "[*] Creating $target_size swap image..."
        su -c "swapoff -a 2>/dev/null || true" 2>/dev/null || swapoff -a 2>/dev/null || true
        su -c "fallocate -l $target_size '$swapfile' || dd if=/dev/zero of='$swapfile' bs=1M count=5120" 2>/dev/null || fallocate -l $target_size "$swapfile" 2>/dev/null || dd if=/dev/zero of="$swapfile" bs=1M count=5120 2>/dev/null || true
        su -c "chmod 600 '$swapfile' && mkswap '$swapfile'" 2>/dev/null || (chmod 600 "$swapfile" && mkswap "$swapfile") 2>/dev/null || true
        echo "[✓] $target_size swap image created."
    fi

    # Ensure only ONE loop device is attached and active for the swap image
    local active_swap_loops
    active_swap_loops=$(su -c "losetup -j '$swapfile'" 2>/dev/null | cut -d: -f1 || losetup -j "$swapfile" 2>/dev/null | cut -d: -f1 || true)
    local count=0
    for dev in $active_swap_loops; do
        count=$((count + 1))
        if [ $count -gt 1 ]; then
            echo "[*] Detaching duplicate swap loop device $dev..."
            su -c "swapoff '$dev' 2>/dev/null || true; losetup -d '$dev' 2>/dev/null || true" 2>/dev/null || true
        fi
    done

    local is_active=0
    if [ "$(id -u)" -eq 0 ]; then
        grep -q "$swapfile\|loop" /proc/swaps 2>/dev/null && is_active=1
    else
        su -c "cat /proc/swaps" 2>/dev/null | grep -q "$swapfile\|loop" && is_active=1
    fi

    if [ "$is_active" -eq 0 ]; then
        echo "[*] Attaching 5GB swap loop device..."
        if [ "$(id -u)" -eq 0 ]; then
            loopdev=$(losetup -f 2>/dev/null || true)
            if [ -n "$loopdev" ]; then
                losetup "$loopdev" "$swapfile" 2>/dev/null && swapon "$loopdev" 2>/dev/null && echo "[✓] 5GB Swap enabled." || echo "[!] Swap mount skipped."
            else
                swapon "$swapfile" 2>/dev/null && echo "[✓] 5GB Swap enabled." || echo "[!] Swap mount skipped."
            fi
        else
            su -c "loopdev=\$(losetup -f) && losetup \$loopdev '$swapfile' && swapon \$loopdev" 2>/dev/null && echo "[✓] 5GB Swap enabled." || echo "[!] Swap mount skipped or active."
        fi
    else
        echo "[✓] Swap already active."
    fi

    # Set swappiness (prefer keeping Linux processes in RAM)
    echo "[*] Setting swappiness to 10..."
    sysctl -w vm.swappiness=10 2>/dev/null || su -c "sysctl -w vm.swappiness=10" 2>/dev/null || echo "  Warning: Could not set swappiness (needs root)"

    # Protect critical processes from OOM killer
    echo "[*] Setting OOM protection for critical processes..."
    local critical_pids
    critical_pids=$(pgrep -f "(pulseaudio|sshd|xfce4-session|dbus-daemon)" 2>/dev/null || true)
    for pid in $critical_pids; do
        if [ -n "$pid" ]; then
            su -c "echo -1000 > /proc/$pid/oom_score_adj" 2>/dev/null || echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
        fi
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

    local swapfile="/data/local/tmp/asl_swap.img"
    local cleanup_cmd="
        for loop in \$(losetup -j '$swapfile' 2>/dev/null | cut -d: -f1); do
            swapoff \"\$loop\" 2>/dev/null || true
            losetup -d \"\$loop\" 2>/dev/null || true
        done
        swapoff '$swapfile' 2>/dev/null || true
        echo '[✓] 5GB swap disabled and loop devices detached'
    "

    if [ "$(id -u)" -eq 0 ]; then
        eval "$cleanup_cmd"
    elif su -c "id" >/dev/null 2>&1; then
        su -c "$cleanup_cmd"
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
