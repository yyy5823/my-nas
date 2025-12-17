#!/bin/bash
# 修复 KissFFT 目录结构以兼容 Chromaprint

KISSFFT_DIR="/Volumes/od/my-nas/native/chromaprint/build/kissfft"

echo "修复 KissFFT 目录结构..."

# 创建 tools 目录中的符号链接
cd "$KISSFFT_DIR/tools"

# 链接根目录中的文件到 tools 目录
for file in kiss_fftr.c kiss_fftr.h kiss_fft.c kiss_fft.h _kiss_fft_guts.h; do
    if [ -f "../$file" ] && [ ! -e "$file" ]; then
        ln -s "../$file" "$file"
        echo "✓ 链接 $file"
    fi
done

echo "完成!"
