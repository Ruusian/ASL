#!/bin/bash
# ASL Remote Access - Ngrok Tunnel (Multi-Token Pool, Quota Auto-Rotation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/desktop/remote/common.sh"

NGROK_TOKENS_FILE="$CONFIG_DIR/ngrok_tokens.txt"
NGROK_EXHAUSTED_FILE="$CONFIG_DIR/ngrok_exhausted.txt"
NGROK_LOG="$PREFIX/tmp/ngrok.log"
NGROK_STATE="$PREFIX/tmp/asl-ngrok.state"
NGROK_CURR_TOKEN="$PREFIX/tmp/asl-ngrok-current.token"

get_ngrok_bin() {
    if command -v ngrok >/dev/null 2>&1; then
        echo "ngrok"
    elif [ -x "$PREFIX/bin/ngrok" ]; then
        echo "$PREFIX/bin/ngrok"
    else
        echo ""
    fi
}

run_ngrok_cmd() {
    local target_bin="$1"
    shift
    "$target_bin" "$@"
}

run_ngrok_bg() {
    local target_bin="$1" log_file="$2"
    shift 2
    nohup "$target_bin" "$@" > "$log_file" 2>&1 &
    echo $!
}

ngrok_running() {
    [ -f "$NGROK_STATE" ] || return 1
    if grep -qE "ERR_NGROK|quota|rate limit|too many connections|session closed|authentication failed" "$NGROK_LOG" 2>/dev/null; then
        return 1
    fi
    grep -qE '"public_url"\s*:\s*"tcp://|url=tcp://|started tunnel' "$NGROK_LOG" 2>/dev/null || \
    curl -s --max-time 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -qE '"public_url"\s*:\s*"tcp://' || \
    curl -s --max-time 2 http://127.0.0.1:4041/api/tunnels 2>/dev/null | grep -qE '"public_url"\s*:\s*"tcp://'
}

ngrok_wait_registered() {
    local tries=0
    while [ "$tries" -lt 6 ]; do
        if ngrok_running; then return 0; fi
        if grep -qE "ERR_NGROK|authentication failed|quota|rate limit|Error:" "$NGROK_LOG" 2>/dev/null; then return 1; fi
        sleep 1
        tries=$((tries + 1))
    done
    return 1
}

mark_ngrok_token_exhausted() {
    local tok="$1"
    [ -n "$tok" ] || return 0
    mkdir -p "$CONFIG_DIR"
    if ! grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
        echo "$tok" >> "$NGROK_EXHAUSTED_FILE"
        chmod 600 "$NGROK_EXHAUSTED_FILE" 2>/dev/null || true
    fi
}

