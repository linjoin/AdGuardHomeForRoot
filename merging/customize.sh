#!/system/bin/sh
MODID="adg_installation_module"

LANG=$(getprop persist.sys.locale 2>/dev/null || getprop ro.product.locale 2>/dev/null || echo "en-US")
case "$LANG" in
  zh*|ZH*|CN*|cn*) LANG="zh" ;;
  *) LANG="en" ;;
esac

print() {
  local zh_msg="$1"
  local en_msg="$2"
  if [ "$LANG" = "zh" ]; then
    ui_print "$zh_msg"
  else
    ui_print "$en_msg"
  fi
}

restore_selinux() {
  if [ -n "$_ORIGINAL_SELINUX" ] && [ "$_ORIGINAL_SELINUX" = "Enforcing" ]; then
    print "- 恢复 SELinux 为强制模式..." "- Restoring SELinux to enforcing mode..."
    setenforce 1 2>/dev/null
  fi
}

jump_to_coolapk() {
  KUAN_PKG="com.coolapk.market"
  KUAN_USER="37906923"
  if pm list packages | grep -q "$KUAN_PKG"; then
    RETRY_COUNT=0
    MAX_RETRY=3
    while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
      am start -d "coolmarket://u/$KUAN_USER" >/dev/null 2>&1
      sleep 1
      if pgrep -f "$KUAN_PKG" >/dev/null 2>&1; then
        break
      fi
      RETRY_COUNT=$((RETRY_COUNT + 1))
      sleep 1
    done
    if [ $RETRY_COUNT -eq $MAX_RETRY ]; then
      print "- 尝试 $MAX_RETRY 次后仍无法打开酷安" "- Failed to open CoolApk after $MAX_RETRY attempts"
      print "- 请手动访问: coolmarket://u/$KUAN_USER" "- Please visit manually: coolmarket://u/$KUAN_USER"
    fi
  else
    print "- 未安装酷安，请手动访问: coolmarket://u/$KUAN_USER" "- CoolApk not installed, please visit: coolmarket://u/$KUAN_USER"
  fi
}

verify_file() {
  local zipfile="$1"
  local file="$2"
  local hashfile="$file.sha256"
  local tmpdir="${TMPDIR:-/data/local/tmp}/verify_$$"
  mkdir -p "$tmpdir"
  unzip -o "$zipfile" "$file" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }
  unzip -o "$zipfile" "$hashfile" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }
  local file_path="$tmpdir/$file"
  local hash_path="$tmpdir/$hashfile"
  [ -f "$file_path" ] || { rm -rf "$tmpdir"; return 1; }
  [ -f "$hash_path" ] || { rm -rf "$tmpdir"; return 1; }
  local expected=$(head -n 1 "$hash_path" | awk '{print $1}')
  local actual=$(sha256sum "$file_path" | awk '{print $1}')
  if [ "$expected" = "$actual" ]; then
    rm -rf "$tmpdir"
    return 0
  else
    rm -rf "$tmpdir"
    return 1
  fi
}

_ORIGINAL_SELINUX=""
if command -v getenforce >/dev/null 2>&1 && command -v setenforce >/dev/null 2>&1; then
  _ORIGINAL_SELINUX=$(getenforce)
  if [ "$_ORIGINAL_SELINUX" = "Enforcing" ]; then
    print "- 临时设置 SELinux 为宽容模式..." "- Temporarily setting SELinux to permissive mode..."
    setenforce 0
  else
    print "- SELinux 已是宽容模式或未开启" "- SELinux is already permissive or disabled"
  fi
else
  print "- 无法获取 SELinux 状态，跳过设置" "- Cannot get SELinux status, skipping..."
fi

trap restore_selinux EXIT

print "- 正在校验本模块完整性..." "- Verifying this module integrity..."

OUTER_ZIPFILE="$ZIPFILE"

if ! verify_file "$OUTER_ZIPFILE" "customize.sh"; then
  print "- 正在校验本模块完整性: 不通过" "- Verifying this module integrity: FAILED"
  ui_print ""
  print "⚠️ 警告: customize.sh 校验失败" "⚠️ Warning: customize.sh verification failed"
  print "⚠️ 模块可能已被修改，请从作者发布的下载动态进行下载" "⚠️ Module may have been modified, please download from the author's release post"
  ui_print ""
  print "正在跳转至作者酷安主页..." "Jumping to author's CoolApk homepage..."
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "安装已终止" "Installation terminated"
  abort ""
fi

if ! verify_file "$OUTER_ZIPFILE" "module.prop"; then
  print "- 正在校验本模块完整性: 不通过" "- Verifying this module integrity: FAILED"
  ui_print ""
  print "⚠️ 警告: module.prop 校验失败" "⚠️ Warning: module.prop verification failed"
  print "⚠️ 模块可能已被修改，请从作者发布的下载动态进行下载" "⚠️ Module may have been modified, please download from the author's release post"
  ui_print ""
  print "正在跳转至作者酷安主页..." "Jumping to author's CoolApk homepage..."
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "安装已终止" "Installation terminated"
  abort ""
