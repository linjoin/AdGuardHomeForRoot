#!/system/bin/sh

MODULE_DIR="/data/adb/modules/AdGuardHome"
MODULE_UPDATE_DIR="/data/adb/modules_update/AdGuardHome"
AGH_DIR="/data/adb/agh"
AGH_SCRIPT_DIR="$AGH_DIR/scripts"
VALIDATION_FILE="$MODULE_DIR/Validation"
MODULE_PROP="$MODULE_DIR/module.prop"
VALIDATION_KEY="X7kL9pQ2rM5vN3jH8fD1"
BOX_SINGBOX="/data/adb/box/sing-box/config.json"
BOX_MIHOMO="/data/adb/box/mihomo/config.yaml"
MODULE_SINGBOX="$MODULE_DIR/box/sing-box/config.json"
MODULE_MIHOMO="$MODULE_DIR/box/mihomo/config.yaml"

wait_for_boot() {
    while [ "$(getprop init.svc.bootanim)" != "stopped" ]; do
        sleep 15
    done
}

update_module_description() {
    [ -f "$MODULE_PROP" ] || return 0

    if [ "$language" = "en" ]; then
        sed -i "s/^description=.*/description=$1/" "$MODULE_PROP"
    else
        sed -i "s/^description=.*/description=$2/" "$MODULE_PROP"
    fi
}

files_match_if_present() {
    _src="$1"
    _dst="$2"

    if [ ! -f "$_src" ] || [ ! -f "$_dst" ]; then
        return 0
    fi

    diff -q "$_src" "$_dst" >/dev/null 2>&1
}

validate_installation() {
    [ -f "$VALIDATION_FILE" ] || return 0

    _content=$(cat "$VALIDATION_FILE" 2>/dev/null)
    if [ "$_content" != "$VALIDATION_KEY" ]; then
        update_module_description \
            "Invalid validation key, service stopped" \
            "校验密钥无效，服务已停止"
        return 1
    fi

    files_match_if_present "$MODULE_SINGBOX" "$BOX_SINGBOX" || {
        update_module_description \
            "Box configuration not synchronized, service suspended" \
            "Box配置未同步，服务已暂停"
        return 1
    }

    files_match_if_present "$MODULE_MIHOMO" "$BOX_MIHOMO" || {
        update_module_description \
            "Box configuration not synchronized, service suspended" \
            "Box配置未同步，服务已暂停"
        return 1
    }

    return 0
}

lock_recursive_if_exists() {
    [ -e "$1" ] || return 0
    chattr +i -R "$1" 2>/dev/null
}

lock_files() {
    lock_recursive_if_exists "$AGH_SCRIPT_DIR"

    if [ -d "$MODULE_DIR" ]; then
        find "$MODULE_DIR" -type f \
            ! -name "module.prop" \
            ! -name "update" \
            ! -name "uninstall.sh" \
            -exec chattr +i {} \; 2>/dev/null

        lock_recursive_if_exists "$MODULE_DIR/webroot"
        lock_recursive_if_exists "$MODULE_DIR/box"
    fi
}

start_services() {
    "$AGH_SCRIPT_DIR/tool.sh" start
    "$AGH_SCRIPT_DIR/setcpu.sh"

    inotifyd "$AGH_SCRIPT_DIR/inotify.sh" "${MODULE_DIR}:w,d,n,c,m" &
    inotifyd "$AGH_SCRIPT_DIR/inotify.sh" "/data/adb/modules_update/:w,d,n,c,m" &
}

toggle_airplane_if_needed() {
    if [ "$(settings get global airplane_mode_on)" = "1" ]; then
        return 0
    fi

    sleep 30
    settings put global airplane_mode_on 1
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true
    sleep 3
    settings put global airplane_mode_on 0
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false
}

main() {
    wait_for_boot
    rm -rf "$MODULE_UPDATE_DIR" 2>/dev/null

    validate_installation || exit 0

    lock_files
    start_services
    toggle_airplane_if_needed
}

main