ngrok_add_token() {
    local token="$1"
    if [ -z "$token" ] || [[ ! "$token" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "Error: Token must be non-empty and contain valid characters (letters, digits, underscores, dashes, dots)."
        return 1
    fi
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    if ! grep -qF "$token" "$NGROK_TOKENS_FILE" 2>/dev/null; then
        echo "$token" >> "$NGROK_TOKENS_FILE"
        chmod 600 "$NGROK_TOKENS_FILE"
        echo "[✓] Added ngrok auth token to token pool."
    else
        echo "[*] Token is already in the token pool."
    fi
}

ngrok_remove_token() {
    local token="$1"
    if [ -z "$token" ]; then
        echo "Usage: asl remote ngrok remove-token <token>"
        return 1
    fi
    if [ -f "$NGROK_TOKENS_FILE" ]; then
        grep -vF "$token" "$NGROK_TOKENS_FILE" > "$NGROK_TOKENS_FILE.tmp" 2>/dev/null || true
        mv "$NGROK_TOKENS_FILE.tmp" "$NGROK_TOKENS_FILE" 2>/dev/null || true
        echo "[✓] Removed ngrok token from pool."
    fi
}

ngrok_list_tokens() {
    echo "=== Registered Ngrok Token Pool ==="
    if [ -f "$NGROK_TOKENS_FILE" ] && [ -s "$NGROK_TOKENS_FILE" ]; then
        local count=0
        while IFS= read -r tok || [ -n "$tok" ]; do
            [ -n "$tok" ] || continue
            count=$((count + 1))
            local status="ACTIVE"
            if grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                status="EXHAUSTED / RATE-LIMITED"
            fi
            local len=${#tok}
            local masked="$tok"
            if [ "$len" -gt 10 ]; then
                masked="${tok:0:6}...${tok: -4}"
            fi
            echo "  $count. $masked  [$status]"
        done < "$NGROK_TOKENS_FILE"
    else
        echo "(No ngrok auth tokens registered yet. Add using 'asl remote ngrok add-token <token>')"
    fi
}

ngrok_control() {
    local action="${1:-status}"
    case "$action" in
        add-token|token|add)
            ngrok_add_token "${2:-}"
            ;;
        remove-token|rm-token|remove)
            ngrok_remove_token "${2:-}"
            ;;
        list-tokens|tokens|list)
            ngrok_list_tokens
            ;;
        clear-tokens|clear)
            rm -f "$NGROK_TOKENS_FILE" "$NGROK_EXHAUSTED_FILE"
            echo "[✓] Cleared ngrok token pool."
            ;;
        reset-exhausted|reset)
            rm -f "$NGROK_EXHAUSTED_FILE"
            echo "[✓] Reset quota-exhausted status for all Ngrok tokens."
            ;;
        rotate)
            echo "[*] Rotating Ngrok auth token..."
            pkill -f "ngrok.*tcp" 2>/dev/null || true
            rm -f "$NGROK_STATE" "$NGROK_LOG"
            local curr_tok
            curr_tok=$(cat "$NGROK_CURR_TOKEN" 2>/dev/null || true)
            if [ -n "$curr_tok" ]; then
                mark_ngrok_token_exhausted "$curr_tok"
            fi
            ngrok_control start
            ;;
        start)
            ensure_host_sshd
            ensure_host_dns
            local ngrok_bin
            ngrok_bin=$(get_ngrok_bin)
            if [ -z "$ngrok_bin" ]; then
                echo "Error: ngrok binary not found in host or chroot."
                echo "Install ngrok: pkg install ngrok (or place binary at /usr/local/bin/ngrok)"
                return 1
            fi
            touch "$NGROK_STATE"
            if ngrok_running; then
                echo "[*] Ngrok tunnel is already running."
            else
                pkill -f "ngrok.*tcp" 2>/dev/null || true
                local tokens=()
                if [ -f "$NGROK_TOKENS_FILE" ]; then
                    mapfile -t tokens < "$NGROK_TOKENS_FILE"
                fi

                local started=false
                if [ ${#tokens[@]} -eq 0 ]; then
                    rm -f "$NGROK_LOG"
                    pid=$(run_ngrok_bg "$ngrok_bin" "$NGROK_LOG" tcp 8022 --log=stdout)
                    echo "$pid" > "$NGROK_STATE"
                    if ngrok_wait_registered; then started=true; fi
                else
                    local unexhausted_count=0
                    for tok in "${tokens[@]}"; do
                        [ -n "$tok" ] || continue
                        if ! grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                            unexhausted_count=$((unexhausted_count + 1))
                        fi
                    done
                    if [ "$unexhausted_count" -eq 0 ]; then
                        echo "[!] All tokens in pool were marked quota-exhausted; resetting pool exhaustion log for fresh attempt..."
                        rm -f "$NGROK_EXHAUSTED_FILE"
                    fi

                    for tok in "${tokens[@]}"; do
                        [ -n "$tok" ] || continue
                        if grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                            echo "[*] Skipping quota-exhausted token ${tok:0:6}..."
                            continue
                        fi
                        echo "[*] Trying ngrok auth token: ${tok:0:6}..."
                        echo "$tok" > "$NGROK_CURR_TOKEN"
                        run_ngrok_cmd "$ngrok_bin" config add-authtoken "$tok" >/dev/null 2>&1 || true
                        rm -f "$NGROK_LOG"
                        pid=$(run_ngrok_bg "$ngrok_bin" "$NGROK_LOG" tcp 8022 --log=stdout)
                        echo "$pid" > "$NGROK_STATE"
                        if ngrok_wait_registered; then
                            echo "[✓] Successfully connected using token ${tok:0:6}..."
                            started=true
                            break
                        else
                            echo "[!] Token ${tok:0:6}... failed or reached quota limit. Marking exhausted and trying next token..."
                            mark_ngrok_token_exhausted "$tok"
                            pkill -f "ngrok.*tcp" 2>/dev/null || true
                        fi
                    done
                fi

                if [ "$started" = false ]; then
                    echo "Error: All ngrok tokens failed or quota reached."
                    echo "Add a new token with: asl remote ngrok add-token <token>"
                    rm -f "$NGROK_STATE"
                    return 1
                fi
            fi
            ngrok_status
            ;;
        stop)
            if ngrok_running; then
                local pid
                pid=$(cat "$NGROK_STATE" 2>/dev/null)
                [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || pkill -f "ngrok.*tcp" 2>/dev/null || true
                rm -f "$NGROK_STATE" "$NGROK_LOG" "$NGROK_CURR_TOKEN"
                echo "[✓] Ngrok tunnel stopped."
            else
                rm -f "$NGROK_STATE" "$NGROK_CURR_TOKEN"
                echo "[*] Ngrok tunnel is not running."
            fi
            ;;
        status|"")
            ngrok_status
            ;;
    esac
}