fi

if ! verify_file "$OUTER_ZIPFILE" "service.sh"; then
  print "- 正在校验本模块完整性: 不通过" "- Verifying this module integrity: FAILED"
  ui_print ""
  print "⚠️ 警告: service.sh 校验失败" "⚠️ Warning: service.sh verification failed"
  print "⚠️ 模块可能已被修改，请从作者发布的下载动态进行下载" "⚠️ Module may have been modified, please download from the author's release post"
  ui_print ""
  print "正在跳转至作者酷安主页..." "Jumping to author's CoolApk homepage..."
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "安装已终止" "Installation terminated"
  abort ""
fi

if ! verify_file "$OUTER_ZIPFILE" "verify.sh"; then
  print "- 正在校验本模块完整性: 不通过" "- Verifying this module integrity: FAILED"
  ui_print ""
  print "⚠️ 警告: verify.sh 校验失败" "⚠️ Warning: verify.sh verification failed"
  print "⚠️ 模块可能已被修改，请从作者发布的下载动态进行下载" "⚠️ Module may have been modified, please download from the author's release post"
  ui_print ""
  print "正在跳转至作者酷安主页..." "Jumping to author's CoolApk homepage..."
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "安装已终止" "Installation terminated"
  abort ""
fi

print "- 正在校验本模块完整性: 通过" "- Verifying this module integrity: PASSED"
ui_print ""

print "- 正在校验架构包完整性..." "- Verifying architecture package integrity..."

if ! verify_file "$OUTER_ZIPFILE" "AdGuardHome/AdGuardHomeForRoot_AutoOpt_arm64.zip"; then
  print "- 正在校验架构包完整性: 不通过" "- Verifying architecture package integrity: FAILED"
  ui_print ""
  print "⚠️ 警告: arm64 架构包校验失败" "⚠️ Warning: arm64 package verification failed"
  print "⚠️ 模块可能已被修改，请从作者发布的下载动态进行下载" "⚠️ Module may have been modified, please download from the author's release post"
  ui_print ""
  print "正在跳转至作者酷安主页..." "Jumping to author's CoolApk homepage..."
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "安装已终止" "Installation terminated"
  abort ""
fi

if ! verify_file "$OUTER_ZIPFILE" "AdGuardHome/AdGuardHomeForRoot_AutoOpt_armv7.zip"; then
  print "- 正在校验架构包完整性: 不通过" "- Verifying architecture package integrity: FAILED"
  ui_print ""
  print "⚠️ 警告: armv7 架构包校验失败" "⚠️ Warning: armv7 package verification failed"
  print "⚠️ 模块可能已被修改，请从作者发布的下载动态进行下载" "⚠️ Module may have been modified, please download from the author's release post"
  ui_print ""
  print "正在跳转至作者酷安主页..." "Jumping to author's CoolApk homepage..."
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "安装已终止" "Installation terminated"
  abort ""
fi

print "- 正在校验架构包完整性: 通过" "- Verifying architecture package integrity: PASSED"
ui_print ""

DEVICE_ARCH=$(getprop ro.product.cpu.abi)
case "$DEVICE_ARCH" in
  arm64-v8a|aarch64) TARGET_ARCH="arm64" ;;
  armeabi-v7a|armeabi) TARGET_ARCH="armv7" ;;
  *) restore_selinux; print "不支持的架构: $DEVICE_ARCH" "Unsupported architecture: $DEVICE_ARCH"; abort "" ;;
esac
print "- 检测到架构: $DEVICE_ARCH (使用: $TARGET_ARCH)" "- Detected architecture: $DEVICE_ARCH (using: $TARGET_ARCH)"

ARCHIVE="AdGuardHome/AdGuardHomeForRoot_AutoOpt_${TARGET_ARCH}.zip"
ARCHIVE_NAME="AdGuardHomeForRoot_AutoOpt_${TARGET_ARCH}.zip"
print "- 正在提取: $ARCHIVE" "- Extracting: $ARCHIVE"

mkdir -p "$MODPATH/AdGuardHome"
unzip -o "$OUTER_ZIPFILE" "$ARCHIVE" -d "$MODPATH" >/dev/null 2>&1 || { restore_selinux; print "提取失败: $ARCHIVE" "Extraction failed: $ARCHIVE"; abort ""; }

ZIP_PATH="$MODPATH/$ARCHIVE"

print "- 正在安装 $ARCHIVE_NAME ..." "- Installing $ARCHIVE_NAME ..."

INSTALL_SUCCESS=false
INSTALL_METHOD=""

if [ -n "$KSU" ] || [ -f "/data/adb/ksud" ] || [ -f "/data/adb/ksu/bin/ksud" ]; then
  print "- 已检测到 KernelSU 管理器或其衍生分支。" "- KernelSU manager or its derivative detected."
  KSUD_PATH="/data/adb/ksud"
  [ -f "/data/adb/ksu/bin/ksud" ] && KSUD_PATH="/data/adb/ksu/bin/ksud"
  if [ -f "$KSUD_PATH" ] && "$KSUD_PATH" module install "$ZIP_PATH"; then
    INSTALL_SUCCESS=true
    INSTALL_METHOD="KernelSU"
  else
    print "- KernelSU 安装失败，尝试其他方式..." "- KernelSU installation failed, trying other methods..."
  fi
