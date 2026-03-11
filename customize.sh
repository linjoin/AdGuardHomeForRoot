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

info "- 🌳 Installing AdGuardHome for $ARCH" "- 🌳 开始安装 AdGuardHome for $ARCH"

AGH_DIR="/data/adb/agh"
BIN_DIR="$AGH_DIR/bin"
SCRIPT_DIR="$AGH_DIR/scripts"
PID_FILE="$AGH_DIR/bin/agh.pid"
BOX_MODULE_DIR="/data/adb/modules/box_for_root"
BOX_CONFIG_DIR="/data/adb/box"
AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"

BOX_MODULE_EXISTS=false
if [ -d "$BOX_MODULE_DIR" ]; then
  BOX_MODULE_EXISTS=true
fi

if [ "$BOX_MODULE_EXISTS" = true ]; then
  warn "- 🪵 Detected box_for_root module!" "- 🪵 检测到 box_for_root 透明代理模块！"
  warn "- 🪵 Note: Transparent proxy detection currently only supports box for root" "- 🪵 提示：检测透明代理模块暂时只支持 box for root"
  warn "- 🪵 This module provides built-in box configs to replace your current setup." "- 🪵 本模块提供内置的 box 配置以替换你当前的设置。"
  warn "- 🪵 If you want to keep your current config, choose 'Keep'." "- 🪵 如果你想保留当前配置，请选择'保留'。"
  warn "- 🪵 If you want to use this module's optimized config, choose 'Replace'." "- 🪵 如果你想使用本模块优化的配置，请选择'替换'。"
  warn "- 🪵 (Volume Up = Replace, Volume Down = Keep, 10s no input = Keep)" "- 🪵 （音量上键 = 替换, 音量下键 = 保留，10秒无操作 = 保留）"
  
  START_TIME_REPLACE=$(date +%s)
  while true; do
    NOW_TIME_REPLACE=$(date +%s)
    timeout 1 getevent -lc 1 2>&1 | grep KEY_VOLUME >"$TMPDIR/events_replace"
    if [ $((NOW_TIME_REPLACE - START_TIME_REPLACE)) -gt 9 ]; then
      warn "- 🪵 No input detected, keeping existing box_for_root..." "- 🪵 无输入，保留现有的 box_for_root..."
      REPLACE_BOX=false
      break
    elif $(cat $TMPDIR/events_replace | grep -q KEY_VOLUMEUP); then
      warn "- 🪵 User chose to replace box_for_root..." "- 🪵 用户选择替换 box_for_root..."
      REPLACE_BOX=true
      break
    elif $(cat $TMPDIR/events_replace | grep -q KEY_VOLUMEDOWN); then
      warn "- 🪵 User chose to keep box_for_root..." "- 🪵 用户选择保留 box_for_root..."
      REPLACE_BOX=false
      break
    fi
  done
  
  if [ "$REPLACE_BOX" = true ]; then
    info "- 🌳 Replacing box_for_root configurations..." "- 🌳 正在替换 box_for_root 配置..."
    
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
      
      warn "- 🪵 (Press Volume Up to continue after reading)" "- 🪵 （阅读完毕后按音量上键继续）"
      while true; do
        timeout 1 getevent -lc 1 2>&1 | grep KEY_VOLUME >"$TMPDIR/events_confirm"
        if $(cat $TMPDIR/events_confirm | grep -q KEY_VOLUMEUP); then
          break
        elif $(cat $TMPDIR/events_confirm | grep -q KEY_VOLUMEDOWN); then
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

extract_keep_config() {
  info "- 🌳 Keeping old configuration files..." "- 🌳 保留原来的配置文件..."
  
  
  if [ -d "$BOX_CONFIG_DIR" ] && [ -f "$AGH_DIR/settings.conf" ]; then
    if grep -q '^enable_iptables=true' "$AGH_DIR/settings.conf"; then
      warn "- 🪵 Warning: Old config has enable_iptables=true!" "- 🪵 警告：旧配置启用了 iptables！"
      warn "- 🪵 Please manually change to false to avoid conflict with box." "- 🪵 请手动修改为 false 以避免与 box 冲突。"
    fi
  fi
  
  info "- 🌳 Extracting script files..." "- 🌳 正在解压脚本文件..."
  unzip -o "$ZIPFILE" "scripts/*" -d $AGH_DIR >/dev/null 2>&1 || {
    error "- 🪵 Failed to extract scripts!" "- 🪵 解压脚本文件失败！"
  }
  info "- 🌳 Extracting binary files except configuration..." "- 🌳 正在解压二进制文件（不包括配置文件）..."
  unzip -o "$ZIPFILE" "bin/*" -x "bin/AdGuardHome.yaml" -d $AGH_DIR >/dev/null 2>&1 || {
    error "- 🪵 Failed to extract binary files!" "- 🪵 解压二进制文件失败！"
  }
  info "- 🌳 Skipping configuration file extraction..." "- 🌳 跳过解压配置文件..."
}

extract_no_config() {
  info "- 🌳 Backing up old configuration files with .bak extension..." "- 🌳 使用 .bak 扩展名备份旧配置文件..."
  [ -f "$AGH_DIR/settings.conf" ] && mv "$AGH_DIR/settings.conf" "$AGH_DIR/settings.conf.bak"
  [ -f "$AGH_DIR/bin/AdGuardHome.yaml" ] && mv "$AGH_DIR/bin/AdGuardHome.yaml" "$AGH_DIR/bin/AdGuardHome.yaml.bak"
  extract_all
}

extract_all() {
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
}

if [ -d "$AGH_DIR" ]; then
  info "- 🌳 Found old version, stopping all AdGuardHome processes..." "- 🌳 发现旧版模块，正在停止所有 AdGuardHome 进程..."
  pkill -f "AdGuardHome" || pkill -9 -f "AdGuardHome" 
  info "- 🌳 Do you want to keep the old configuration? (If not, it will be automatically backed up)" "- 🌳 是否保留原来的配置文件？（若不保留则自动备份）"
  info "- 🌳 (Volume Up = Yes, Volume Down = No, 30s no input = Yes)" "- 🌳 （音量上键 = 是, 音量下键 = 否，30秒无操作 = 是）"
  START_TIME=$(date +%s)
  while true; do
    NOW_TIME=$(date +%s)
    timeout 1 getevent -lc 1 2>&1 | grep KEY_VOLUME >"$TMPDIR/events"
    if [ $((NOW_TIME - START_TIME)) -gt 29 ]; then
      info "- 🌳 No input detected after 30 seconds, defaulting to keep old configuration." "- 🌳 30秒无输入，默认保留原配置。"
      extract_keep_config
      break
    elif $(cat $TMPDIR/events | grep -q KEY_VOLUMEUP); then
      extract_keep_config
      break
    elif $(cat $TMPDIR/events | grep -q KEY_VOLUMEDOWN); then
      extract_no_config
      break
    fi
  done
else
  info "- 🌳 First time installation, extracting files..." "- 🌳 第一次安装，正在解压文件..."
  mkdir -p "$AGH_DIR" "$BIN_DIR" "$SCRIPT_DIR"
  extract_all
fi

info "- 🌳 Setting permissions..." "- 🌳 设置权限..."

chmod +x "$BIN_DIR/AdGuardHome"
chown root:net_raw "$BIN_DIR/AdGuardHome"

chmod +x "$SCRIPT_DIR"/*.sh "$MODPATH"/*.sh

info "- 🌳 Installation completed, please reboot." "- 🌳 安装完成，请重启设备。"
