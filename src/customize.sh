SKIPUNZIP=1

language="zh"

locale=$(getprop persist.sys.locale || getprop ro.product.locale || getprop persist.sys.language)

if echo "$locale" | grep -qi "en"; then
    language="en"
fi

function info() {
    [ "$language" = "en" ] && ui_print "$1" || ui_print "$2"
}

function error() {
    [ "$language" = "en" ] && abort "$1" || abort "$2"
}

function warn() {
    [ "$language" = "en" ] && ui_print "$1" || ui_print "$2"
}

AGH_DIR="/data/adb/agh"
AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
PROXY_SCRIPT="$AGH_DIR/scripts/ProxyConfig.sh"
BACKUP_DIR="/data/adb/modules/adg_installation_module"
USER_RULES_BAK="$BACKUP_DIR/user_rules.yaml.bak"

remove_immutable_recursive() {
    local target="$1"
    [ -e "$target" ] || return 0
    chattr -i -R "$target" 2>/dev/null
    find "$target" -exec chattr -i {} \; 2>/dev/null
    find "$target" -type d -exec chmod 755 {} \; 2>/dev/null
}

remove_immutable_recursive "/data/adb/modules_update/"
remove_immutable_recursive "$AGH_DIR"
remove_immutable_recursive "$AGH_MODULE_DIR"

backup_user_rules_block() {
    local yaml="$AGH_DIR/bin/AdGuardHome.yaml"
    [ -f "$yaml" ] || return 0
    local start
    start="$(grep -n "^[[:space:]]*user_rules:[[:space:]]*$" "$yaml" 2>/dev/null | head -n 1 | cut -d: -f1)"
    [ -n "$start" ] || return 0
    mkdir -p "$BACKUP_DIR"
    sed -n "${start},\$p" "$yaml" | sed -n '1p;2,$ {/^[^[:space:]#][^:]*:/q;p}' > "$USER_RULES_BAK"
    if [ ! -s "$USER_RULES_BAK" ]; then
        rm -f "$USER_RULES_BAK"
        return 0
    fi
    info "- 🌳 Backed up custom rules" "- 🌳 已备份自定义规则"
    return 0
}

restore_user_rules_block() {
    local yaml="$AGH_DIR/bin/AdGuardHome.yaml"
    [ -f "$yaml" ] || return 0
    [ -f "$USER_RULES_BAK" ] || return 0

    local tmp="$yaml.tmp"
    : > "$tmp" || return 0

    local skipping=false
    local replaced=false

    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skipping" = true ]; then
            if printf '%s\n' "$line" | grep -qE '^[^[:space:]#][^:]*:'; then
                skipping=false
                printf '%s\n' "$line" >> "$tmp"
            fi
            continue
        fi

        if printf '%s\n' "$line" | grep -qE '^[[:space:]]*user_rules:[[:space:]]*$'; then
            cat "$USER_RULES_BAK" >> "$tmp"
            replaced=true
            skipping=true
            continue
        fi

        printf '%s\n' "$line" >> "$tmp"
    done < "$yaml"

    if [ "$replaced" != true ]; then
        printf "\n" >> "$tmp"
        cat "$USER_RULES_BAK" >> "$tmp"
    fi

    mv "$tmp" "$yaml"

    info "- 🌳 Custom rules merged into the new config" "- 🌳 已将自定义规则合并到新的配置里"
    return 0
}

if [ -f "$PROXY_SCRIPT" ]; then
    info "- 🌳 AdGuardHome for Root, which detects the spring dream without trace, is executing the exclusive code to remove the immutable attributes..." "- 🌳 检测到春梦无痕的 AdGuardHome for Root，正在执行专属的解除不可变属性代码..."

    backup_user_rules_block

    pkill -9 "NoAdsService" 2>/dev/null
    pkill -9 "ProxyConfig" 2>/dev/null

    [ -f "$PROXY_SCRIPT" ] && "$PROXY_SCRIPT" --clean 2>/dev/null

    remove_immutable_recursive "$AGH_DIR"
    remove_immutable_recursive "$AGH_MODULE_DIR"

    [ -d "/data/adb/agh" ] && rm -rf "/data/adb/agh"

    info "- 🌳 Old AdGuardHome for Root has been cleaned up" "- 🌳 已清理旧版AdGuardHome for Root"
