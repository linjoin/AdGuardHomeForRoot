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

TMP_BASE="${TMPDIR:-/data/local/tmp}/agh_verify_$$"
mkdir -p "$TMP_BASE"

cleanup_all() {
  rm -rf "$TMP_BASE"
  [ -n "$ORIGINAL_SELINUX" ] && [ "$ORIGINAL_SELINUX" = "Enforcing" ] && setenforce 1 2>/dev/null
}
trap cleanup_all EXIT

check_tools() {
  if ! command -v unzip >/dev/null 2>&1; then
    print "- 错误：缺少 unzip 工具" "- Error: Missing unzip tool"
    exit 1
  fi
}

jump_to_coolapk() {
  local pkg="com.coolapk.market"
  local user="37906923"
  if command -v pm >/dev/null 2>&1 && command -v am >/dev/null 2>&1 && command -v dumpsys >/dev/null 2>&1; then
    if pm list packages 2>/dev/null | grep -q "$pkg"; then
      local retry=0
      while [ $retry -lt 3 ]; do
        am start -d "coolmarket://u/$user" >/dev/null 2>&1
        sleep 1
        local current=$(dumpsys activity activities 2>/dev/null | grep -E "mResumedActivity|mFocusedWindow" | grep -o "$pkg" | head -1)
        [ "$current" = "$pkg" ] && break
        retry=$((retry + 1))
        sleep 1
      done
    fi
  fi
  print "- 请手动访问：coolmarket://u/$user" "- Please visit manually: coolmarket://u/$user"
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
  local file="$1"
  local tool="$2"
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
  print "- $1 校验失败" "- Verification failed for $1"
  print "- 模块可能被篡改，请从作者主页下载" "- Module may be modified. Please download from author page"
  jump_to_coolapk
  exit 1
}

verify_file() {
  local zip="$1"
  local file="$2"
  local tmpdir="$TMP_BASE/v_$$"
  mkdir -p "$tmpdir"

  unzip -o "$zip" "$file" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }
  unzip -o "$zip" "$file.sha256" -d "$tmpdir" >/dev/null 2>&1 || { rm -rf "$tmpdir"; return 1; }

  local tool=$(get_hash_tool)
  [ -z "$tool" ] && { rm -rf "$tmpdir"; return 1; }

  local expected=$(head -n 1 "$tmpdir/$file.sha256" | awk '{print $1}')
  local actual=$(calc_hash "$tmpdir/$file" "$tool")

  rm -rf "$tmpdir"
  [ "$expected" = "$actual" ] && [ -n "$expected" ]
}

ORIGINAL_SELINUX=""
NEED_SELINUX_SWITCH=false

if command -v getenforce >/dev/null 2>&1 && command -v setenforce >/dev/null 2>&1; then
  ORIGINAL_SELINUX=$(getenforce)
fi

switch_selinux() {
  if [ "$ORIGINAL_SELINUX" = "Enforcing" ] && [ "$NEED_SELINUX_SWITCH" = false ]; then
    setenforce 0
    NEED_SELINUX_SWITCH=true
  fi
}

check_tools

print "- 正在校验模块完整性" "- Verifying module integrity"

if ! verify_file "$ZIPFILE" "customize.sh"; then
  verify_fail "customize.sh"
fi
if ! verify_file "$ZIPFILE" "module.prop"; then
  verify_fail "module.prop"
fi
if ! verify_file "$ZIPFILE" "service.sh"; then
  verify_fail "service.sh"
fi

print "- 模块校验通过" "- Module verification passed"

if ! verify_file "$ZIPFILE" "AdGuardHome/AdGuardHomeForRoot_AutoOpt_arm64.zip"; then
  verify_fail "arm64 package"
fi
if ! verify_file "$ZIPFILE" "AdGuardHome/AdGuardHomeForRoot_AutoOpt_armv7.zip"; then
  verify_fail "armv7 package"
fi

print "- 架构包校验完成" "- Architecture packages verified"

ARCH=$(getprop ro.product.cpu.abi)
case "$ARCH" in
  arm64-v8a|aarch64) TARGET="arm64" ;;
  armeabi-v7a|armeabi) TARGET="armv7" ;;
  *) print "- 不支持的设备架构：$ARCH" "- Unsupported architecture: $ARCH"; exit 1 ;;
esac

print "- 设备架构：$TARGET" "- Detected architecture: $TARGET"

ARCHIVE="AdGuardHome/AdGuardHomeForRoot_AutoOpt_${TARGET}.zip"
mkdir -p "$MODPATH/AdGuardHome"
unzip -o "$ZIPFILE" "$ARCHIVE" -d "$MODPATH" >/dev/null 2>&1 || {
  print "- 文件解压失败" "- File extraction failed"
  exit 1
}

ZIP_PATH="$MODPATH/$ARCHIVE"
SUCCESS=false
METHOD=""

try_install_manager() {
  local name="$1"
  local bin="$2"
  local cmd="$3"

  [ -f "$bin" ] || return 1

  print "- 尝试使用 $name 安装" "- Trying $name installation"

  if eval "$cmd"; then
    METHOD="$name"
    SUCCESS=true
    return 0
  fi
  return 1
}

