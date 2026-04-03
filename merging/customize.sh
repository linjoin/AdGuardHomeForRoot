#!/system/bin/sh

UI_LANG=$(getprop persist.sys.locale 2>/dev/null)
[ -z "$UI_LANG" ] && UI_LANG=$(getprop ro.product.locale 2>/dev/null)
[ -z "$UI_LANG" ] && UI_LANG=$(getprop ro.product.locale.language 2>/dev/null)
[ -z "$UI_LANG" ] && UI_LANG=$(getprop ro.product.locale.region 2>/dev/null)
[ -z "$UI_LANG" ] && UI_LANG=$(getprop persist.sys.language 2>/dev/null)
[ -z "$UI_LANG" ] && UI_LANG="en-US"

case "$UI_LANG" in
  zh*|ZH*|CN*|cn*) UI_LANG="zh" ;;
  *) UI_LANG="en" ;;
esac

print() {
  if [ "$UI_LANG" = "zh" ]; then
    ui_print "$1"
  else
    ui_print "$2"
  fi
}

restore_selinux() {
  if [ -n "$_ORIGINAL_SELINUX" ] && [ "$_ORIGINAL_SELINUX" = "Enforcing" ]; then
    print "🌳 喵~ 正在恢复 SELinux 哦nya~" "🌳 Restoring SELinux to enforcing mode nya~"
    setenforce 1 2>/dev/null
  fi
}

jump_to_coolapk() {
  KUAN_PKG="com.coolapk.market"
  KUAN_USER="37906923"
  if command -v pm >/dev/null 2>&1 && command -v am >/dev/null 2>&1 && command -v dumpsys >/dev/null 2>&1; then
    if pm list packages 2>/dev/null | grep -q "$KUAN_PKG"; then
      RETRY_COUNT=0
      MAX_RETRY=3
      while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
        am start -d "coolmarket://u/$KUAN_USER" >/dev/null 2>&1
        sleep 1
        CURRENT_PKG=$(dumpsys activity activities 2>/dev/null | grep -E "mResumedActivity|mFocusedWindow" | grep -o "$KUAN_PKG" | head -1)
        if [ "$CURRENT_PKG" = "$KUAN_PKG" ]; then
          break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 1
      done
      if [ $RETRY_COUNT -eq $MAX_RETRY ]; then
        print "🪵 呜…打不开酷安啦 重试失败nya~" "🪵 Failed to open CoolApk after $MAX_RETRY attempts nya~"
        print "🪵 请手动访问哦：coolmarket://u/$KUAN_USER" "🪵 Please visit manually nya~: coolmarket://u/$KUAN_USER"
      fi
    else
      print "🪵 没有检测到酷安呢nya~" "🪵 CoolApk not installed nya~, please visit: coolmarket://u/$KUAN_USER"
    fi
  else
    print "🪵 请手动访问哦：coolmarket://u/$KUAN_USER" "🪵 Please visit manually nya~: coolmarket://u/$KUAN_USER"
  fi
}

get_hash_tool() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v toybox >/dev/null 2>&1 && toybox sha256sum /dev/null >/dev/null 2>&1; then
    echo "toybox sha256sum"
  elif command -v busybox >/dev/null 2>&1 && busybox sha256sum /dev/null >/dev/null 2>&1; then
    echo "busybox sha256sum"
  elif command -v sha256 >/dev/null 2>&1; then
    echo "sha256"
  elif command -v openssl >/dev/null 2>&1; then
    echo "openssl"
  else
    echo ""
  fi
}

calc_hash() {
  file="$1"
  tool="$2"
  case "$tool" in
    sha256sum) sha256sum "$file" | awk '{print $1}' ;;
    "toybox sha256sum") toybox sha256sum "$file" | awk '{print $1}' ;;
    "busybox sha256sum") busybox sha256sum "$file" | awk '{print $1}' ;;
    sha256) sha256 -q "$file" 2>/dev/null || sha256 "$file" | awk '{print $NF}' ;;
    openssl) openssl dgst -sha256 "$file" | awk '{print $NF}' ;;
    *) echo "" ;;
  esac
}

verify_fail() {
  failed_file="$1"
  print "🪵 模块校验失败啦nya~" "🪵 Module verification failed nya~"
  ui_print ""
  print "🪵 $failed_file 校验异常nya~" "🪵 Warning: $failed_file verification failed nya~"
  print "🪵 模块好像被修改了哦nya~" "🪵 Module may have been modified nya~, please download from author-chan"
  ui_print ""
  print "🪵 正在跳转到作者主页nya~" "🪵 Jumping to author-chan's homepage nya~"
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "🪵 安装停止啦nya~" "🪵 Installation terminated nya~"
  abort ""
}

