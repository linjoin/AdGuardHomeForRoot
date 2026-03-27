#!/system/bin/sh

. /data/adb/agh/scripts/base.sh

cleanup_stale_pid() {
    if [ -f "$PID_FILE" ]; then
        local stale_pid
        stale_pid="$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')"
        if [ -z "$stale_pid" ] || ! kill -0 "$stale_pid" 2>/dev/null || ! ps -p "$stale_pid" -o comm= 2>/dev/null | grep -q "AdGuardHome"; then
            rm -f "$PID_FILE"
            return 0
        fi
    fi
    return 1
}

start_adguardhome() {
    cleanup_stale_pid
    if [ -f "$PID_FILE" ]; then
        local adg_pid
        adg_pid="$(cat "$PID_FILE" 2>/dev/null)"
        log "AdGuardHome is already running" "AdGuardHome 已经在运行"
        su 2000 -c "cmd notification post -S messaging --conversation \"🌳AdGuardHome\" --message \"🌳AdGuardHome\":\"已经在运行\" \"AGH\" \"\$RANDOM\"" >/dev/null 2>&1 &
        exit 0
    fi

    export SSL_CERT_DIR="/system/etc/security/cacerts/"
    export TZ="Asia/Shanghai"

    busybox setuidgid "$adg_user:$adg_group" "$BIN_DIR/AdGuardHome" >"$AGH_DIR/bin.log" 2>&1 &
    local adg_pid=$!
    local max_wait=15
    local wait_count=0

    while [ $wait_count -lt $max_wait ]; do
        if kill -0 "$adg_pid" 2>/dev/null && ps -p "$adg_pid" -o comm= 2>/dev/null | grep -q "AdGuardHome"; then
            break
        fi
        sleep 0.1
        wait_count=$((wait_count + 1))
    done

    if kill -0 "$adg_pid" 2>/dev/null && ps -p "$adg_pid" -o comm= 2>/dev/null | grep -q "AdGuardHome"; then
        echo "$adg_pid" >"$PID_FILE"
        if [ -x "$SCRIPT_DIR/setcpu.sh" ]; then
            "$SCRIPT_DIR/setcpu.sh" &
        fi
        if [ "$enable_iptables" = "true" ]; then
            $SCRIPT_DIR/iptables.sh enable &
            log "🌳 started PID: $adg_pid iptables: enabled" "🌳 启动成功 PID: $adg_pid iptables 已启用"
            update_description "🌳 Started PID: $adg_pid iptables: enabled" "🌳 启动成功 PID: $adg_pid iptables 已启用"
            su 2000 -c "cmd notification post -S messaging --conversation \"🌳启动成功\" --message \"🌳启动成功\":\"PID:$adg_pid iptables 已启用\" \"AGH\" \"\$RANDOM\"" >/dev/null 2>&1 &
        else
            log "🌳 started PID: $adg_pid iptables: disabled" "🌳 启动成功 PID: $adg_pid iptables 已禁用"
            update_description "🌳 Started PID: $adg_pid iptables: disabled" "🌳 启动成功 PID: $adg_pid iptables 已禁用"
            su 2000 -c "cmd notification post -S messaging --conversation \"🌳启动成功\" --message \"🌳启动成功\":\"PID:$adg_pid iptables 已禁用\" \"AGH\" \"\$RANDOM\"" >/dev/null 2>&1 &
        fi
    else
        kill -9 "$adg_pid" 2>/dev/null
        wait "$adg_pid" 2>/dev/null
        log "🪵 Error occurred, check logs for details" "🪵 出现错误，请检查位于/data/adb/agh/debug.log日志以获取详细信息"
        update_description "🪵 Error occurred, check logs for details" "🪵 出现错误，请检查位于/data/adb/agh/debug.log日志以获取详细信息"
        su 2000 -c "cmd notification post -S messaging --conversation \"🪵启动失败\" --message \"🪵启动失败\":\"出现错误，请检查位于/data/adb/agh/debug.log日志\" \"AGH\" \"\$RANDOM\"" >/dev/null 2>&1 &
        $SCRIPT_DIR/debug.sh &
        exit 1
    fi
}

stop_adguardhome() {
    local pid
    if [ -f "$PID_FILE" ]; then
        pid="$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')"
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
        log "🪵 AdGuardHome stopped" "🪵 AdGuardHome 已停止"
        su 2000 -c "cmd notification post -S messaging --conversation \"🪵已停止\" --message \"🪵已停止\":\"AdGuardHome 已停止\" \"AGH\" \"\$RANDOM\"" >/dev/null 2>&1 &
    else
        pkill -f "AdGuardHome" 2>/dev/null || pkill -9 -f "AdGuardHome" 2>/dev/null
        log "🪵 AdGuardHome force stopped" "🪵 AdGuardHome 强制停止"
        su 2000 -c "cmd notification post -S messaging --conversation \"🪵强制停止\" --message \"🪵强制停止\":\"AdGuardHome 强制停止\" \"AGH\" \"\$RANDOM\"" >/dev/null 2>&1 &
    fi
    update_description "🪵 Stopped" "🪵 已停止"
    $SCRIPT_DIR/iptables.sh disable &
}

toggle_adguardhome() {
    cleanup_stale_pid
    if [ -f "$PID_FILE" ]; then
        local current_pid
        current_pid="$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')"
        if [ -n "$current_pid" ] && kill -0 "$current_pid" 2>/dev/null && ps -p "$current_pid" -o comm= 2>/dev/null | grep -q "AdGuardHome"; then
            stop_adguardhome
            return
        fi
    fi
    start_adguardhome
}

case "$1" in
    start) start_adguardhome ;;
    stop) stop_adguardhome ;;
    toggle) toggle_adguardhome ;;
    *) echo "Usage: $0 {start|stop|toggle}"; exit 1 ;;
esac