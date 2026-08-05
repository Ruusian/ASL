#!/bin/bash
# AndroidLinux-SuperKit: Thermal & Battery Monitor

superkit_thermal_report() {
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

    printf '%s=== AndroidLinux-SuperKit Thermal & Battery Status ===%s\n' "$c_cyan$c_bold" "$c_reset"

    # Battery Temperature via dumpsys or sysfs
    local batt_temp=""
    batt_temp=$(su -c "dumpsys battery | awk '/temperature:/ {print int(\$2/10)}'" 2>/dev/null || true)
    if [ -z "$batt_temp" ] || [ "$batt_temp" -le 0 ]; then
        for p in /sys/class/power_supply/battery/temp /sys/class/power_supply/bms/temp; do
            if [ -r "$p" ]; then
                raw_temp=$(cat "$p" 2>/dev/null || true)
                if [ -n "$raw_temp" ] && [ "$raw_temp" -gt 0 ]; then
                    [ "$raw_temp" -gt 1000 ] && raw_temp=$((raw_temp / 100))
                    batt_temp="$raw_temp"
                    break
                fi
            fi
        done
    fi

    if [ -n "$batt_temp" ] && [ "$batt_temp" -gt 0 ] && [ "$batt_temp" -lt 100 ]; then
        printf ' Battery:     '
        format_temp "$batt_temp"
        echo
    else
        printf ' Battery:     %sUnknown%s\n' "$c_yellow" "$c_reset"
    fi

    echo " Thermal Zones (SoC, CPU, GPU):"
    local count=0
    for tz_path in /sys/class/thermal/thermal_zone*; do
        [ -d "$tz_path" ] || continue
        type=$(cat "$tz_path/type" 2>/dev/null || true)
        raw_temp=$(cat "$tz_path/temp" 2>/dev/null || true)
        [ -n "$type" ] && [[ "$raw_temp" =~ ^-?[0-9]+$ ]] || continue

        if [ "$raw_temp" -gt 1000 ]; then
            temp_c=$((raw_temp / 1000))
        else
            temp_c="$raw_temp"
        fi

        # Filter valid temperature ranges (1°C to 125°C) and relevant sensor names
        if [ "$temp_c" -ge 1 ] && [ "$temp_c" -le 125 ]; then
            case "$type" in
                *cpu-[0-9]*-usr|*gpuss-[0-9]*-usr|soc|cpuss-[0-9]*-usr)
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
}

if [ "${BASH_SOURCE[0]}" -eq "${0}" 2>/dev/null ] || [ "$0" = "$BASH_SOURCE" ]; then
    superkit_thermal_report
fi
