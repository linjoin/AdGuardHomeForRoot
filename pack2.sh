#!/bin/bash

# 定义下载 URL 和路径变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/cache"
MERGING_DIR="$SCRIPT_DIR/merging"

# 获取当前时间 (年月日时分)
TIMESTAMP=$(date +"%Y%m%d%H%M")

declare -A URL_WITH_CACHE_PATH=(
  ["https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_arm64.tar.gz"]="$CACHE_DIR/AdGuardHome_linux_arm64.tar.gz"
  ["https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_armv7.tar.gz"]="$CACHE_DIR/AdGuardHome_linux_armv7.tar.gz"
)

# 检查 merging 目录是否存在
if [ ! -d "$MERGING_DIR" ]; then
  echo "Error: merging directory not found at $MERGING_DIR"
  exit 1
fi

# 创建缓存目录
if [ ! -d "$CACHE_DIR" ]; then
  echo "Creating cache directory..."
  mkdir -p "$CACHE_DIR"
fi

# 下载文件，有缓存时不再下载
echo "Downloading AdGuardHome..."
for url in "${!URL_WITH_CACHE_PATH[@]}"; do
  cache_path="${URL_WITH_CACHE_PATH[$url]}"
  if [ ! -f "$cache_path" ]; then
    echo "Downloading $url..."
    if curl -L -o "$cache_path" "$url"; then
      echo "Download completed successfully."
    else
      echo "Download failed. Exiting..."
      exit 1
    fi
  else
    echo "File already exists in cache. Skipping download."
  fi
done

# 使用 tar 解压文件
echo "Extracting AdGuardHome..."
for url in "${!URL_WITH_CACHE_PATH[@]}"; do
  cache_path="${URL_WITH_CACHE_PATH[$url]}"

  if [[ "$cache_path" =~ AdGuardHome_linux_(arm64|armv7)\.tar\.gz$ ]]; then
    arch="${BASH_REMATCH[1]}"
    extract_dir="$CACHE_DIR/$arch"
  else
    echo "Invalid file path: $cache_path" >&2
    exit 1
  fi

  if [ ! -d "$extract_dir" ]; then
    mkdir -p "$extract_dir"
    echo "Extracting $cache_path..."
    if tar -xzf "$cache_path" -C "$extract_dir"; then
      echo "Extraction completed successfully."
    else
      echo "Extraction failed"
      exit 1
    fi
  fi
done

# 设置项目根目录
PROJECT_ROOT="$SCRIPT_DIR/src"

# 检查是否安装了 zip
if ! command -v zip &> /dev/null; then
  echo "Error: zip command not found. Please install zip."
  exit 1
fi

# 更新 src/module.prop 中的 version
MODULE_PROP="$PROJECT_ROOT/module.prop"
if [ -f "$MODULE_PROP" ]; then
  echo "Updating version in $MODULE_PROP to ${TIMESTAMP}_beta..."
  sed -i "s/^version=.*/version=${TIMESTAMP}_beta/" "$MODULE_PROP"
  echo "Version updated successfully."
else
  echo "Warning: $MODULE_PROP not found, skipping version update."
fi

# 定义中间产物路径 (架构包不带时间戳)
ARM64_ZIP="$CACHE_DIR/AdGuardHomeForRoot_AutoOpt_arm64.zip"
ARMV7_ZIP="$CACHE_DIR/AdGuardHomeForRoot_AutoOpt_armv7.zip"

# 合并包带时间戳
OUTPUT_PATH="$CACHE_DIR/(beta)AdGuardHomeForRoot_AutoOpt_${TIMESTAMP}.zip"

# 删除已存在的文件
[ -f "$ARM64_ZIP" ] && rm -f "$ARM64_ZIP"
[ -f "$ARMV7_ZIP" ] && rm -f "$ARMV7_ZIP"
[ -f "$OUTPUT_PATH" ] && rm -f "$OUTPUT_PATH"