verify_file() {
  zipfile="$1"
  file="$2"
  hashfile="$file.sha256"
  tmpdir="${TMPDIR:-/data/local/tmp}/verify_$$"
  mkdir -p "$tmpdir"
  unzip -o "$zipfile" "$file" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }
  unzip -o "$zipfile" "$hashfile" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }
  file_path="$tmpdir/$file"
  hash_path="$tmpdir/$hashfile"
  [ -f "$file_path" ] || { rm -rf "$tmpdir"; return 1; }
  [ -f "$hash_path" ] || { rm -rf "$tmpdir"; return 1; }
  
  HASH_TOOL=$(get_hash_tool)
  [ -z "$HASH_TOOL" ] && { rm -rf "$tmpdir"; return 1; }
  
  expected=$(head -n 1 "$hash_path" | awk '{print $1}')
  actual=$(calc_hash "$file_path" "$HASH_TOOL")
  
  if [ "$expected" = "$actual" ] && [ -n "$expected" ]; then
    rm -rf "$tmpdir"
    return 0
  else
    rm -rf "$tmpdir"
    return 1
  fi
}

_ORIGINAL_SELINUX=""
NEED_SELINUX_SWITCH=false

if command -v getenforce >/dev/null 2>&1 && command -v setenforce >/dev/null 2>&1; then
  _ORIGINAL_SELINUX=$(getenforce)
fi

switch_selinux() {
  if [ "$_ORIGINAL_SELINUX" = "Enforcing" ]; then
    if [ "$NEED_SELINUX_SWITCH" = false ]; then
      print "🌳 喵~ 暂时调整一下 SELinux 哦nya~" "🌳 Temporarily setting SELinux to permissive mode nya~"
      setenforce 0
      NEED_SELINUX_SWITCH=true
    fi
  fi
}

trap 'restore_selinux' EXIT

print "🌳 喵呜~ 正在校验模块完整性nya~" "🌳 Verifying module integrity nya~"

OUTER_ZIPFILE="$ZIPFILE"

if ! verify_file "$OUTER_ZIPFILE" "customize.sh"; then
  verify_fail "customize.sh"
fi

if ! verify_file "$OUTER_ZIPFILE" "module.prop"; then
  verify_fail "module.prop"
fi

if ! verify_file "$OUTER_ZIPFILE" "service.sh"; then
  verify_fail "service.sh"
fi

if ! verify_file "$OUTER_ZIPFILE" "verify.sh"; then
  verify_fail "verify.sh"
fi

print "🌳 模块校验通过啦 太棒了nya~" "🌳 Module verification passed nya~, wonderful~"
ui_print ""

print "🌳 喵~ 正在校验架构包nya~" "🌳 Verifying architecture package integrity nya~"

if ! verify_file "$OUTER_ZIPFILE" "AdGuardHome/AdGuardHomeForRoot_AutoOpt_arm64.zip"; then
  print "🪵 架构包校验失败啦nya~" "🪵 Architecture package verification failed nya~"
  ui_print ""
  print "🪵 arm64 包校验异常nya~" "🪵 Warning: arm64 package verification failed nya~"
  print "🪵 模块好像被修改了哦nya~" "🪵 Module may have been modified nya~, please download from author-chan"
  ui_print ""
  print "🪵 正在跳转到作者主页nya~" "🪵 Jumping to author-chan's homepage nya~"
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "🪵 安装停止啦nya~" "🪵 Installation terminated nya~"
  abort ""
fi

if ! verify_file "$OUTER_ZIPFILE" "AdGuardHome/AdGuardHomeForRoot_AutoOpt_armv7.zip"; then
  print "🪵 架构包校验失败啦nya~" "🪵 Architecture package verification failed nya~"
  ui_print ""
  print "🪵 armv7 包校验异常nya~" "🪵 Warning: armv7 package verification failed nya~"
  print "🪵 模块好像被修改了哦nya~" "🪵 Module may have been modified nya~, please download from author-chan"
  ui_print ""
  print "🪵 正在跳转到作者主页nya~" "🪵 Jumping to author-chan's homepage nya~"
  sleep 3
  jump_to_coolapk
  restore_selinux
  print "🪵 安装停止啦nya~" "🪵 Installation terminated nya~"
  abort ""
