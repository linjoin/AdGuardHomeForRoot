#!/system/bin/sh

export PATH="/system/bin:/system/xbin:/vendor/bin:/sbin:$PATH"

CONFIG_FILE="/data/adb/agh/settings.conf"
LOG_FILE="/data/adb/agh/inotifyd.log"
LOCK_DIR="/data/adb/agh/inotifyd.lock"

readonly EVENTS="$1"
readonly MONITOR_DIR="${2:-/data/adb/modules_update}"
readonly MONITOR_FILE="$3"

SCRIPTS_DIR="/data/adb/agh/scripts"
MODULE_DIR="/data/adb/modules/AdGuardHome"
WEBROOT_DIR="$MODULE_DIR/webroot"
BOX_DIR="$MODULE_DIR/box"

LOG_MAX_SIZE=20480
LOCK_TIMEOUT=10

find_busybox() {
    _bb=""

    for _path in "/data/adb/ksu/bin/busybox" "/data/adb/ap/bin/busybox" "/data/adb/magisk/busybox"; do
        [ -x "$_path" ] && _bb="$_path" && break
    done

    [ -z "$_bb" ] && _bb="busybox"

    for _applet in grep head cut tr stat find tail wc cat chattr mkdir rm; do
        if ! "$_bb" "$_applet" --help >/dev/null 2>&1 && \
           ! "$_bb" "$_applet" >/dev/null 2>&1; then
            echo ""
            return 1
        fi
    done

    echo "$_bb"
}

read_log_level() {
    [ -f "$CONFIG_FILE" ] || {
        echo 3
        return 0
    }

    _level=$(
        "$BB" grep "^inotify_log_level=" "$CONFIG_FILE" 2>/dev/null |
        "$BB" head -n 1 |
        "$BB" cut -d'=' -f2 |
        "$BB" tr -d '"' |
        "$BB" tr -d "'"
    )

    [ -n "$_level" ] && echo "$_level" || echo 3
}

is_process_alive() {
    [ -n "$1" ] || return 1
    [ -d "/proc/$1" ]
}

acquire_lock() {
    _start="$(date +%s)"

    while :; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo "$$" > "$LOCK_DIR/pid" 2>/dev/null || {
                "$BB" rm -rf "$LOCK_DIR" 2>/dev/null
                continue
            }
            return 0
        fi

        if [ -d "$LOCK_DIR" ] && [ ! -f "$LOCK_DIR/pid" ]; then
            sleep 1
            if [ -d "$LOCK_DIR" ] && [ ! -f "$LOCK_DIR/pid" ]; then
                "$BB" rm -rf "$LOCK_DIR" 2>/dev/null
                continue
            fi
        fi

        if [ -f "$LOCK_DIR/pid" ]; then
            _pid="$("$BB" cat "$LOCK_DIR/pid" 2>/dev/null)"
            if [ -n "$_pid" ] && ! is_process_alive "$_pid"; then
                "$BB" rm -rf "$LOCK_DIR" 2>/dev/null
                continue
            fi
        fi

        _now="$(date +%s)"
        [ $((_now - _start)) -ge "$LOCK_TIMEOUT" ] && return 1
        sleep 1
    done
}

release_lock() {
    if [ -f "$LOCK_DIR/pid" ]; then
        if [ "$("$BB" cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
            "$BB" rm -rf "$LOCK_DIR" 2>/dev/null
        fi
    fi
}

rotate_log() {
    [ ! -f "$LOG_FILE" ] && return 0

    _size=$("$BB" stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$_size" -gt "$LOG_MAX_SIZE" ] || return 0

    _tmp="${LOG_FILE}.tmp.$$"
    "$BB" tail -c "$LOG_MAX_SIZE" "$LOG_FILE" > "$_tmp" 2>/dev/null
    "$BB" cat "$_tmp" > "$LOG_FILE"
    "$BB" rm -f "$_tmp"

    log_msg "INFO" 3 "日志已轮转 (>${LOG_MAX_SIZE}字节,保留最后${LOG_MAX_SIZE}字节)"
}

check_paths() {
    [ -d "$MODULE_DIR" ] || {
        log_msg "ERROR" 1 "MODULE_DIR不存在: $MODULE_DIR"
        return 1
    }

    [ -d "$SCRIPTS_DIR" ] || {
        log_msg "ERROR" 1 "SCRIPTS_DIR不存在: $SCRIPTS_DIR"
        return 1
    }

    [ -d "$MONITOR_DIR" ] || {
        log_msg "ERROR" 1 "MONITOR_DIR不存在: $MONITOR_DIR"
        return 1
    }

    return 0
}

log_msg() {
    _tag="$1"
    _level="$2"
    _msg="$3"

    [ "$_level" -le "$inotify_log_level" ] || return 0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$_tag] [PID:$$] $_msg" >> "$LOG_FILE"
}

log_by_exit() {
    _msg="$1"
    _code="$2"

    case "$_code" in
        0)
            log_msg "INFO" 3 "$_msg (OK)"
            ;;
        1)
            log_msg "ERROR" 1 "$_msg (ERROR)"
            ;;
        *)
            log_msg "WARN" 2 "$_msg (WARN, exit=$_code)"
            ;;
    esac
}

attr_flag() {
    [ "$1" = "unlock" ] && echo "-i" || echo "+i"
}

merge_status() {
    _has_warn=0

    for _code in "$@"; do
        [ "$_code" -eq 1 ] && {
            echo 1
            return 0
        }

        [ "$_code" -ne 0 ] && _has_warn=1
    done

    [ "$_has_warn" -eq 1 ] && echo 2 || echo 0
}

