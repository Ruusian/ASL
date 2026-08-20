#!/bin/bash
# ASL Persistent Tunnel Manager - keeps the Oracle VPS reverse tunnel optimized

TUNNEL_PID_FILE="/tmp/asl-oracle-tunnel.pid"
TUNNEL_LOG="/tmp/asl-oracle-tunnel.log"

ensure_tunnel() {
    # Check if existing tunnel is alive
    if [ -f "$TUNNEL_PID_FILE" ]; then
        local pid=$(cat "$TUNNEL_PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    
    echo "[$(date +%H:%M:%S)] Establishing optimized Oracle VPS tunnel..."
    
    # Kill any stale tunnels
    pkill -f 'ssh.*oracle_vps.key' 2>/dev/null || true
    sleep 1
    
    # Start optimized tunnel with larger buffers
    nohup ssh -i ~/.ssh/oracle_vps.key \
        -T -N \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=~/.ssh/known_hosts \
        -o ServerAliveInterval=10 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=15 \
        -o TCPKeepAlive=yes \
        -o Compression=no \
        -R 2222:127.0.0.1:8022 \
        ubuntu@130.210.19.7 > "$TUNNEL_LOG" 2>&1 &
    
    echo $! > "$TUNNEL_PID_FILE"
    sleep 2
    
    if kill -0 $(cat "$TUNNEL_PID_FILE" 2>/dev/null) 2>/dev/null; then
        echo "[✓] Oracle VPS tunnel established (PID: $(cat $TUNNEL_PID_FILE))"
    else
        echo "[✗] Oracle VPS tunnel failed. Check $TUNNEL_LOG"
        return 1
    fi
}

case "${1:-status}" in
    start) ensure_tunnel ;;
    stop) 
        [ -f "$TUNNEL_PID_FILE" ] && kill -TERM $(cat "$TUNNEL_PID_FILE" 2>/dev/null) 2>/dev/null
        rm -f "$TUNNEL_PID_FILE"
        echo "[✓] Tunnel stopped"
        ;;
    status)
        if [ -f "$TUNNEL_PID_FILE" ] && kill -0 $(cat "$TUNNEL_PID_FILE" 2>/dev/null) 2>/dev/null; then
            echo "Oracle VPS Tunnel: RUNNING (PID: $(cat $TUNNEL_PID_FILE))"
        else
            echo "Oracle VPS Tunnel: STOPPED"
        fi
        ;;
esac
