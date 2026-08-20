#!/bin/bash
# ASL: 24/7 Background Service Manager & Boot Autostart Integration
# Ensures ASL chroot mounts, host SSH server, Serveo persistent tunnel, Ngrok backup,
# auto-connect daemon, and AI proxy services start automatically on boot and stay alive 24/7.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
fi

BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/00-asl-autostart.sh"
BASHRC="$HOME/.bashrc"
SERVICE_LOG="${PREFIX:-/data/data/com.termux/files/usr}/tmp/asl-service.log"
SERVICE_PIDFILE="${PREFIX:-/data/data/com.termux/files/usr}/tmp/asl-service.pid"

asl_service_start() {
    echo "[*] Initializing ASL 24/7 Background Services..."

    # 0. Disable Android Phantom Process Killer, set OOM score adjustment, CPU affinity & tune TCP sysctl if root available
    if su -c "id -u" >/dev/null 2>&1; then
        su -c "device_config put activity_manager max_phantom_processes 2147483647 2>/dev/null; settings put global settings_enable_monitor_phantom_procs false 2>/dev/null; setprop persist.sys.fflag.override.settings_enable_monitor_phantom_procs false 2>/dev/null; dumpsys deviceidle whitelist +com.termux 2>/dev/null; am set-standby-bucket com.termux active 2>/dev/null; cmd appops set com.termux RUN_IN_BACKGROUND allow 2>/dev/null; cmd appops set com.termux RUN_ANY_IN_BACKGROUND allow 2>/dev/null; cmd appops set com.termux SYSTEM_EXEMPT_FROM_POWER_RESTRICTIONS allow 2>/dev/null" 2>/dev/null || true
        for pid in $(pgrep -f "sshd|ngrok|serveo|autoconnect|omniroute|asl-service|asl-watchdog-loop" 2>/dev/null); do
            su -c "echo -1000 > /proc/$pid/oom_score_adj" 2>/dev/null || true
            if command -v taskset >/dev/null 2>&1; then
                taskset -pc 0-3 "$pid" >/dev/null 2>&1 || true
            fi
        done
        su -c "sysctl -w net.core.rmem_max=8388608 net.core.wmem_max=8388608 net.core.netdev_max_backlog=10000 net.core.somaxconn=2048 net.ipv4.tcp_fastopen=3 2>/dev/null" 2>/dev/null || true
        echo "[✓] Android 14 Phantom Process Killer & Doze disabled, AppOps & Standby Bucket active, CPU affinity set, OOM protection applied & Kernel TCP tuned."
    fi

    # 1. Engage CPU wake lock to prevent Android deep sleep
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null || true
        echo "[✓] CPU Wake-Lock engaged."
    fi

    # 2. Ensure chroot is mounted
    if ! is_mounted; then
        echo "[*] Mounting Debian chroot virtual filesystems..."
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" || echo "[!] Warning: Chroot mount returned notice."
        fi
    else
        echo "[✓] Debian chroot already mounted."
    fi

    # 3. Start SSH, Serveo, Ngrok, and Auto-Connect daemon
    echo "[*] Starting SSH, Serveo, Ngrok, and Auto-Connect remote bridges..."
    if [ -f "$SCRIPT_DIR/desktop/remote.sh" ]; then
        bash "$SCRIPT_DIR/desktop/remote.sh" start-all || true
    fi

    # 4. Check & restore Omniroute / local AI proxy on port 20128 if installed
    local omniroute_bin="$HOME/.omniroute/bin/omniroute"
    if [ -x "$omniroute_bin" ] || command -v omniroute >/dev/null 2>&1; then
        if ! pgrep -f "omniroute" >/dev/null 2>&1 && ! netstat -tulpn 2>/dev/null | grep -q ":20128"; then
            echo "[*] Starting Omniroute local AI proxy on port 20128..."
            nohup omniroute start >/dev/null 2>&1 &
        fi
    fi

    # Record service start timestamp for uptime tracking (only if not already set)
    local prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    mkdir -p "$prefix/tmp" 2>/dev/null || true
    if [ ! -f "$prefix/tmp/asl-service.start_time" ]; then
        date +%s > "$prefix/tmp/asl-service.start_time" 2>/dev/null || true
    fi

    echo "[✓] All ASL 24/7 background services are ACTIVE."
}