fi

if [ "$INSTALL_SUCCESS" = false ]; then
  if [ -n "$APATCH" ] || [ -f "/data/adb/apd" ] || [ -f "/data/adb/ap/bin/apd" ]; then
    print "- 检测到 APatch 管理器或其衍生分支" "- APatch manager or its derivative detected"
    APD_PATH=""
    [ -f "/data/adb/ap/bin/apd" ] && APD_PATH="/data/adb/ap/bin/apd"
    [ -f "/data/adb/apd" ] && APD_PATH="/data/adb/apd"
    if [ -n "$APD_PATH" ] && "$APD_PATH" module install "$ZIP_PATH"; then
      INSTALL_SUCCESS=true
      INSTALL_METHOD="APatch"
    else
      print "- APatch 安装失败，尝试其他方式..." "- APatch installation failed, trying other methods..."
    fi
  fi
fi

if [ "$INSTALL_SUCCESS" = false ]; then
  if [ -n "$MAGISK_VER" ] || [ -f "/data/adb/magisk/magisk" ] || [ -f "/system/bin/magisk" ]; then
    print "- 检测到 Magisk 或其衍生分支" "- Magisk or its derivative detected"
    MAGISK_BIN="/data/adb/magisk/magisk"
    [ -f "/system/bin/magisk" ] && MAGISK_BIN="/system/bin/magisk"
    if [ -f "$MAGISK_BIN" ] && "$MAGISK_BIN" --install-module "$ZIP_PATH"; then
      INSTALL_SUCCESS=true
      INSTALL_METHOD="Magisk"
    else
      print "- Magisk 安装失败，尝试通用方式..." "- Magisk installation failed, trying universal method..."
    fi
  fi
fi

if [ "$INSTALL_SUCCESS" = false ]; then
  print "- 使用通用安装方式..." "- Using universal installation method..."
  AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
  [ -d "$AGH_MODULE_DIR" ] && rm -rf "$AGH_MODULE_DIR"
  mkdir -p "$AGH_MODULE_DIR"
  unzip -o "$ZIP_PATH" -d "$AGH_MODULE_DIR" >/dev/null 2>&1 || { restore_selinux; print "通用安装失败: 无法解压模块文件" "Universal installation failed: cannot extract module files"; abort ""; }
  touch "$AGH_MODULE_DIR/enable"
  chmod -R 755 "$AGH_MODULE_DIR"
  [ -d "$AGH_MODULE_DIR/system" ] && chmod -R 755 "$AGH_MODULE_DIR/system"
  if [ -f "$AGH_MODULE_DIR/customize.sh" ]; then
    print "- 执行模块安装脚本..." "- Executing module installation script..."
    SUB_TMPDIR="$TMPDIR/agh_sub_$$"
    mkdir -p "$SUB_TMPDIR"
    (
      export MODPATH="$AGH_MODULE_DIR"
      export ZIPFILE="$ZIP_PATH"
      export TMPDIR="$SUB_TMPDIR"
      ui_print_sub() { echo "ui_print $1" >&2; echo "$1"; }
      abort_sub() { echo "abort: $1" >&2; exit 1; }
      if ! type ui_print >/dev/null 2>&1; then ui_print() { ui_print_sub "$@"; }; fi
      if ! type abort >/dev/null 2>&1; then abort() { abort_sub "$@"; }; fi
      cd "$AGH_MODULE_DIR"
      . ./customize.sh
    )
    INSTALL_STATUS=$?
    rm -rf "$SUB_TMPDIR"
    if [ $INSTALL_STATUS -eq 0 ]; then
      print "- 安装脚本执行成功" "- Installation script executed successfully"
    else
      print "- 警告: 安装脚本执行失败(退出码: $INSTALL_STATUS)，但文件已解压" "- Warning: Installation script failed (exit code: $INSTALL_STATUS), but files extracted"
    fi
  fi
  INSTALL_SUCCESS=true
  INSTALL_METHOD="通用方案"
  print "- 通用安装完成" "- Universal installation completed"
fi

if [ "$INSTALL_SUCCESS" = true ]; then
  print "- $ARCHIVE_NAME 安装成功 (方式: $INSTALL_METHOD)" "- $ARCHIVE_NAME installed successfully (method: $INSTALL_METHOD)"
  rm -f "$ZIP_PATH"
  rmdir "$MODPATH/AdGuardHome" 2>/dev/null
  print "- 此安装器将自动移除" "- This installer will be automatically removed"
else
  print "$ARCHIVE_NAME 安装失败: 所有安装方式均不可用" "$ARCHIVE_NAME installation failed: all methods unavailable"
  abort ""
fi
