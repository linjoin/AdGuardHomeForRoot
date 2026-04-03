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
locale="$(getprop persist.sys.locale 2>/dev/null)"
[ -n "$locale" ] || locale="$(getprop ro.product.locale 2>/dev/null)"
echo "$locale" | grep -qi "en" && language="en"

log() {
    local str
    if [ "$language" = "en" ]; then
        str="$1"
    else
        str="$2"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $str" | tee -a "$AGH_DIR/history.log"
}

update_description() {
    local desc
    [ -f "$MOD_PATH/module.prop" ] || return 0

    if [ "$language" = "en" ]; then
        desc="$1"
    else
        desc="$2"
    fi

    sed -i "s/^description=.*/description=$desc/" "$MOD_PATH/module.prop"
}