fi

print "🌳 架构包校验通过啦nya~" "🌳 Architecture package verification passed nya~"
ui_print ""

DEVICE_ARCH=$(getprop ro.product.cpu.abi)
case "$DEVICE_ARCH" in
  arm64-v8a|aarch64) TARGET_ARCH="arm64" ;;
  armeabi-v7a|armeabi) TARGET_ARCH="armv7" ;;
  *) restore_selinux; print "🪵 不支持的设备架构哦 $DEVICE_ARCH nya~" "🪵 Unsupported architecture nya~: $DEVICE_ARCH"; abort "" ;;
esac
print "🌳 已识别设备架构 $DEVICE_ARCH nya~" "🌳 Detected architecture nya~: $DEVICE_ARCH (using: $TARGET_ARCH)"

ARCHIVE="AdGuardHome/AdGuardHomeForRoot_AutoOpt_${TARGET_ARCH}.zip"
ARCHIVE_NAME="AdGuardHomeForRoot_AutoOpt_${TARGET_ARCH}.zip"
print "🌳 喵~ 正在解压文件nya~" "🌳 Extracting nya~: $ARCHIVE"

mkdir -p "$MODPATH/AdGuardHome"
unzip -o "$OUTER_ZIPFILE" "$ARCHIVE" -d "$MODPATH" >/dev/null 2>&1 || { restore_selinux; print "🪵 文件解压失败啦nya~" "🪵 Extraction failed nya~: $ARCHIVE"; abort ""; }

ZIP_PATH="$MODPATH/$ARCHIVE"

print "🌳 开始安装咯nya~~" "🌳 Installing nya~~ $ARCHIVE_NAME"

INSTALL_SUCCESS=false
INSTALL_METHOD=""

if [ -n "$KSU" ]; then
  CURRENT_ENV="KSU"
elif [ -n "$APATCH" ]; then
  CURRENT_ENV="APATCH"
elif [ -n "$MAGISK_VER" ]; then
  CURRENT_ENV="MAGISK"
else
  CURRENT_ENV=""
fi

if [ "$CURRENT_ENV" = "KSU" ]; then
  print "🌳 检测到 KernelSU 环境啦nya~" "🌳 KernelSU environment detected nya~"
  KSUD_PATH="/data/adb/ksud"
  [ -f "/data/adb/ksu/bin/ksud" ] && KSUD_PATH="/data/adb/ksu/bin/ksud"
  if [ -f "$KSUD_PATH" ] && "$KSUD_PATH" module install "$ZIP_PATH"; then
    INSTALL_SUCCESS=true
    INSTALL_METHOD="KernelSU"
  else
    print "🪵 KernelSU 安装失败nya~ 正在尝试其他管理器nya~" "🪵 KernelSU installation failed nya~, trying other managers nya~"
  fi
  
  if [ "$INSTALL_SUCCESS" = false ]; then
    if [ -f "/data/adb/magisk/magisk" ] || [ -f "/system/bin/magisk" ]; then
      print "🌳 尝试 Magisk 安装nya~" "🌳 Trying Magisk installation nya~"
      MAGISK_BIN="/data/adb/magisk/magisk"
      [ -f "/system/bin/magisk" ] && MAGISK_BIN="/system/bin/magisk"
      if [ -f "$MAGISK_BIN" ] && "$MAGISK_BIN" --install-module "$ZIP_PATH"; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="Magisk (fallback)"
      else
        print "🪵 Magisk 也失败nya~ 再试试 APatchnya~" "🪵 Magisk also failed nya~, trying APatch nya~"
      fi
    fi
  fi
  
  if [ "$INSTALL_SUCCESS" = false ]; then
    if [ -f "/data/adb/apd" ] || [ -f "/data/adb/ap/bin/apd" ]; then
      print "🌳 尝试 APatch 安装nya~" "🌳 Trying APatch installation nya~"
      APD_PATH=""
      [ -f "/data/adb/ap/bin/apd" ] && APD_PATH="/data/adb/ap/bin/apd"
      [ -f "/data/adb/apd" ] && APD_PATH="/data/adb/apd"
      if [ -n "$APD_PATH" ] && "$APD_PATH" module install "$ZIP_PATH"; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="APatch (fallback)"
      else
        print "🪵 APatch 也失败nya~" "🪵 APatch also failed nya~"
      fi
    fi
  fi