chattr_recursive() {
    _op="$1"
    _target="$2"
    _flag="$(attr_flag "$_op")"

    log_msg "DEBUG" 4 "chattr_recursive: op=$_op target=$_target"

    "$BB" chattr "$_flag" -R "$_target" 2>/dev/null
    _ret=$?

    log_by_exit "[$_op] $_target" "$_ret"
    return "$_ret"
}

handle_scripts() {
    _op="$1"

    log_msg "DEBUG" 4 "handle_scripts: op=$_op"
    chattr_recursive "$_op" "$SCRIPTS_DIR"
}

handle_modules() {
    _op="$1"
    _flag="$(attr_flag "$_op")"
    _had_error=0

    log_msg "DEBUG" 4 "handle_modules: op=$_op"

    "$BB" find "$MODULE_DIR" -type f \
        ! -name "module.prop" \
        ! -name "update" \
        ! -name "uninstall.sh" \
        -exec "$BB" chattr "$_flag" {} \; 2>/dev/null
    _find_ret=$?
    log_msg "DEBUG" 4 "handle_modules: find exit=$_find_ret"
    [ "$_find_ret" -ne 0 ] && _had_error=1

    if [ -d "$WEBROOT_DIR" ]; then
        "$BB" chattr "$_flag" -R "$WEBROOT_DIR" 2>/dev/null
        _web_ret=$?
        log_msg "DEBUG" 4 "handle_modules: webroot exit=$_web_ret"
        [ "$_web_ret" -ne 0 ] && _had_error=1
    else
        _web_ret=0
        log_msg "DEBUG" 4 "handle_modules: webroot 不存在,跳过"
    fi

    if [ -d "$BOX_DIR" ]; then
        "$BB" chattr "$_flag" -R "$BOX_DIR" 2>/dev/null
        _box_ret=$?
        log_msg "DEBUG" 4 "handle_modules: box exit=$_box_ret"
        [ "$_box_ret" -ne 0 ] && _had_error=1
    else
        _box_ret=0
        log_msg "DEBUG" 4 "handle_modules: box 不存在,跳过"
    fi

    _final=0
    [ "$_had_error" -eq 1 ] && _final=1

    log_by_exit "[$_op] modules/AdGuardHome/" "$_final"
    return "$_final"
}

handle_event() {
    _op="$1"
    _event_name="${EVENTS:-direct}"

    log_msg "INFO" 3 "[event:${_event_name}] $_op dir=$MONITOR_DIR file=$MONITOR_FILE"
    log_msg "DEBUG" 4 "handle_event: EVENTS=${EVENTS:-direct} op=$_op"

    handle_scripts "$_op"
    _ret_scripts=$?

    handle_modules "$_op"
    _ret_modules=$?

    log_msg "DEBUG" 4 "handle_event: ret_scripts=$_ret_scripts ret_modules=$_ret_modules"

    _final="$(merge_status "$_ret_scripts" "$_ret_modules")"
    log_by_exit "[event:${_event_name}] $_op completed" "$_final"

    [ "$_final" -eq 0 ] && log_msg "INFO" 3 "✓ 全部成功"
    return "$_final"
}

check_dir_empty() {
    if [ ! -r "$MONITOR_DIR" ] || [ ! -x "$MONITOR_DIR" ]; then
        echo "error"
        return 1
    fi

    _count=$(
        "$BB" find "$MONITOR_DIR" -mindepth 1 -maxdepth 1 2>/dev/null |
        "$BB" wc -l |
        "$BB" tr -d ' '
    )

    case "$_count" in
        ''|*[!0-9]*)
            echo "error"
            return 1
            ;;
    esac

    [ "$_count" -eq 0 ] && echo "empty" || echo "has_file"
}

sync_state() {
    _state="$(check_dir_empty)"

    if [ "$_state" = "error" ]; then
        log_msg "ERROR" 1 "无法访问监控目录: $MONITOR_DIR"
        return 1
    fi

    log_msg "DEBUG" 4 "sync_state: dir_state=$_state"

    if [ "$_state" = "has_file" ]; then
        log_msg "INFO" 3 "检测到文件 → 解除锁定"
        handle_event "unlock"
    else
        log_msg "INFO" 3 "目录为空 → 执行锁定"
        handle_event "lock"
    fi
}

BB="$(find_busybox)"
[ -z "$BB" ] && {
    echo "错误: BusyBox 不可用或缺少必要 applet" >&2
    exit 1
}

inotify_log_level="$(read_log_level)"

acquire_lock || {
    log_msg "WARN" 2 "获取锁超时，退出"
    exit 1
}

trap 'release_lock' EXIT INT TERM

rotate_log

check_paths || exit 1

log_msg "DEBUG" 4 "script_start: args=$* level=$inotify_log_level BB=$BB"

if [ -z "$EVENTS" ]; then
    sync_state
    _exit_code=$?
    log_msg "DEBUG" 4 "script_end (direct_call)"
    exit "$_exit_code"
fi

case "$EVENTS" in
    w|n|c|m|d)
        sync_state
        _exit_code=$?
        log_msg "DEBUG" 4 "script_end"
        exit "$_exit_code"
        ;;
    *)
        log_msg "WARN" 2 "[event:$EVENTS] unknown event type"
        log_msg "DEBUG" 4 "script_end"
        exit 0
        ;;
esac