fi

if [ -d "$AGH_MODULE_DIR" ]; then
    info "- 🌳 Removing immutable attributes from module directory..." "- 🌳 正在解除模块目录的不可变属性..."
    remove_immutable_recursive "$AGH_MODULE_DIR"
fi

info "- 🌳 Installing AdGuardHome..." "- 🌳 开始安装 AdGuardHome..."

BIN_DIR="$AGH_DIR/bin"
SCRIPT_DIR="$AGH_DIR/scripts"
BOX_MODULE_DIR="/data/adb/modules/box_for_root"
BOX_CONFIG_DIR="/data/adb/box"

if [ -d "$AGH_DIR" ]; then
    info "- 🌳 Removing old AdGuardHome directory..." "- 🌳 正在删除旧版 AdGuardHome 目录..."

    mkdir -p "$BACKUP_DIR"

    backup_user_rules_block

    pkill -9 AdGuardHome 2>/dev/null
    pkill -9 inotifyd 2>/dev/null
    sleep 1

    remove_immutable_recursive "$AGH_DIR"

    if [ -f "$AGH_DIR/bin/data/querylog.json" ]; then
        mv "$AGH_DIR/bin/data/querylog.json" "$BACKUP_DIR/querylog.json.bak"
        info "- 🌳 Backed up querylog.json" "- 🌳 已备份 querylog.json"
    fi

    rm -rf "$AGH_DIR"

    if [ -d "$AGH_DIR" ]; then
        error "- 🪵 Failed to remove old directory!" "- 🪵 删除旧目录失败！"
    fi

    info "- 🌳 Old directory removed successfully" "- 🌳 旧目录已成功删除"
fi

BOX_MODULE_EXISTS=false
if [ -d "$BOX_MODULE_DIR" ]; then
    BOX_MODULE_EXISTS=true
fi