elif [ "$CURRENT_ENV" = "APATCH" ]; then
  print "🌳 检测到 APatch 环境啦nya~" "🌳 APatch environment detected nya~"
  APD_PATH=""
  [ -f "/data/adb/ap/bin/apd" ] && APD_PATH="/data/adb/ap/bin/apd"
  [ -f "/data/adb/apd" ] && APD_PATH="/data/adb/apd"
  if [ -n "$APD_PATH" ] && "$APD_PATH" module install "$ZIP_PATH"; then
    INSTALL_SUCCESS=true
    INSTALL_METHOD="APatch"
  else
    print "🪵 APatch 安装失败nya~ 正在尝试其他管理器nya~" "🪵 APatch installation failed nya~, trying other managers nya~"
  fi
  
  if [ "$INSTALL_SUCCESS" = false ]; then
    if [ -f "/data/adb/magisk/magisk" ] || [ -f "/system/bin/magisk" ]; then
      print "🌳 尝试 Magisk 安装nya~" "🌳 Trying Magisk installation nya~"
      MAGISK_BIN="/data/adb/magisk/magisk"
      [ -f "/system/bin/magisk" ] && MAGISK_BIN="/system/bin/magisk"
      if [ -f "$MAGISK_BIN" ] && "$MAGISK_BIN" --install-module "$ZIP_PATH"; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="Magisk (fallback)"
      else
        print "🪵 Magisk 也失败nya~ 再试试 KernelSUnya~" "🪵 Magisk also failed nya~, trying KernelSU nya~"
      fi
    fi
  fi
  
  if [ "$INSTALL_SUCCESS" = false ]; then
    if [ -f "/data/adb/ksud" ] || [ -f "/data/adb/ksu/bin/ksud" ]; then
      print "🌳 尝试 KernelSU 安装nya~" "🌳 Trying KernelSU installation nya~"
      KSUD_PATH="/data/adb/ksud"
      [ -f "/data/adb/ksu/bin/ksud" ] && KSUD_PATH="/data/adb/ksu/bin/ksud"
      if [ -f "$KSUD_PATH" ] && "$KSUD_PATH" module install "$ZIP_PATH"; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="KernelSU (fallback)"
      else
        print "🪵 KernelSU 也失败nya~" "🪵 KernelSU also failed nya~"
      fi
    fi
  fi

elif [ "$CURRENT_ENV" = "MAGISK" ]; then
  print "🌳 检测到 Magisk 环境啦nya~" "🌳 Magisk environment detected nya~"
  MAGISK_BIN="/data/adb/magisk/magisk"
  [ -f "/system/bin/magisk" ] && MAGISK_BIN="/system/bin/magisk"
  if [ -f "$MAGISK_BIN" ] && "$MAGISK_BIN" --install-module "$ZIP_PATH"; then
    INSTALL_SUCCESS=true
    INSTALL_METHOD="Magisk"
  else
    print "🪵 Magisk 安装失败nya~ 正在尝试其他管理器nya~" "🪵 Magisk installation failed nya~, trying other managers nya~"
  fi
  
  if [ "$INSTALL_SUCCESS" = false ]; then
    if [ -f "/data/adb/ksud" ] || [ -f "/data/adb/ksu/bin/ksud" ]; then
      print "🌳 尝试 KernelSU 安装nya~" "🌳 Trying KernelSU installation nya~"
      KSUD_PATH="/data/adb/ksud"
      [ -f "/data/adb/ksu/bin/ksud" ] && KSUD_PATH="/data/adb/ksu/bin/ksud"
      if [ -f "$KSUD_PATH" ] && "$KSUD_PATH" module install "$ZIP_PATH"; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="KernelSU (fallback)"
      else
        print "🪵 KernelSU 也失败nya~ 再试试 APatchnya~" "🪵 KernelSU also failed nya~, trying APatch nya~"
      fi
    fi
  fi
  
  if [ "$INSTALL_SUCCESS" = false ]; then
    if [ -f "/data/adb/apd" ] || [ -f "/data/adb/ap/bin/apd" ]; then
      print "🌳 尝试 APatch 安装nya~" "🌳 Trying APatch installation nya~"
      APD_PATH=""
      [ -f "/data/adb/ap/bin/apd" ] && APD_PATH="/data/adb/ap/bin/apd"
      [ -f "/data/adb/apd" ] && APD_PATH="/data/adb/apd"
      if [ -n "$APD_PATH" ] && "$APD_PATH" module install "$ZIP_PATH"; then
        INSTALL_SUCCESS=true
        INSTALL_METHOD="APatch (fallback)"
      else
        print "🪵 APatch 也失败nya~" "🪵 APatch also failed nya~"
      fi
    fi
  fi
