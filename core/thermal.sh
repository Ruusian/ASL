#!/bin/bash
# ASL: Thermal & Battery Monitor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

asl_thermal_report() {
    local c_reset=$'\033[0m' c_bold=$'\033[1m' c_cyan=$'\033[36m'
    local c_green=$'\033[32m' c_yellow=$'\033[33m' c_red=$'\033[31m'
    local tz_path type raw_temp temp_c

    format_temp() {
        local t="$1"
        if [ "$t" -lt 45 ]; then
            printf '%s%d°C%s' "$c_green" "$t" "$c_reset"
        elif [ "$t" -lt 60 ]; then
            printf '%s%d°C%s' "$c_yellow" "$t" "$c_reset"
        else
            printf '%s%d°C (HIGH TEMP)%s' "$c_red" "$t" "$c_reset"
        fi
    }

    printf '%s=== ASL Thermal & Battery Status ===%s\n' "$c_cyan$c_bold" "$c_reset"

    # Battery Temperature via dumpsys or sysfs
    local batt_temp=""
    batt_temp=$(asl_exec "dumpsys battery | awk '/temperature:/ {print int(\$2/10)}'" 2>/dev/null || true)
    if [ -z "$batt_temp" ] || [[ ! "$batt_temp" =~ ^-?[0-9]+$ ]] || [ "$batt_temp" -le 0 ]; then
        for p in /sys/class/power_supply/battery/temp /sys/class/power_supply/bms/temp; do
            raw_temp=$(cat "$p" 2>/dev/null || asl_exec "cat '$p' 2>/dev/null" 2>/dev/null || true)
            if [ -n "$raw_temp" ] && [[ "$raw_temp" =~ ^[0-9]+$ ]] && [ "$raw_temp" -gt 0 ]; then
                if [ "$raw_temp" -gt 1000 ]; then
                    batt_temp=$((raw_temp / 1000))
                elif [ "$raw_temp" -gt 100 ]; then
                    batt_temp=$(((raw_temp + 5) / 10))
                else
                    batt_temp="$raw_temp"
                fi
                break
            fi
        done
    fi

    if [ -n "$batt_temp" ] && [[ "$batt_temp" =~ ^[0-9]+$ ]] && [ "$batt_temp" -gt 0 ] && [ "$batt_temp" -lt 100 ]; then
        printf ' Battery:     '
        format_temp "$batt_temp"
        echo
    else
        printf ' Battery:     %sUnknown%s\n' "$c_yellow" "$c_reset"
    fi

    # Thermal headroom (Android 15+ API)
    local thermal_headroom=""
    thermal_headroom=$(asl_exec "dumpsys hardware_properties | awk -F= '/ThermalHeadroom/ {print \$2}'" 2>/dev/null || true)
    if [ -n "$thermal_headroom" ] && [[ "$thermal_headroom" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        printf ' Thermal Headroom: %s%s%s' "$c_cyan" "$thermal_headroom" "$c_reset"
        if [ "$(echo "$thermal_headroom < 0.5" | bc 2>/dev/null || echo "1")" = "1" ]; then
            printf ' %s[COOL]%s\n' "$c_green" "$c_reset"
        elif [ "$(echo "$thermal_headroom < 1.0" | bc 2>/dev/null || echo "0")" = "1" ]; then
            printf ' %s[WARM]%s\n' "$c_yellow" "$c_reset"
        else
            printf ' %s[HOT - THROTTLE RISK]%s\n' "$c_red" "$c_reset"
        fi
    fi

    echo " Thermal Zones (SoC, CPU, GPU):"
    local count=0
    for tz_path in /sys/class/thermal/thermal_zone*; do
        [ -d "$tz_path" ] || continue
        type=$(cat "$tz_path/type" 2>/dev/null || asl_exec "cat '$tz_path/type' 2>/dev/null" 2>/dev/null || true)
        raw_temp=$(cat "$tz_path/temp" 2>/dev/null || asl_exec "cat '$tz_path/temp' 2>/dev/null" 2>/dev/null || true)
        [ -n "$type" ] && [[ "$raw_temp" =~ ^[0-9]+$ ]] && [ "$raw_temp" -gt 0 ] || continue

        if [ "$raw_temp" -gt 1000 ]; then
            temp_c=$((raw_temp / 1000))
        else
            temp_c="$raw_temp"
        fi

        # Filter valid temperature ranges (1°C to 125°C) and relevant sensor names
        if [ "$temp_c" -ge 1 ] && [ "$temp_c" -le 125 ]; then
            case "$type" in
                *cpu*|*gpu*|soc|*soc*|*tsens*|*qcom*|*ap-thermal*|*mtk*|*exynos*|*quiet-therm*)
                    printf '  %-22s ' "$type:"
                    format_temp "$temp_c"
                    echo
                    count=$((count + 1))
                    ;;
            esac
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo "  No active CPU/GPU thermal sensors available."
    fi

    # Thermal throttling status
    echo ""
    echo "Throttling Status:"
    local throttle_status
    throttle_status=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || true)
    local throttle_max
    throttle_max=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true)
    
    if [ -n "$throttle_status" ] && [ -n "$throttle_max" ] && [ "$throttle_max" -gt 0 ] 2>/dev/null; then
        local freq_mhz=$((throttle_status / 1000))
        local max_mhz=$((throttle_max / 1000))
        [ "$max_mhz" -eq 0 ] && max_mhz=1
        local usage_pct=$((freq_mhz * 100 / max_mhz))
        
        if [ "$usage_pct" -gt 90 ]; then
            printf '  CPU Freq: %s%dMHz / %dMHz (%d%%)%s\n' "$c_green" "$freq_mhz" "$max_mhz" "$usage_pct" "$c_reset"
        elif [ "$usage_pct" -gt 70 ]; then
            printf '  CPU Freq: %s%dMHz / %dMHz (%d%%)%s\n' "$c_yellow" "$freq_mhz" "$max_mhz" "$usage_pct" "$c_reset"
        else
            printf '  CPU Freq: %s%dMHz / %dMHz (%d%%) [THROTTLED]%s\n' "$c_red" "$freq_mhz" "$max_mhz" "$usage_pct" "$c_reset"
        fi
    else
        echo "  CPU frequency info not available"
    fi
}

asl_thermal_watch() {
    echo "[*] Starting thermal watchdog monitor (interval: 5s)... Press Ctrl+C to stop."
    trap 'echo -e "\n[*] Thermal watchdog stopped."; trap - INT TERM; return 0 2>/dev/null || exit 0' INT TERM
    while true; do
        clear
        asl_thermal_report
        sleep 5
    done
}

case "${1:-status}" in
    watch|monitor)
        asl_thermal_watch
        ;;
    status|report|*)
        asl_thermal_report
        ;;
esac