if [ "$BOX_MODULE_EXISTS" = true ]; then
    warn "- 🪵 Detected box_for_root module!" "- 🪵 检测到 box for root 透明代理模块！"
    warn "- 🪵 Note: Transparent proxy detection currently only supports box for root" "- 🪵 提示：检测透明代理模块检测暂时只支持 box for root"
    warn "- 🪵 This module provides built-in box configs to replace your current setup." "- 🪵 本模块提供内置的 box 配置以替换你当前的 box 配置。"
    warn "- 🪵 If you want to keep your current config, choose 'Keep'." "- 🪵 如果你想保留当前配置，请选择'保留'。"
    warn "- 🪵 If you want to use this module's optimized config, choose 'Replace'." "- 🪵 如果你想使用适配本模块的配置，请选择'替换'。"
    warn "- 🪵 (Volume Up = Replace, Volume Down = Keep, 10s no input = Keep)" "- 🪵 （音量上键 = 替换, 音量下键 = 保留，10秒无操作 = 保留）"

    START_TIME_REPLACE=$(date +%s)
    while true; do
        NOW_TIME_REPLACE=$(date +%s)
        timeout 1 getevent -lc 1 2>&1 | grep KEY_VOLUME >"$TMPDIR/events_replace"
        if [ $((NOW_TIME_REPLACE - START_TIME_REPLACE)) -gt 9 ]; then
            warn "- 🪵No input, keep the existing box for root configuration" "- 🪵 无输入，保留现有的 box for root 配置"
            REPLACE_BOX=false
            break
        elif $(cat $TMPDIR/events_replace | grep -q KEY_VOLUMEUP); then
            warn "- 🪵 The user chooses to replace the box for root configuration" "- 🪵 用户选择替换 box for root 配置"
            REPLACE_BOX=true
            break
        elif $(cat $TMPDIR/events_replace | grep -q KEY_VOLUMEDOWN); then
            warn "- 🪵 The user chooses to replace the box_for_root configuration" "- 🪵 用户选择保留 box for root 配置"
            REPLACE_BOX=false
            break
        fi
    done

    if [ "$REPLACE_BOX" = true ]; then
        info "- 🌳 Replacing box for root configurations..." "- 🌳 正在替换 box for root 配置..."

        if [ -f "$BOX_CONFIG_DIR/mihomo/config.yaml" ]; then
            mv "$BOX_CONFIG_DIR/mihomo/config.yaml" "$BOX_CONFIG_DIR/mihomo/config.yaml.bak"
            info "- 🌳 Backed up mihomo/config.yaml" "- 🌳 已备份 mihomo/config.yaml"
        fi

        if [ -f "$BOX_CONFIG_DIR/sing-box/config.json" ]; then
            mv "$BOX_CONFIG_DIR/sing-box/config.json" "$BOX_CONFIG_DIR/sing-box/config.json.bak"
            info "- 🌳 Backed up sing-box/config.json" "- 🌳 已备份 sing-box/config.json"
        fi

        MIHOMO_EXTRACTED=false
        SINGBOX_EXTRACTED=false

        unzip -o "$ZIPFILE" "box/mihomo/config.yaml" -d "$TMPDIR" >/dev/null 2>&1 && {
            mkdir -p "$BOX_CONFIG_DIR/mihomo"
            mv "$TMPDIR/box/mihomo/config.yaml" "$BOX_CONFIG_DIR/mihomo/config.yaml"
            info "- 🌳 Extracted mihomo/config.yaml" "- 🌳 已解压 mihomo/config.yaml"
            MIHOMO_EXTRACTED=true
        } || {
            warn "- 🪵 mihomo/config.yaml not found in module" "- 🪵 模块中未找到 mihomo/config.yaml"
        }

        unzip -o "$ZIPFILE" "box/sing-box/config.json" -d "$TMPDIR" >/dev/null 2>&1 && {
            mkdir -p "$BOX_CONFIG_DIR/sing-box"
            mv "$TMPDIR/box/sing-box/config.json" "$BOX_CONFIG_DIR/sing-box/config.json"
            info "- 🌳 Extracted sing-box/config.json" "- 🌳 已解压 sing-box/config.json"
            SINGBOX_EXTRACTED=true
        } || {
            warn "- 🪵 sing-box/config.json not found in module" "- 🪵 模块中未找到 sing-box/config.json"
        }

        mkdir -p "$AGH_MODULE_DIR"
        echo "X7kL9pQ2rM5vN3jH8fD1" > "$AGH_MODULE_DIR/Validation"
        info "- 🌳 Created validation file in $AGH_MODULE_DIR/Validation" "- 🌳 已在 $AGH_MODULE_DIR/Validation 创建验证文件"

        if [ "$MIHOMO_EXTRACTED" = true ] || [ "$SINGBOX_EXTRACTED" = true ]; then
            warn "- 🪵 =========================================" "- 🪵 ========================================="
            warn "- 🪵 IMPORTANT: Please modify subscription URL!" "- 🪵 重要提示：请修改订阅链接！"
            warn "- 🪵 Currently only supports: mihomo, sing-box" "- 🪵 暂时只支持：mihomo、sing-box"
            warn "- 🪵 Edit the following files to add your subscription:" "- 🪵 请编辑以下文件添加你的订阅链接："

            if [ "$MIHOMO_EXTRACTED" = true ]; then
                warn "- 🪵   $BOX_CONFIG_DIR/mihomo/config.yaml" "- 🪵   $BOX_CONFIG_DIR/mihomo/config.yaml"
            fi
            if [ "$SINGBOX_EXTRACTED" = true ]; then
                warn "- 🪵   $BOX_CONFIG_DIR/sing-box/config.json" "- 🪵   $BOX_CONFIG_DIR/sing-box/config.json"
            fi

            warn "- 🪵 =========================================" "- 🪵 ========================================="

            warn "- 🪵 (Press Volume Down to continue, 3s no input = auto continue)" "- 🪵 （按音量减键继续，3秒无操作自动继续）"
            START_TIME_CONFIRM=$(date +%s)
            while true; do
                NOW_TIME_CONFIRM=$(date +%s)
                if [ $((NOW_TIME_CONFIRM - START_TIME_CONFIRM)) -gt 2 ]; then
                    break
                fi
                timeout 1 getevent -lc 1 2>&1 | grep KEY_VOLUME >"$TMPDIR/events_confirm"
                if $(cat $TMPDIR/events_confirm | grep -q KEY_VOLUMEDOWN); then
                    break
                fi
            done
        else
            warn "- 🪵 No configuration files extracted!" "- 🪵 未解压到任何配置文件！"
            warn "- 🪵 Please check if box/mihomo/config.yaml or box/sing-box/config.json exists in module." "- 🪵 请检查模块中是否存在 box/mihomo/config.yaml 或 box/sing-box/config.json"
        fi
    fi
