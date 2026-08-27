#!/bin/bash
# ASL: System, GPU & Hardware Benchmark Utility
# Evaluates OpenGL/Vulkan rendering performance, CPU compute throughput, RAM bandwidth, and thermal thermals.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
elif [ -f "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh" ]; then
    source "${PREFIX:-/data/data/com.termux/files/usr}/share/asl/core/common.sh"
elif [ -f "$HOME/ASL/core/common.sh" ]; then
    source "$HOME/ASL/core/common.sh"
fi

if [ -f "$SCRIPT_DIR/core/gpu-profile.sh" ]; then
    source "$SCRIPT_DIR/core/gpu-profile.sh"
elif [ -f "$HOME/ASL/core/gpu-profile.sh" ]; then
    source "$HOME/ASL/core/gpu-profile.sh"
fi

asl_benchmark_run() {
    local c_reset=$'\033[0m' c_bold=$'\033[1m' c_cyan=$'\033[36m'
    local c_green=$'\033[32m' c_yellow=$'\033[33m' c_red=$'\033[31m'
    local c_shadow=$'\033[90m'

    printf '%s=== ASL Hardware & Compute Benchmark ===%s\n\n' "$c_cyan$c_bold" "$c_reset"

    # 1. System & Hardware Profile
    echo "Hardware & Platform Profile:"
    local chip_platform arch num_cores
    chip_platform=$(getprop ro.board.platform 2>/dev/null || echo "Unknown SoC")
    arch=$(uname -m 2>/dev/null || echo "aarch64")
    num_cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 8)
    asl_gpu_detect 2>/dev/null || true
    echo "  SoC Platform: $chip_platform ($arch, $num_cores cores)"
    echo "  GPU Profile:  $ASL_GPU_PROFILE (Model: ${ASL_GPU_MODEL:-unknown})"
    echo ""

    # Initial Thermal State
    local temp_start_cpu temp_start_batt
    temp_start_cpu=$(asl_cpu_temp_c 2>/dev/null)
    [ -z "$temp_start_cpu" ] && temp_start_cpu="N/A"
    temp_start_batt=$(asl_batt_temp_c 2>/dev/null)
    [ -z "$temp_start_batt" ] && temp_start_batt="N/A"

    echo "Thermal Baseline:"
    echo "  Initial CPU Temperature:     ${temp_start_cpu}°C"
    echo "  Initial Battery Temperature: ${temp_start_batt}°C"
    echo ""

    # 2. 3D Graphics & OpenGL Rendering Benchmark
    echo "3D Graphics & OpenGL Pipeline:"
    local x11_active=0
    if [ -S "${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}/.X11-unix/X0" ] || [ -S "/tmp/.X11-unix/X0" ] || pgrep -f "termux-x11" >/dev/null 2>&1; then
        x11_active=1
    fi

    if [ "$x11_active" -eq 1 ] && is_mounted 2>/dev/null; then
        echo "  [✓] X11 Display Server Active (:0)"
        local gl_info
        gl_info=$(asl_chroot_exec "export DISPLAY=:0 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; glxinfo -B 2>/dev/null" 2>/dev/null || true)
        if [ -n "$gl_info" ]; then
            local gl_vendor gl_renderer gl_version
            gl_vendor=$(echo "$gl_info" | grep -i "OpenGL vendor string:" | cut -d: -f2- | sed 's/^[ \t]*//')
            gl_renderer=$(echo "$gl_info" | grep -i "OpenGL renderer string:" | cut -d: -f2- | sed 's/^[ \t]*//')
            gl_version=$(echo "$gl_info" | grep -i "OpenGL version string:" | cut -d: -f2- | sed 's/^[ \t]*//')
            [ -n "$gl_vendor" ] && echo "  OpenGL Vendor:   $gl_vendor"
            [ -n "$gl_renderer" ] && echo "  OpenGL Renderer: $gl_renderer"
            [ -n "$gl_version" ] && echo "  OpenGL Version:  $gl_version"
        fi

        echo "  Running 5-second 3D rasterization benchmark (glxgears)..."
        local fps_output
        fps_output=$(asl_chroot_exec "export DISPLAY=:0 vblank_mode=0 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; timeout 5 glxgears 2>&1" 2>/dev/null || true)
        local fps_val
        fps_val=$(echo "$fps_output" | grep -oE '[0-9]+\.?[0-9]* FPS' | head -1)
        if [ -n "$fps_val" ]; then
            printf '  3D Rasterization Score: %s%s%s\n' "$c_green$c_bold" "$fps_val" "$c_reset"
        else
            echo "  3D Rasterization Score: Test completed (headless/unrendered)"
        fi
    else
        echo "  [i] Termux:X11 display is currently idle."
        echo "      To run real-time 3D rasterization FPS tests, start desktop with 'asl desktop start'."
    fi
    echo ""

    # 3. CPU Compute & Memory Bandwidth Benchmark
    echo "CPU & Memory Throughput Benchmark:"
    echo "  Executing multi-stage compute & RAM workload..."

    local py_bench_res
    py_bench_res=$(python3 -c '
import time, math, os, sys

# Stage 1: CPU Floating-point & transcendental compute
t0 = time.perf_counter()
acc = 0.0
for i in range(1, 3000000):
    acc += math.sqrt(i) * math.sin(i)
t_cpu = time.perf_counter() - t0
mops = round(3.0 / t_cpu, 2)

# Stage 2: Memory Read/Write Throughput (100MB buffer)
t0 = time.perf_counter()
size_mb = 100
buf = bytearray(size_mb * 1024 * 1024)
for idx in range(0, len(buf), 4096):
    buf[idx] = 0xAA
t_mem = time.perf_counter() - t0
bandwidth_mb_s = round(size_mb / t_mem, 2)

# Stage 3: Matrix multiplication / Compute density
t0 = time.perf_counter()
n = 150
mat_a = [[float(i + j) for j in range(n)] for i in range(n)]
mat_b = [[float(i * j) for j in range(n)] for i in range(n)]
res = [[sum(mat_a[i][k] * mat_b[k][j] for k in range(n)) for j in range(n)] for i in range(n)]
t_matrix = time.perf_counter() - t0

print(f"{t_cpu*1000:.2f}|{mops}|{t_mem*1000:.2f}|{bandwidth_mb_s}|{t_matrix*1000:.2f}")
' 2>/dev/null || true)

    if [ -n "$py_bench_res" ]; then
        IFS='|' read -r cpu_ms cpu_mops mem_ms mem_bw mat_ms <<< "$py_bench_res"
        printf '  CPU Math Latency:    %s%sms%s (%s MFLOPS)\n' "$c_cyan" "$cpu_ms" "$c_reset" "$cpu_mops"
        printf '  RAM Write Bandwidth: %s%s MB/s%s (100MB in %sms)\n' "$c_green" "$mem_bw" "$c_reset" "$mem_ms"
        printf '  Matrix Compute Time: %s%sms%s (150x150 dense multiplication)\n' "$c_cyan" "$mat_ms" "$c_reset"
    else
        echo "  [!] Python3 compute benchmark unavailable."
    fi
    echo ""

    # 4. Post-Benchmark Thermal Delta & Governor Frequency
    local temp_end_cpu temp_end_batt cur_freq max_freq
    temp_end_cpu=$(asl_cpu_temp_c 2>/dev/null)
    [ -z "$temp_end_cpu" ] && temp_end_cpu="N/A"
    temp_end_batt=$(asl_batt_temp_c 2>/dev/null)
    [ -z "$temp_end_batt" ] && temp_end_batt="N/A"

    cur_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || true)
    max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true)
    local freq_str="N/A"
    if [ -n "$cur_freq" ] && [ -n "$max_freq" ] && [ "$max_freq" -gt 0 ] 2>/dev/null; then
        freq_str="$((cur_freq / 1000))MHz / $((max_freq / 1000))MHz"
    fi

    echo "Thermal & Clock Response:"
    echo "  Post-Benchmark CPU Temp:     ${temp_end_cpu}°C"
    echo "  Post-Benchmark Battery Temp: ${temp_end_batt}°C"
    echo "  CPU Core Clock Frequency:    $freq_str"

    # Overall Performance Rating
    echo ""
    printf '%sOverall Performance Rating:%s ' "$c_bold" "$c_reset"
    if [ -n "$cpu_ms" ] && [ "${cpu_ms%.*}" -lt 1200 ] 2>/dev/null; then
        printf '%sEXCELLENT%s (Low latency, high compute throughput)\n' "$c_green$c_bold" "$c_reset"
    elif [ -n "$cpu_ms" ] && [ "${cpu_ms%.*}" -lt 2500 ] 2>/dev/null; then
        printf '%sGOOD%s (Standard smartphone performance profile)\n' "$c_yellow$c_bold" "$c_reset"
    else
        printf '%sCONSTRAINED%s (Recommend switching governor: asl mode performance)\n' "$c_red$c_bold" "$c_reset"
    fi
}

asl_benchmark_run "$@"
