#!/bin/bash

# 定义下载 URL 和路径变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/cache"

declare -A URL_WITH_CACHE_PATH=(
  ["https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_arm64.tar.gz"]="$CACHE_DIR/AdGuardHome_linux_arm64.tar.gz"
  ["https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_armv7.tar.gz"]="$CACHE_DIR/AdGuardHome_linux_armv7.tar.gz"
)

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

# 给项目打包，使用 zip 压缩
echo "Packing AdGuardHome..."
OUTPUT_PATH_ARM64="$CACHE_DIR/AdGuardHomeForRoot_arm64.zip"
OUTPUT_PATH_ARMV7="$CACHE_DIR/AdGuardHomeForRoot_armv7.zip"

# 删除已存在的输出文件
[ -f "$OUTPUT_PATH_ARM64" ] && rm -f "$OUTPUT_PATH_ARM64"
[ -f "$OUTPUT_PATH_ARMV7" ] && rm -f "$OUTPUT_PATH_ARMV7"

# 设置项目根目录
PROJECT_ROOT="$SCRIPT_DIR/src"

# 检查是否安装了 zip
if ! command -v zip &> /dev/null; then
  echo "Error: zip command not found. Please install zip."
  exit 1
fi

# 打包函数
pack_module() {
  local output_path="$1"
  local arch="$2"
  local binary_path="$CACHE_DIR/$arch/AdGuardHome/AdGuardHome"
  
  echo "Packing $arch module to $output_path..."
  
  # 创建临时目录用于构建
  TEMP_DIR=$(mktemp -d)
  
  # 复制项目文件
  cp -r "$PROJECT_ROOT"/* "$TEMP_DIR/" 2>/dev/null || true
  
  # 确保 bin 目录存在并复制二进制文件
  mkdir -p "$TEMP_DIR/bin"
  cp "$binary_path" "$TEMP_DIR/bin/AdGuardHome"
  chmod +x "$TEMP_DIR/bin/AdGuardHome"
  
  # 进入临时目录并打包
  (cd "$TEMP_DIR" && zip -r "$output_path" . -x "*.git*")
  
  # 清理临时目录
  rm -rf "$TEMP_DIR"
  
  echo "$arch module packed successfully."
}

# 打包 arm64
pack_module "$OUTPUT_PATH_ARM64" "arm64"

# 打包 armv7
pack_module "$OUTPUT_PATH_ARMV7" "armv7"

echo "Packing completed successfully."
echo "Output files:"
echo "  - $OUTPUT_PATH_ARM64"
echo "  - $OUTPUT_PATH_ARMV7"
