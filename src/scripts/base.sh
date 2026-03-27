#!/system/bin/sh

[ -d "/data/adb/magisk" ] && export PATH="/data/adb/magisk:$PATH"
[ -d "/data/adb/ksu/bin" ] && export PATH="/data/adb/ksu/bin:$PATH"
[ -d "/data/adb/ap/bin" ] && export PATH="/data/adb/ap/bin:$PATH"

. /data/adb/agh/settings.conf

readonly AGH_DIR
readonly BIN_DIR
readonly SCRIPT_DIR
readonly PID_FILE
readonly MOD_PATH

language="zh"
locale=$(getprop persist.sys.locale 2>/dev/null || getprop ro.product.locale 2>/dev/null)
echo "$locale" | grep -qi "en" && language="en"

log() {
    local str
    [ "$language" = "en" ] && str="$1" || str="$2"
    echo "$(date "+%Y-%m-%d %H:%M:%S") $str" | tee -a "$AGH_DIR/history.log"
}

update_description() {
    [ -f "$MOD_PATH/module.prop" ] && sed -i "s/^description=.*/description=$([ "$language" = "en" ] && echo "$1" || echo "$2")/" "$MOD_PATH/module.prop"
}