asl_service_stop() {
    echo "[*] Stopping ASL 24/7 Background Services..."
    if [ -f "$SCRIPT_DIR/desktop/remote.sh" ]; then
        bash "$SCRIPT_DIR/desktop/remote.sh" autoconnect stop >/dev/null 2>&1 || true
        bash "$SCRIPT_DIR/desktop/remote.sh" oracle stop >/dev/null 2>&1 || true
        bash "$SCRIPT_DIR/desktop/remote.sh" serveo stop >/dev/null 2>&1 || true
        bash "$SCRIPT_DIR/desktop/remote.sh" ngrok stop >/dev/null 2>&1 || true
        bash "$SCRIPT_DIR/desktop/remote.sh" lan stop >/dev/null 2>&1 || true
    fi
    pkill -f "asl-watchdog-loop" 2>/dev/null || true
    pkill -f "omniroute" 2>/dev/null || true
    if command -v termux-wake-unlock >/dev/null 2>&1; then
        termux-wake-unlock 2>/dev/null || true
    fi
    rm -f "${PREFIX:-/data/data/com.termux/files/usr}/tmp/asl-service.start_time" 2>/dev/null || true
    rm -f "${PREFIX:-/data/data/com.termux/files/usr}/tmp/asl-watchdog.pid" 2>/dev/null || true
    echo "[✓] ASL 24/7 background services stopped."
}

asl_service_enable() {
    echo "[*] Enabling ASL 24/7 Boot Autostart..."
    mkdir -p "$BOOT_DIR"
    chmod 700 "$BOOT_DIR"

    cat << 'BOOT_EOF' > "$BOOT_SCRIPT"
#!/bin/bash
# ASL Termux:Boot autostart script
# Runs automatically on Android device boot via Termux:Boot app

termux-wake-lock 2>/dev/null || true

# Wait for active network connection on boot (up to 30s)
echo "[*] Waiting for network connectivity..." >> /data/data/com.termux/files/usr/tmp/asl-boot.log
retry=0
while [ $retry -lt 15 ]; do
    if ping -c 1 -w 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -w 2 8.8.8.8 >/dev/null 2>&1; then
        echo "[✓] Network online." >> /data/data/com.termux/files/usr/tmp/asl-boot.log
        break
    fi
    sleep 2
    retry=$((retry + 1))
done

# Locate ASL directory
ASL_PATH="/data/data/com.termux/files/home/ASL"
if [ -f "$ASL_PATH/bin/asl" ]; then
    bash "$ASL_PATH/bin/asl" service start >> /data/data/com.termux/files/usr/tmp/asl-boot.log 2>&1
fi
BOOT_EOF
    chmod 755 "$BOOT_SCRIPT"
    echo "[✓] Boot autostart script created at $BOOT_SCRIPT"

    # Add background auto-check to .bashrc if not already present
    if [ -f "$BASHRC" ]; then
        if ! grep -q "ASL 24/7 Auto-Start Hook" "$BASHRC"; then
            cat << 'BASHRC_EOF' >> "$BASHRC"

# ASL 24/7 Auto-Start Hook
if [ -f "$HOME/ASL/bin/asl" ] && ! pgrep -f "asl-watchdog-loop\|sshd\|autoconnect" >/dev/null 2>&1; then
    (nohup bash "$HOME/ASL/bin/asl" service start >/dev/null 2>&1 &) disown 2>/dev/null || true
fi
BASHRC_EOF
            echo "[✓] Added shell auto-start hook to $BASHRC"
        fi
    fi

    echo "[✓] ASL autostart successfully enabled! (Will run on boot & shell startup)."
}

asl_service_disable() {
    echo "[*] Disabling ASL Boot Autostart..."
    rm -f "$BOOT_SCRIPT"
    if [ -f "$BASHRC" ]; then
        sed -i '/# ASL 24\/7 Auto-Start Hook/,+3d' "$BASHRC" 2>/dev/null || true
    fi
    echo "[✓] Boot autostart disabled."
}

