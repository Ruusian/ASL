#!/bin/bash
# Connect a Raspberry Pi VNC viewer to the ASL desktop over USB tethering.

set -u

for command_name in ip vncviewer; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "[!] Required command '$command_name' not found." >&2
        exit 1
    fi
done

max_retries="${ASL_BRIDGE_RETRIES:-30}"
retry_count=0
phone_ip=""

echo "Starting ASL phone display bridge..."
while [ "$retry_count" -lt "$max_retries" ]; do
    phone_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')
    [ -n "$phone_ip" ] || phone_ip=$(ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '127.0.0.1' | head -1)
    [ -n "$phone_ip" ] || phone_ip=$(getprop dhcp.wlan0.ipaddress 2>/dev/null)
    [ -n "$phone_ip" ] || phone_ip=$(su -c "ip -4 route get 1.1.1.1 2>/dev/null" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')
    if [ -n "$phone_ip" ]; then
        break
    fi
    retry_count=$((retry_count + 1))
    echo "[-] Waiting for USB tethering... ($((max_retries - retry_count))s)"
    sleep 1
done

if [ -z "$phone_ip" ]; then
    echo "[!] No phone detected. Enable USB tethering and try again." >&2
    exit 1
fi

echo "[+] Connecting to ASL at $phone_ip..."
vncviewer "$phone_ip"::5901 \
    -FullScreen \
    -QualityLevel 4 \
    -CompressLevel 9 \
    -LowColorLevel 1 \
    -MenuKey=F8