# 打包函数 - 生成架构特定的模块包
pack_arch_module() {
  local output_path="$1"
  local arch="$2"
  local binary_path="$CACHE_DIR/$arch/AdGuardHome/AdGuardHome"

  echo "Packing $arch module to $(basename "$output_path")..."

  local temp_dir=$(mktemp -d)

  cp -r "$PROJECT_ROOT"/* "$temp_dir/" 2>/dev/null || true

  mkdir -p "$temp_dir/bin"
  cp "$binary_path" "$temp_dir/bin/AdGuardHome"
  chmod +x "$temp_dir/bin/AdGuardHome"

  (cd "$temp_dir" && zip -r "$output_path" . -x "*.git*")

  rm -rf "$temp_dir"

  echo "$arch module packed successfully."
}

# 第一步：打包 arm64
pack_arch_module "$ARM64_ZIP" "arm64"

# 第二步：打包 armv7
pack_arch_module "$ARMV7_ZIP" "armv7"

# 第三步：生成 SHA256 校验文件
echo ""
echo "Generating SHA256 checksums..."

cd "$CACHE_DIR"

# 生成 arm64 的 sha256 文件
ARM64_SHA256=$(sha256sum "AdGuardHomeForRoot_AutoOpt_arm64.zip" | awk '{print $1}')
echo "$ARM64_SHA256" > "AdGuardHomeForRoot_AutoOpt_arm64.zip.sha256"
echo "  AdGuardHomeForRoot_AutoOpt_arm64.zip.sha256"

# 生成 armv7 的 sha256 文件
ARMV7_SHA256=$(sha256sum "AdGuardHomeForRoot_AutoOpt_armv7.zip" | awk '{print $1}')
echo "$ARMV7_SHA256" > "AdGuardHomeForRoot_AutoOpt_armv7.zip.sha256"
echo "  AdGuardHomeForRoot_AutoOpt_armv7.zip.sha256"

# 第四步：准备 merging 目录并生成 SHA256 文件
echo ""
echo "Preparing merging directory with SHA256 checksums..."

MERGING_TEMP=$(mktemp -d)
cp -r "$MERGING_DIR"/* "$MERGING_TEMP/" 2>/dev/null || true

# 为 merging 目录中的所有文件生成 sha256 校验文件
find "$MERGING_TEMP" -type f | while read -r file; do
  filename=$(basename "$file")
  filesha256=$(sha256sum "$file" | awk '{print $1}')
  echo "$filesha256" > "$file.sha256"
  echo "  $filename.sha256"
done

# 第五步：合并到最终包
echo ""
echo "Merging into final package..."

FINAL_TEMP=$(mktemp -d)

cp -r "$MERGING_TEMP"/* "$FINAL_TEMP/" 2>/dev/null || true

mkdir -p "$FINAL_TEMP/AdGuardHome"
cp "$ARM64_ZIP" "$FINAL_TEMP/AdGuardHome/"
cp "$ARMV7_ZIP" "$FINAL_TEMP/AdGuardHome/"
cp "$ARM64_ZIP.sha256" "$FINAL_TEMP/AdGuardHome/"
cp "$ARMV7_ZIP.sha256" "$FINAL_TEMP/AdGuardHome/"

echo "Creating final zip archive..."
(cd "$FINAL_TEMP" && zip -r "$OUTPUT_PATH" . -x "*.git*")

rm -rf "$FINAL_TEMP"
rm -rf "$MERGING_TEMP"

# 第六步：清理临时文件
echo ""
echo "Cleaning up temporary files..."
rm -f "$ARM64_ZIP"
rm -f "$ARMV7_ZIP"
rm -f "$ARM64_ZIP.sha256"
rm -f "$ARMV7_ZIP.sha256"
echo "  Removed: AdGuardHomeForRoot_AutoOpt_arm64.zip"
echo "  Removed: AdGuardHomeForRoot_AutoOpt_armv7.zip"
echo "  Removed: AdGuardHomeForRoot_AutoOpt_arm64.zip.sha256"
echo "  Removed: AdGuardHomeForRoot_AutoOpt_armv7.zip.sha256"

echo ""
echo "========================================"
echo "Build completed successfully!"
echo "========================================"
echo ""
echo "Timestamp: $TIMESTAMP"
echo ""
echo "Generated file:"
echo "  $OUTPUT_PATH"
echo ""
echo "Final package structure:"
echo "  AdGuardHome/"
echo "    ├── AdGuardHomeForRoot_AutoOpt_arm64.zip"
echo "    ├── AdGuardHomeForRoot_AutoOpt_arm64.zip.sha256"
echo "    ├── AdGuardHomeForRoot_AutoOpt_armv7.zip"
echo "    └── AdGuardHomeForRoot_AutoOpt_armv7.zip.sha256"
echo "  [files from merging/ + their .sha256 files]"
echo ""
echo "Note: Architecture-specific modules with SHA256 checksums"
echo "      are packed inside the final zip. Temporary files cleaned."
