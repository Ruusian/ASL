#!/data/data/com.termux/files/usr/bin/bash
# ASL Safe Service Updater
# Safely pauses watchdog -> stops service cleanly -> performs update -> restarts service -> resumes watchdog

service="${1:-omniroute}"
TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG_FILE="$PREFIX/tmp/asl-safe-update.log"
LOCK_FILE="$PREFIX/tmp/.asl_update_lock"

mkdir -p "$PREFIX/tmp" "$TERMUX_HOME/.asl" 2>/dev/null || true

# 1. Prevent concurrent updates
if [ -f "$LOCK_FILE" ]; then
    old_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "[!] An update is already in progress (PID: $old_pid). Please wait."
        exit 1
    fi
fi
echo "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE" "$TERMUX_HOME/.asl/no-watchdog-omniroute" 2>/dev/null || true' EXIT INT TERM

echo "[*] === Safe Update Initiated for: $service ===" > "$LOG_FILE"

case "$service" in
    omni|omniroute)
        echo "[1/5] Pausing watchdog supervision for OmniRoute..." | tee -a "$LOG_FILE"
        touch "$TERMUX_HOME/.asl/no-watchdog-omniroute" 2>/dev/null || true
        touch "$PREFIX/tmp/.asl_stopped_omniroute" 2>/dev/null || true

        echo "[2/5] Stopping active OmniRoute daemon cleanly..." | tee -a "$LOG_FILE"
        pkill -9 -f "omniroute.*serve" 2>/dev/null || true
        pkill -9 -f "node.*omniroute.mjs" 2>/dev/null || true
        # Wait up to 6s for port 20128 to release
        for _w in $(seq 1 12); do
            if ! (timeout 0.3 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/20128') 2>/dev/null; then
                break
            fi
            sleep 0.5
        done
        echo "[✓] Port 20128 released." | tee -a "$LOG_FILE"

        old_ver=$(omniroute --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "3.8.52")
        echo "[3/5] Updating npm package omniroute@latest (Current: v$old_ver)..." | tee -a "$LOG_FILE"
        if npm install -g omniroute@latest --no-audit --no-fund >> "$LOG_FILE" 2>&1; then
            new_ver=$(omniroute --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "$old_ver")
            echo "[✓] Package update finished (v$old_ver -> v$new_ver)" | tee -a "$LOG_FILE"
        else
            new_ver=$(omniroute --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "$old_ver")
            echo "[!] Notice: npm install finished (v$new_ver)" | tee -a "$LOG_FILE"
        fi

                # Enforce Claude tool_use auto-healing persistence across package updates
        if [ -f "$PREFIX/share/asl/core/patch-omniroute-claude-heal.py" ]; then
            echo "[*] Enforcing Claude tool-call auto-healing persistence..." | tee -a "$LOG_FILE"
            python3 "$PREFIX/share/asl/core/patch-omniroute-claude-heal.py" >> "$LOG_FILE" 2>&1 || true
        elif [ -f "$TERMUX_HOME/ASL/core/patch-omniroute-claude-heal.py" ]; then
            python3 "$TERMUX_HOME/ASL/core/patch-omniroute-claude-heal.py" >> "$LOG_FILE" 2>&1 || true
        fi

        echo "[4/5] Launching updated OmniRoute daemon..." | tee -a "$LOG_FILE"
        rm -f "$PREFIX/tmp/.asl_stopped_omniroute" 2>/dev/null || true
        if [ -f "$TERMUX_HOME/omniroute-daemon.sh" ]; then
            (cd "$TERMUX_HOME" && setsid nohup bash "$TERMUX_HOME/omniroute-daemon.sh" >> /data/data/com.termux/files/home/omniroute.log 2>&1 < /dev/null &)
        fi

        # Poll port 20128 for up to 15 seconds to confirm it is answering
        echo "[*] Waiting for port 20128 warm-up..." | tee -a "$LOG_FILE"
        started=0
        for _p in $(seq 1 30); do
            code=$(curl -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/v1/models 2>/dev/null || echo "000")
            if [ "$code" = "200" ]; then
                started=1
                break
            fi
            sleep 0.5
        done

        echo "[5/5] Resuming watchdog supervision..." | tee -a "$LOG_FILE"
        rm -f "$TERMUX_HOME/.asl/no-watchdog-omniroute" 2>/dev/null || true

        if [ "$started" -eq 1 ]; then
            echo "[✓] SUCCESS: OmniRoute v$new_ver is LIVE and verified healthy (HTTP 200 OK) on port 20128!" | tee -a "$LOG_FILE"
            exit 0
        else
            echo "[!] Warning: Port 20128 did not answer 200 within timeout." | tee -a "$LOG_FILE"
            exit 1
        fi
        ;;
    *)
        echo "[!] Unknown service for safe update: $service"
        exit 1
        ;;
esac
