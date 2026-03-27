#!/system/bin/sh

LOG_FILE="/data/adb/agh/monitor_debug.log"
if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.bak" 2>/dev/null
fi

SCRIPT_DIR="$(dirname "$0")"
readonly EVENTS="$1"
readonly MONITOR_DIR="$2"
readonly MONITOR_FILE="$3"

log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] [PID:$$] $1" >> "$LOG_FILE"
}

log_debug "========== 监控事件触发 =========="
log_debug "EVENTS=${EVENTS}"
log_debug "MONITOR_DIR=${MONITOR_DIR}"
log_debug "MONITOR_FILE=${MONITOR_FILE}"
log_debug "SCRIPT_DIR=${SCRIPT_DIR}"

unlock_scripts() {
    chattr -i -R /data/adb/agh/scripts 2>/dev/null
}

lock_scripts() {
    chattr +i -R /data/adb/agh/scripts 2>/dev/null
}

unlock_modules() {
    find /data/adb/modules/AdGuardHome -type f ! -name "module.prop" ! -name "update" ! -name "uninstall.sh" -exec chattr -i {} \; 2>/dev/null
}

lock_modules() {
    find /data/adb/modules/AdGuardHome -type f ! -name "module.prop" ! -name "update" ! -name "uninstall.sh" -exec chattr +i {} \; 2>/dev/null
}

if [ "${MONITOR_DIR}" = "/data/adb/modules_update/" ]; then
    case "$EVENTS" in
        "n"|"m")
            log_debug "检测到 modules_update 目录活动（创建/修改），解除不可变属性"
            unlock_scripts
            if [ $? -eq 0 ]; then
                log_debug "解除 /data/adb/agh/scripts/ 🌳成功"
            else
                log_debug "解除 /data/adb/agh/scripts/ 🪵错误"
            fi
            unlock_modules
            if [ $? -eq 0 ]; then
                log_debug "解除 /data/adb/modules/AdGuardHome/ 🌳成功"
            else
                log_debug "解除 /data/adb/modules/AdGuardHome/ 🪵错误"
            fi
            ;;
        "d")
            log_debug "检测到 modules_update 目录被删除，恢复不可变属性"
            lock_scripts
            if [ $? -eq 0 ]; then
                log_debug "恢复 /data/adb/agh/scripts/ 🌳成功"
            else
                log_debug "恢复 /data/adb/agh/scripts/ 🪵错误"
            fi
            lock_modules
            if [ $? -eq 0 ]; then
                log_debug "恢复 /data/adb/modules/AdGuardHome/ 🌳成功"
            else
                log_debug "恢复 /data/adb/modules/AdGuardHome/ 🪵错误"
            fi
            ;;
    esac
fi

if [ "${MONITOR_DIR}" = "/data/adb/modules/AdGuardHome" ]; then
    case "$MONITOR_FILE" in
        "update")
            if [ "${EVENTS}" = "n" ]; then
                log_debug "检测到 update 文件，解除不可变属性"
                unlock_scripts
                if [ $? -eq 0 ]; then
                    log_debug "解除 /data/adb/agh/scripts/ 🌳成功"
                else
                    log_debug "解除 /data/adb/agh/scripts/ 🪵错误"
                fi
                unlock_modules
                if [ $? -eq 0 ]; then
                    log_debug "解除 /data/adb/modules/AdGuardHome/ 🌳成功"
                else
                    log_debug "解除 /data/adb/modules/AdGuardHome/ 🪵错误"
                fi
            fi
            ;;
        .uninstall_test_*)
            if [ "${EVENTS}" = "n" ]; then
                log_debug "检测到卸载测试文件，停止服务"
                $SCRIPT_DIR/tool.sh stop
                if [ $? -eq 0 ]; then
                    log_debug "tool.sh stop 🌳成功"
                else
                    log_debug "tool.sh stop 🪵错误"
                fi
            fi
            ;;
        "disable")
            if [ "${EVENTS}" = "n" ]; then
                log_debug "disable 文件创建，停止服务"
                $SCRIPT_DIR/tool.sh stop
                if [ $? -eq 0 ]; then
                    log_debug "tool.sh stop 🌳成功"
                else
                    log_debug "tool.sh stop 🪵错误"
                fi
            elif [ "${EVENTS}" = "d" ]; then
                log_debug "disable 文件删除，启动服务"
                $SCRIPT_DIR/tool.sh start
                if [ $? -eq 0 ]; then
                    log_debug "tool.sh start 🌳成功"
                else
                    log_debug "tool.sh start 🪵错误"
                fi
            fi
            ;;
    esac
fi

log_debug "========== 事件处理结束 =========="
log_debug ""