install_universal() {
  local agh_dir="/data/adb/modules/AdGuardHome"
  rm -rf "$agh_dir"
  mkdir -p "$agh_dir"

  switch_selinux

  print "- 正在解压模块文件" "- Extracting module files"
  unzip -o "$ZIP_PATH" -d "$agh_dir" || return 1

  touch "$agh_dir/enable"
  find "$agh_dir" -type d -exec chmod 755 {} \;
  find "$agh_dir" -type f -exec chmod 644 {} \;

  for s in customize.sh service.sh action.sh uninstall.sh post-fs-data.sh; do
    [ -f "$agh_dir/$s" ] && chmod 755 "$agh_dir/$s"
  done

  for b in "$agh_dir"/bin/* "$agh_dir"/AdGuardHome/bin/*; do
    [ -f "$b" ] && chmod 755 "$b"
  done 2>/dev/null

  if [ -f "$agh_dir/customize.sh" ]; then
    local subtmp="$TMP_BASE/sub_$$"
    mkdir -p "$subtmp"

    print "- 执行安装脚本" "- Executing installation script"

    (
      export MODPATH="$agh_dir"
      export ZIPFILE="$ZIP_PATH"
      export TMPDIR="$subtmp"
      export SKIPUNZIP=1

      ui_print() { echo "$1"; }
      abort() { echo "abort: $1"; exit 1; }

      cd "$agh_dir" || exit 1
      . ./customize.sh
    )

    local st=$?
    rm -rf "$subtmp"

    if [ $st -ne 0 ]; then
      rm -rf "$agh_dir"
      return 1
    fi
  fi

  METHOD="Universal"
  SUCCESS=true
  return 0
}

if [ -n "$KSU" ]; then
  try_install_manager "KernelSU" "/data/adb/ksud" "\"/data/adb/ksud\" module install \"$ZIP_PATH\"" || \
  try_install_manager "KernelSU" "/data/adb/ksu/bin/ksud" "\"/data/adb/ksu/bin/ksud\" module install \"$ZIP_PATH\""

  [ "$SUCCESS" = false ] && try_install_manager "Magisk" "/data/adb/magisk/magisk" "\"/data/adb/magisk/magisk\" --install-module \"$ZIP_PATH\"" || \
  try_install_manager "Magisk" "/system/bin/magisk" "\"/system/bin/magisk\" --install-module \"$ZIP_PATH\""

  [ "$SUCCESS" = false ] && try_install_manager "APatch" "/data/adb/apd" "\"/data/adb/apd\" module install \"$ZIP_PATH\"" || \
  try_install_manager "APatch" "/data/adb/ap/bin/apd" "\"/data/adb/ap/bin/apd\" module install \"$ZIP_PATH\""

elif [ -n "$APATCH" ]; then
  try_install_manager "APatch" "/data/adb/apd" "\"/data/adb/apd\" module install \"$ZIP_PATH\"" || \
  try_install_manager "APatch" "/data/adb/ap/bin/apd" "\"/data/adb/ap/bin/apd\" module install \"$ZIP_PATH\""

  [ "$SUCCESS" = false ] && try_install_manager "Magisk" "/data/adb/magisk/magisk" "\"/data/adb/magisk/magisk\" --install-module \"$ZIP_PATH\"" || \
  try_install_manager "Magisk" "/system/bin/magisk" "\"/system/bin/magisk\" --install-module \"$ZIP_PATH\""

  [ "$SUCCESS" = false ] && try_install_manager "KernelSU" "/data/adb/ksud" "\"/data/adb/ksud\" module install \"$ZIP_PATH\"" || \
  try_install_manager "KernelSU" "/data/adb/ksu/bin/ksud" "\"/data/adb/ksu/bin/ksud\" module install \"$ZIP_PATH\""

elif [ -n "$MAGISK_VER" ]; then
  try_install_manager "Magisk" "/data/adb/magisk/magisk" "\"/data/adb/magisk/magisk\" --install-module \"$ZIP_PATH\"" || \
  try_install_manager "Magisk" "/system/bin/magisk" "\"/system/bin/magisk\" --install-module \"$ZIP_PATH\""

  [ "$SUCCESS" = false ] && try_install_manager "KernelSU" "/data/adb/ksud" "\"/data/adb/ksud\" module install \"$ZIP_PATH\"" || \
  try_install_manager "KernelSU" "/data/adb/ksu/bin/ksud" "\"/data/adb/ksu/bin/ksud\" module install \"$ZIP_PATH\""

  [ "$SUCCESS" = false ] && try_install_manager "APatch" "/data/adb/apd" "\"/data/adb/apd\" module install \"$ZIP_PATH\"" || \
  try_install_manager "APatch" "/data/adb/ap/bin/apd" "\"/data/adb/ap/bin/apd\" module install \"$ZIP_PATH\""
fi

[ "$SUCCESS" = false ] && install_universal

rm -f "$ZIP_PATH"
rmdir "$MODPATH/AdGuardHome" 2>/dev/null

if [ "$SUCCESS" = true ]; then
  print "- 安装成功，安装方式：$METHOD" "- Installation completed. Method: $METHOD"
else
  print "- 安装失败" "- Installation failed"
  exit 1
fi