fi

if [ "$INSTALL_SUCCESS" = false ]; then
  print "🌳 所有管理器都失败nya~ 使用通用安装方式哦nya~" "🌳 All managers failed nya~, using universal installation method nya~"
  AGH_MODULE_DIR="/data/adb/modules/AdGuardHome"
  [ -d "$AGH_MODULE_DIR" ] && rm -rf "$AGH_MODULE_DIR"
  mkdir -p "$AGH_MODULE_DIR"
  
  switch_selinux
  unzip -o "$ZIP_PATH" -d "$AGH_MODULE_DIR" >/dev/null 2>&1
  UNZIP_STATUS=$?
  
  if [ $UNZIP_STATUS -ne 0 ]; then
    restore_selinux
    print "🪵 通用安装失败啦nya~" "🪵 Universal installation failed nya~: cannot extract module files"
    abort ""
  fi
  
  touch "$AGH_MODULE_DIR/enable"
  
  find "$AGH_MODULE_DIR" -type d -exec chmod 755 {} \;
  find "$AGH_MODULE_DIR" -type f -exec chmod 644 {} \;
  
  for script in customize.sh service.sh action.sh uninstall.sh post-fs-data.sh; do
    [ -f "$AGH_MODULE_DIR/$script" ] && chmod 755 "$AGH_MODULE_DIR/$script"
  done
  
  for bin in "$AGH_MODULE_DIR"/bin/* "$AGH_MODULE_DIR"/AdGuardHome/bin/*; do
    [ -f "$bin" ] && chmod 755 "$bin"
  done 2>/dev/null
  
  if [ -f "$AGH_MODULE_DIR/customize.sh" ]; then
    print "🌳 正在执行安装脚本nya~" "🌳 Executing module installation script nya~"
    SUB_TMPDIR="$TMPDIR/agh_sub_$$"
    mkdir -p "$SUB_TMPDIR"
    (
      export MODPATH="$AGH_MODULE_DIR"
      export ZIPFILE="$ZIP_PATH"
      export TMPDIR="$SUB_TMPDIR"
      ui_print_sub() { echo "ui_print $1" >&2; echo "$1"; }
      abort_sub() { echo "abort: $1" >&2; exit 1; }
      if ! command -v ui_print >/dev/null 2>&1; then ui_print() { ui_print_sub "$@"; }; fi
      if ! command -v abort >/dev/null 2>&1; then abort() { abort_sub "$@"; }; fi
      cd "$AGH_MODULE_DIR"
      . ./customize.sh
    )
    INSTALL_STATUS=$?
    rm -rf "$SUB_TMPDIR"
    if [ $INSTALL_STATUS -eq 0 ]; then
      print "🌳 脚本执行成功啦nya~" "🌳 Installation script executed successfully nya~"
      INSTALL_SUCCESS=true
    else
      print "🪵 脚本执行失败nya~" "🪵 Installation script failed nya~"
      rm -rf "$AGH_MODULE_DIR"
      restore_selinux
      print "🪵 安装停止啦nya~" "🪵 Installation terminated nya~ due to script failure"
      abort ""
    fi
  else
    INSTALL_SUCCESS=true
  fi
  
  if [ "$INSTALL_SUCCESS" = true ]; then
    INSTALL_METHOD="通用方案"
    print "🌳 通用安装完成咯nya~" "🌳 Universal installation completed nya~"
  fi
fi

if [ "$INSTALL_SUCCESS" = true ]; then
 print "🌳 $ARCHIVE_NAME 安装成功啦nya~" "🌳 $ARCHIVE_NAME installed successfully nya~"
 rm -f "$ZIP_PATH"
 rmdir "$MODPATH/AdGuardHome" 2>/dev/null
 print "🌳 本次是 $INSTALL_METHOD 方式帮主人装好的喵nya~~" "🌳 Installation method nya~~: $INSTALL_METHOD"
else
 print "🪵 所有安装方式都失败啦nya~" "🪵 $ARCHIVE_NAME installation failed nya~: all methods unavailable"
 abort ""
fi