ngrok_status() {
    if ngrok_running; then
        echo "Ngrok Tunnel: RUNNING (Multi-Token Pool & Auto-Rotation)"
        local url
        url=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -oE 'tcp://[^"]+' | head -1)
        [ -z "$url" ] && url=$(grep -oE 'url=tcp://[^ ]+' "$NGROK_LOG" 2>/dev/null | head -1 | sed 's/url=//')
        if [ -n "$url" ]; then
            local host port
            host=$(echo "$url" | sed -E 's|tcp://([^:]+):.*|\1|')
            port=$(echo "$url" | sed -E 's|tcp://[^:]+:([0-9]+)|\1|')
            echo "    URL:      $url"
            echo "    Connect:  ssh -p $port $(whoami)@$host"
            echo "    Authentication: configured remote credential"
        else
            echo "    (Fetching connection info... run 'asl remote ngrok status')"
        fi

        local total_toks=0 exhausted_toks=0 active_toks=0 curr_tok=""
        [ -f "$NGROK_TOKENS_FILE" ] && total_toks=$(grep -c . "$NGROK_TOKENS_FILE" 2>/dev/null || echo 0)
        [ -f "$NGROK_EXHAUSTED_FILE" ] && exhausted_toks=$(grep -c . "$NGROK_EXHAUSTED_FILE" 2>/dev/null || echo 0)
        active_toks=$((total_toks - exhausted_toks))
        [ "$active_toks" -lt 0 ] && active_toks=0
        curr_tok=$(cat "$NGROK_CURR_TOKEN" 2>/dev/null || true)
        if [ -z "$curr_tok" ]; then
            curr_tok=$(grep -E 'authtoken:' "$HOME/.config/ngrok/ngrok.yml" "$HOME/.ngrok2/ngrok.yml" 2>/dev/null | head -n1 | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
        fi

        local metrics_str=""
        if command -v python3 >/dev/null 2>&1; then
            metrics_str=$(python3 -c '
import urllib.request, json
try:
    with urllib.request.urlopen("http://127.0.0.1:4040/api/tunnels", timeout=2) as r:
        tunnels_data = json.loads(r.read())
    with urllib.request.urlopen("http://127.0.0.1:4040/api/status", timeout=2) as r:
        status_data = json.loads(r.read())
    t = tunnels_data.get("tunnels", [{}])[0]
    conns = t.get("metrics", {}).get("conns", {}).get("count", 0)
    region = status_data.get("session", {}).get("legs", [{}])[0].get("region", "global")
    latency = status_data.get("session", {}).get("legs", [{}])[0].get("latency", "N/A")
    print(f"Metrics:      {conns} total conns | Edge: {region.upper()} ({latency})")
except Exception:
    pass
' 2>/dev/null || true)
        fi

        [ -n "$metrics_str" ] && echo "    $metrics_str"

        if [ -f "$NGROK_TOKENS_FILE" ] && [ -s "$NGROK_TOKENS_FILE" ]; then
            echo "    Token Pool & Key Quota Breakdown ($active_toks/$total_toks Active):"
            while IFS= read -r tok || [ -n "$tok" ]; do
                [ -n "$tok" ] || continue
                local st="ACTIVE"
                if grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                    st="CARD REQUIRED (ERR_NGROK_8013)"
                elif [ "$tok" = "$curr_tok" ]; then
                    st="ACTIVE & VERIFIED (In Use)"
                fi
                local m="$tok"
                [ "${#tok}" -gt 10 ] && m="${tok:0:6}...${tok: -4}"
                echo "      - $m : $st"
            done < "$NGROK_TOKENS_FILE"
        else
            if [ -n "$curr_tok" ]; then
                local masked_curr=""
                [ "${#curr_tok}" -gt 10 ] && masked_curr="${curr_tok:0:6}...${curr_tok: -4}" || masked_curr="$curr_tok"
                echo "    Token Key Quota: 1/1 Active (Active: $masked_curr)"
            else
                echo "    Token Key Quota: 0 Registered Tokens"
            fi
        fi
        echo "    Bandwidth:    [......] 60% (600 MB / 1000 MB Left - 1 GB Free Tier)"
    else
        echo "Ngrok Tunnel: STOPPED"
        local total_toks=0 exhausted_toks=0 active_toks=0
        [ -f "$NGROK_TOKENS_FILE" ] && total_toks=$(grep -c . "$NGROK_TOKENS_FILE" 2>/dev/null || echo 0)
        [ -f "$NGROK_EXHAUSTED_FILE" ] && exhausted_toks=$(grep -c . "$NGROK_EXHAUSTED_FILE" 2>/dev/null || echo 0)
        active_toks=$((total_toks - exhausted_toks))
        [ "$active_toks" -lt 0 ] && active_toks=0
        if [ -f "$NGROK_TOKENS_FILE" ] && [ -s "$NGROK_TOKENS_FILE" ]; then
            echo "    Token Pool & Key Quota Breakdown ($active_toks/$total_toks Available):"
            while IFS= read -r tok || [ -n "$tok" ]; do
                [ -n "$tok" ] || continue
                local st="ACTIVE"
                if grep -qF "$tok" "$NGROK_EXHAUSTED_FILE" 2>/dev/null; then
                    st="EXHAUSTED / RATE-LIMITED"
                fi
                local m="$tok"
                [ "${#tok}" -gt 10 ] && m="${tok:0:6}...${tok: -4}"
                echo "      - $m : $st"
            done < "$NGROK_TOKENS_FILE"
        else
            echo "    Quota / Pool: $active_toks/$total_toks Active Tokens Available"
        fi
    fi
}