fi

info "- 🌳 Extracting module basic files..." "- 🌳 解压模块基本文件..."
unzip -o "$ZIPFILE" "action.sh" -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" "module.prop" -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" "service.sh" -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" "uninstall.sh" -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" "webroot/*" -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" "box/*" -d "$MODPATH" >/dev/null 2>&1

disable_iptables_in_conf() {
    local conf_file="$1"
    if [ -f "$conf_file" ]; then
        info "- 🌳 Auto-disabling iptables in settings.conf..." "- 🌳 自动禁用 settings.conf 中的 iptables..."

        sed -i 's/^[#[:space:]]*enable_iptables=.*/enable_iptables=false/' "$conf_file"

        if ! grep -q "^enable_iptables=false" "$conf_file"; then
            if grep -q "enable_iptables" "$conf_file"; then
                sed -i 's/^enable_iptables.*/enable_iptables=false/' "$conf_file"
            else
                sed -i '1i enable_iptables=false' "$conf_file"
            fi
        fi
        info "- 🌳 iptables disabled to avoid conflict with box." "- 🌳 已禁用 iptables 以避免与 box 冲突。"
    fi
}

info "- 🌳 Creating directories..." "- 🌳 创建目录..."
mkdir -p "$AGH_DIR" "$BIN_DIR" "$SCRIPT_DIR"

mkdir -p "$AGH_DIR/bin/data"
if [ -f "$BACKUP_DIR/querylog.json.bak" ]; then
    mv "$BACKUP_DIR/querylog.json.bak" "$AGH_DIR/bin/data/querylog.json"
    info "- 🌳 Restored querylog.json" "- 🌳 已恢复 querylog.json"
fi

info "- 🌳 Extracting files..." "- 🌳 正在解压文件..."

info "- 🌳 Extracting script files..." "- 🌳 正在解压脚本文件..."
unzip -o "$ZIPFILE" "scripts/*" -d $AGH_DIR >/dev/null 2>&1 || {
    error "- 🪵 Failed to extract scripts" "- 🪵 解压脚本文件失败"
}

info "- 🌳 Extracting binary files..." "- 🌳 正在解压二进制文件..."
unzip -o "$ZIPFILE" "bin/*" -d $AGH_DIR >/dev/null 2>&1 || {
    error "- 🪵 Failed to extract binary files" "- 🪵 解压二进制文件失败"
}

info "- 🌳 Extracting configuration files..." "- 🌳 正在解压配置文件..."
unzip -o "$ZIPFILE" "settings.conf" -d $AGH_DIR >/dev/null 2>&1 || {
    error "- 🪵 Failed to extract configuration files" "- 🪵 解压配置文件失败"
}

if [ -d "$BOX_CONFIG_DIR" ]; then
    disable_iptables_in_conf "$AGH_DIR/settings.conf"
fi

restore_user_rules_block

info "- 🌳 Setting permissions..." "- 🌳 设置权限..."

chmod +x "$BIN_DIR/AdGuardHome"
chown root:net_raw "$BIN_DIR/AdGuardHome"

chmod +x "$SCRIPT_DIR"/*.sh "$MODPATH"/*.sh

info "- 🌳 Installation completed, please reboot." "- 🌳 安装完成，请重启设备。"
am start -d "coolmarket://u/37906923" >/dev/null 2>&1 &