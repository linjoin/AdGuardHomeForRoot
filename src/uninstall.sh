#!/system/bin/sh

if [ -f "/data/adb/agh/bin/agh.pid" ]; then
    PID=$(cat /data/adb/agh/bin/agh.pid 2>/dev/null | tr -cd '0-9')
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        sleep 2
    fi
fi
iptables -t nat -D ADGUARD_REDIRECT_DNS -p udp --dport 53 -j REDIRECT --to-port 5591 2>/dev/null
iptables -t nat -D ADGUARD_REDIRECT_DNS -p tcp --dport 53 -j REDIRECT --to-port 5591 2>/dev/null
iptables -t nat -F ADGUARD_REDIRECT_DNS 2>/dev/null
iptables -t nat -X ADGUARD_REDIRECT_DNS 2>/dev/null

find /data/adb/agh 2>/dev/null -exec chattr -i {} \; 2>/dev/null
find /data/adb/modules/AdGuardHome 2>/dev/null -exec chattr -i {} \; 2>/dev/null

rm -rf /data/adb/agh
rm -rf /data/adb/modules/AdGuardHome