asl_service_status() {
    echo "=== ASL 24/7 Service & Autostart Status ==="
    if [ -f "$BOOT_SCRIPT" ]; then
        echo " Boot Autostart: ENABLED ($BOOT_SCRIPT)"
    else
        echo " Boot Autostart: DISABLED (Run 'asl service enable' to activate)"
    fi

    local prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local start_file="$prefix/tmp/asl-service.start_time"
    if [ -f "$start_file" ]; then
        local start_t now_t diff_t s_d s_h s_m
        start_t=$(cat "$start_file" 2>/dev/null | tr -d '[:space:]')
        now_t=$(date +%s 2>/dev/null || echo 0)
        if [ -n "$start_t" ] && [[ "$start_t" =~ ^[0-9]+$ ]] && [ "$now_t" -ge "$start_t" ]; then
            diff_t=$((now_t - start_t))
            s_d=$((diff_t / 86400)); diff_t=$((diff_t % 86400))
            s_h=$((diff_t / 3600)); s_m=$(((diff_t % 3600) / 60))
            if [ "$s_d" -gt 0 ]; then
                echo " Service Uptime: ${s_d}d ${s_h}h ${s_m}m"
            elif [ "$s_h" -gt 0 ]; then
                echo " Service Uptime: ${s_h}h ${s_m}m"
            elif [ "$s_m" -gt 0 ]; then
                echo " Service Uptime: ${s_m}m"
            else
                echo " Service Uptime: ${diff_t}s"
            fi
        fi
    fi

    fmt_mem() {
        local pid="$1" rss
        rss=$(ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ')
        if [ -n "$rss" ] && [[ "$rss" =~ ^[0-9]+$ ]]; then
            if [ "$rss" -ge 1024 ]; then echo "$((rss / 1024))MB"
            elif [ "$rss" -gt 0 ]; then echo "<1MB"
            else echo "0MB"; fi
        else echo "<1MB"; fi
    }

    local ac_pid ac_mem
    ac_pid=$(pgrep -f "autoconnect-daemon\|asl-autoconnect" 2>/dev/null | head -1 || true)
    if [ -n "$ac_pid" ]; then
        ac_mem=$(fmt_mem "$ac_pid")
        echo " Remote Daemon:  ACTIVE (Auto-Connect PID: $ac_pid, RAM: $ac_mem)"
    else
        echo " Remote Daemon:  INACTIVE"
    fi

    local ssh_pid ssh_mem
    ssh_pid=$(pgrep -f "sshd" 2>/dev/null | head -1 || true)
    if [ -n "$ssh_pid" ]; then
        ssh_mem=$(fmt_mem "$ssh_pid")
        echo " LAN SSH Server: ACTIVE (Port 8022, PID: $ssh_pid, RAM: $ssh_mem)"
    else
        echo " LAN SSH Server: INACTIVE"
    fi

    local oracle_pid oracle_mem
    oracle_pid=$(pgrep -f "ssh.*130.210.19.7" 2>/dev/null | head -1 || true)
    if [ -n "$oracle_pid" ]; then
        oracle_mem=$(fmt_mem "$oracle_pid")
        echo " Oracle Tunnel: ACTIVE (130.210.19.7:2222, PID: $oracle_pid, RAM: $oracle_mem)"
    elif [ -f "$HOME/.ssh/oracle_vps.key" ]; then
        echo " Oracle Tunnel: STANDBY (Run 'asl remote oracle start')"
    fi

    local serveo_pid serveo_mem
    serveo_pid=$(pgrep -f "serveo.net" 2>/dev/null | head -1 || true)
    if [ -n "$serveo_pid" ]; then
        serveo_mem=$(fmt_mem "$serveo_pid")
        echo " Serveo Tunnel:  ACTIVE (PID: $serveo_pid, RAM: $serveo_mem)"
    else
        echo " Serveo Tunnel:  INACTIVE"
    fi

    local ngrok_pid ngrok_mem
    ngrok_pid=$(pgrep -f "ngrok.*tcp" 2>/dev/null | head -1 || true)
    if [ -n "$ngrok_pid" ]; then
        ngrok_mem=$(fmt_mem "$ngrok_pid")
        echo " Ngrok Tunnel:   ACTIVE (PID: $ngrok_pid, RAM: $ngrok_mem)"
    else
        echo " Ngrok Tunnel:   INACTIVE"
    fi

    local omni_pid omni_mem
    omni_pid=$(pgrep -f "omniroute" 2>/dev/null | head -1 || true)
    if [ -n "$omni_pid" ]; then
        omni_mem=$(fmt_mem "$omni_pid")
        echo " Omniroute Proxy: ACTIVE (Port 20128, PID: $omni_pid, RAM: $omni_mem)"
    fi

    local loop_pid loop_mem
    loop_pid=$(pgrep -f "asl-watchdog-loop" 2>/dev/null | head -1 || true)
    if [ -n "$loop_pid" ]; then
        loop_mem=$(fmt_mem "$loop_pid")
        echo " Watchdog Loop:  ACTIVE (PID: $loop_pid, RAM: $loop_mem, Interval: 60s)"
    else
        echo " Watchdog Loop:  STANDBY (Run 'asl service loop' to start 60s background daemon)"
    fi

    if is_mounted; then
        echo " Chroot Mounts:  ACTIVE"
    else
        echo " Chroot Mounts:  INACTIVE"
    fi

    if dumpsys power 2>/dev/null | grep -q "termux:service-wakelock" || su -c "dumpsys power" 2>/dev/null | grep -q "termux:service-wakelock" || pgrep -f "termux-wake-lock" >/dev/null 2>&1; then
        echo " Wake-Lock:      ENGAGED (Android Sleep Prevented)"
    else
        echo " Wake-Lock:      DISABLED"
    fi

    local boot_log="${PREFIX:-/data/data/com.termux/files/usr}/tmp/asl-boot.log"
    if [ -f "$boot_log" ] && [ -s "$boot_log" ]; then
        echo " Boot Log:       $boot_log ($(tail -n 1 "$boot_log" 2>/dev/null))"
    fi
}

asl_service_check() {
    echo "[*] Running ASL Service Health Watchdog..."
    local healed=0
    local prefix="${PREFIX:-/data/data/com.termux/files/usr}"

    # 1. SSH Server Check
    if ! pgrep -f "sshd" >/dev/null 2>&1; then
        echo "[!] SSH server inactive — restarting LAN SSH..."
        if [ -f "$SCRIPT_DIR/desktop/remote.sh" ]; then
            bash "$SCRIPT_DIR/desktop/remote.sh" lan start >/dev/null 2>&1 || true
            healed=$((healed + 1))
        fi
    fi

    # 2. Auto-Connect Daemon Check (if enabled by user state)
    if [ -f "$prefix/tmp/asl-autoconnect.state" ] && ! pgrep -f "autoconnect" >/dev/null 2>&1; then
        echo "[!] Auto-Connect daemon state ACTIVE but process down — restoring remote Watchdog..."
        if [ -f "$SCRIPT_DIR/desktop/remote.sh" ]; then
            bash "$SCRIPT_DIR/desktop/remote.sh" autoconnect start >/dev/null 2>&1 || true
            healed=$((healed + 1))
        fi
    fi

    # 3. Oracle VPS Tunnel Check (if enabled by user state)
    if [ -f "$prefix/tmp/asl-oracle.state" ] && ! pgrep -f "ssh.*130.210.19.7" >/dev/null 2>&1; then
        echo "[!] Oracle VPS tunnel state ACTIVE but process down — restoring tunnel..."
        if [ -f "$SCRIPT_DIR/desktop/remote.sh" ]; then
            bash "$SCRIPT_DIR/desktop/remote.sh" oracle start >/dev/null 2>&1 || true
            healed=$((healed + 1))
        fi
    fi

    # 4. Serveo Tunnel Check (if enabled by user state)
    if [ -f "$prefix/tmp/asl-serveo.state" ] && ! pgrep -f "serveo.net" >/dev/null 2>&1; then
        echo "[!] Serveo tunnel state ACTIVE but process down — restoring tunnel..."
        if [ -f "$SCRIPT_DIR/desktop/remote.sh" ]; then
            bash "$SCRIPT_DIR/desktop/remote.sh" serveo start >/dev/null 2>&1 || true
            healed=$((healed + 1))
        fi
    fi

    # 4. Ngrok Tunnel Check (if enabled by user state)
    if [ -f "$prefix/tmp/asl-ngrok.state" ]; then
        if ! pgrep -f "ngrok.*tcp" >/dev/null 2>&1 || ! curl -s http://127.0.0.1:4040/api/tunnels >/dev/null 2>&1; then
            echo "[!] Ngrok tunnel unresponsive — cycling active authtoken pool..."
            if [ -f "$SCRIPT_DIR/desktop/remote.sh" ]; then
                bash "$SCRIPT_DIR/desktop/remote.sh" ngrok start >/dev/null 2>&1 || true
                healed=$((healed + 1))
            fi
        fi
    fi

    # 5. Chroot Mount Check
    if ! is_mounted; then
        echo "[!] Debian chroot unmounted — re-mounting Linux virtual filesystems..."
        if [ -f "$SCRIPT_DIR/core/mount-chroot.sh" ]; then
            bash "$SCRIPT_DIR/core/mount-chroot.sh" >/dev/null 2>&1 || true
            healed=$((healed + 1))
        fi
    fi

    # 6. CPU Wake-Lock Protection (prevents Android sleep dropouts)
    if ! dumpsys power 2>/dev/null | grep -q "termux:service-wakelock" && ! su -c "dumpsys power" 2>/dev/null | grep -q "termux:service-wakelock"; then
        if command -v termux-wake-lock >/dev/null 2>&1; then
            termux-wake-lock 2>/dev/null || true
            echo "[*] Re-engaged CPU Wake-Lock to prevent Android sleep..."
            healed=$((healed + 1))
        fi
    fi

    # 7. Re-apply Android OOM score adjustment (-1000) & CPU affinity (cores 0-3) for background daemons
    if su -c "id -u" >/dev/null 2>&1; then
        for pid in $(pgrep -f "sshd|ngrok|serveo|autoconnect|omniroute|asl-service|asl-watchdog-loop" 2>/dev/null); do
            su -c "echo -1000 > /proc/$pid/oom_score_adj" 2>/dev/null || true
            if command -v taskset >/dev/null 2>&1; then
                taskset -pc 0-3 "$pid" >/dev/null 2>&1 || true
            fi
        done
    fi

    # 8. Log rotation check (keep logs under 500KB)
    local boot_log="$prefix/tmp/asl-boot.log"
    local service_log="$prefix/tmp/asl-service.log"
    local wdog_log="$prefix/tmp/asl-watchdog.log"
    for lfile in "$boot_log" "$service_log" "$wdog_log"; do
        if [ -f "$lfile" ]; then
            local lsize
            lsize=$(wc -c < "$lfile" 2>/dev/null || echo 0)
            if [ "$lsize" -gt 524288 ]; then
                echo "[*] Truncating overgrown log $lfile (${lsize} bytes)..."
                tail -n 500 "$lfile" > "$lfile.tmp" && mv -f "$lfile.tmp" "$lfile" 2>/dev/null || true
            fi
        fi
    done

    if [ "$healed" -eq 0 ]; then
        echo "[✓] All 24/7 background services are healthy and running."
    else
        echo "[✓] Service health watchdog auto-healed $healed background daemon(s)."
    fi
}

asl_service_loop() {
    if pgrep -f "asl-watchdog-loop" >/dev/null 2>&1; then
        echo "[!] ASL autonomous watchdog loop is already RUNNING (PID: $(pgrep -f "asl-watchdog-loop" | head -1))."
        return 0
    fi
    echo "[*] Starting ASL autonomous background watchdog daemon (60s interval)..."
    local prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    mkdir -p "$prefix/tmp" 2>/dev/null || true
    local mgr_path="$SCRIPT_DIR/core/service-manager.sh"
    [ -f "$mgr_path" ] || mgr_path="$HOME/ASL/core/service-manager.sh"

    nohup bash -c '
        exec -a "asl-watchdog-loop" bash -c "
            while true; do
                echo \"[$(date +\"%Y-%m-%d %H:%M:%S\")] Watchdog health check...\"
                bash \"'"$mgr_path"'\" check 2>&1
                sleep 60
            done
        "
    ' >> "$prefix/tmp/asl-watchdog.log" 2>&1 &
    local lpid=$!
    echo "$lpid" > "$prefix/tmp/asl-watchdog.pid" 2>/dev/null || true
    echo "[✓] Autonomous watchdog daemon ACTIVE (PID: $lpid)."
}

case "${1:-status}" in
    start|run)
        asl_service_start
        ;;
    stop)
        asl_service_stop
        pkill -f "asl-watchdog-loop" 2>/dev/null || true
        ;;
    restart)
        asl_service_stop
        pkill -f "asl-watchdog-loop" 2>/dev/null || true
        sleep 1
        asl_service_start
        ;;
    check|health)
        asl_service_check
        ;;
    loop|daemon|watchdog)
        asl_service_loop
        ;;
    enable)
        asl_service_enable
        asl_service_start
        asl_service_loop
        ;;
    disable)
        pkill -f "asl-watchdog-loop" 2>/dev/null || true
        asl_service_disable
        ;;
    status|"")
        asl_service_status
        ;;
    *)
        echo "Usage: asl service [start|stop|restart|check|loop|enable|disable|status]"
        ;;
esac
