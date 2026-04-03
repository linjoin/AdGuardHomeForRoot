#!/system/bin/sh

. /data/adb/agh/scripts/base.sh

AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
MODULE_PROP="$AGH_MODULE_DIR/module.prop"
SETTINGS_FILE="/data/adb/agh/settings.conf"

is_en() {
    [ "$language" = "en" ]
}

pick() {
    if is_en; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

running_pid() {
    pid="$1"
    [ -n "$pid" ] &&
    kill -0 "$pid" 2>/dev/null &&
    ps -p "$pid" -o comm= 2>/dev/null | grep -q "AdGuardHome"
}

update_description() {
    [ -f "$MODULE_PROP" ] || return 0
    sed -i "s/^description=.*/description=$(pick "$1" "$2")/" "$MODULE_PROP"
}

notify() {
    [ "$enable_notification" = "true" ] || return 0
    title="$1"
    msg="$2"
    su 2000 -c "cmd notification post -S messaging --conversation \"$title\" --message \"$title\":\"$msg\" \"AGH\" \"\$RANDOM\"" >/dev/null 2>&1 &
}

notify_lang() {
    [ "$enable_notification" = "true" ] || return 0
    notify "$(pick "$1" "$3")" "$(pick "$2" "$4")"
}

cleanup_stale_pid() {
    [ -f "$PID_FILE" ] || return 1

    stale_pid="$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')"
    running_pid "$stale_pid" && return 1

    rm -f "$PID_FILE"
    return 0
}

set_iptables_status() {
    if [ "$enable_iptables" = "true" ]; then
        status_en="iptables enabled"
        status_zh="iptables已启用"
    else
        status_en="iptables disabled"
        status_zh="iptables未启用"
    fi
}

report_already_running() {
    pid="$1"
    log "AdGuardHome For Root AutoOpt is already running (PID: $pid)" \
        "AdGuardHome For Root AutoOpt 已运行 (PID: $pid)"
    notify_lang \
        "AdGuardHome For Root Already Running" "PID:$pid" \
        "AdGuardHome For Root 已在运行" "PID:$pid"
}

report_start_success() {
    pid="$1"
    set_iptables_status

    log "AdGuardHome For Root AutoOpt started successfully (PID: $pid)" \
        "启用成功 PID:$pid $status_zh"
    update_description \
        "AdGuardHome For Root AutoOpt Running - PID:$pid $status_en" \
        "启用成功 PID:$pid $status_zh"
    notify_lang \
        "AdGuardHome For Root Startup Success" "PID:$pid, $status_en" \
        "AdGuardHome For Root 启动成功" "PID:$pid，$status_zh"
}

report_start_failure() {
    log \
        "AdGuardHome For Root AutoOpt failed to start, check /data/adb/agh/debug.log for details" \
        "AdGuardHome For Root AutoOpt 启动失败，详情查看 /data/adb/agh/debug.log"
    update_description \
        "AdGuardHome For Root AutoOpt Startup Failed, Check Logs" \
        "AdGuardHome For Root AutoOpt 启动失败，请查看日志"
    notify_lang \
        "AdGuardHome For Root Startup Failed" "Check /data/adb/agh/debug.log" \
        "AdGuardHome For Root 启动失败" "查看 /data/adb/agh/debug.log"
}

report_stopped() {
    log "AdGuardHome For Root AutoOpt stopped" "AdGuardHome For Root AutoOpt 已停止"
    notify_lang \
        "AdGuardHome For Root Service Stopped" "Service stopped" \
        "AdGuardHome For Root 服务已停止" "服务已停止"
    update_description \
        "AdGuardHome For Root AutoOpt Stopped" \
        "AdGuardHome For Root AutoOpt 已停止"
}

report_force_stopped() {
    log "AdGuardHome For Root AutoOpt force stopped" "AdGuardHome For Root AutoOpt 已强制停止"
    notify_lang \
        "AdGuardHome For Root Force Stopped" "Force stopped" \
        "AdGuardHome For Root 强制停止" "强制停止"
}

start_adguardhome() {
    cleanup_stale_pid

    if [ -f "$PID_FILE" ]; then
        adg_pid="$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')"
        report_already_running "$adg_pid"
        return 0
    fi

    export SSL_CERT_DIR="/system/etc/security/cacerts/"
    export TZ="Asia/Shanghai"

    busybox setuidgid "$adg_user:$adg_group" "$BIN_DIR/AdGuardHome" >"$AGH_DIR/bin.log" 2>&1 &
    adg_pid=$!

    wait_count=0
    while [ $wait_count -lt 15 ]; do
        running_pid "$adg_pid" && break
        sleep 0.1
        wait_count=$((wait_count + 1))
    done

    if running_pid "$adg_pid"; then
        echo "$adg_pid" >"$PID_FILE"

        if [ -x "$SCRIPT_DIR/setcpu.sh" ]; then
            "$SCRIPT_DIR/setcpu.sh" &
        fi

        if [ "$enable_iptables" = "true" ]; then
            "$SCRIPT_DIR/iptables.sh" enable &
        fi

        report_start_success "$adg_pid"
        return 0
    fi

    kill -9 "$adg_pid" 2>/dev/null
    wait "$adg_pid" 2>/dev/null
    report_start_failure
    "$SCRIPT_DIR/debug.sh" &
    exit 1
}

stop_adguardhome() {
    if [ -f "$PID_FILE" ]; then
        pid="$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')"
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
        report_stopped
    else
        pkill -f "AdGuardHome" 2>/dev/null || pkill -9 -f "AdGuardHome" 2>/dev/null
        report_force_stopped
    fi

    "$SCRIPT_DIR/iptables.sh" disable &
}

toggle_adguardhome() {
    cleanup_stale_pid

    if [ -f "$PID_FILE" ]; then
        current_pid="$(cat "$PID_FILE" 2>/dev/null | tr -cd '0-9')"
        if running_pid "$current_pid"; then
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
