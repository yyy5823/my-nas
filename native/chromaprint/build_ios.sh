#!/bin/bash
# iOS Chromaprint 编译脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
CHROMAPRINT_SRC="$BUILD_DIR/chromaprint"
KISSFFT_SRC="$BUILD_DIR/kissfft"
OUTPUT_DIR="$SCRIPT_DIR/output/ios"

echo "=== Chromaprint iOS 编译脚本 ==="
echo "Build dir: $BUILD_DIR"

# 确保目录存在
mkdir -p "$OUTPUT_DIR"

# 清理旧的构建
rm -rf "$CHROMAPRINT_SRC/build-ios-device"
rm -rf "$CHROMAPRINT_SRC/build-ios-sim"

# 编译 iOS Device (arm64)
echo ""
echo "=== 编译 iOS Device (arm64) ==="
mkdir -p "$CHROMAPRINT_SRC/build-ios-device"
cd "$CHROMAPRINT_SRC/build-ios-device"

cmake .. \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TOOLS=OFF \
    -DBUILD_TESTS=OFF \
    -DFFT_LIB=kissfft \
    -DKISSFFT_SOURCE_DIR="$KISSFFT_SRC" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build . --config Release

# 编译 iOS Simulator (arm64 + x86_64)
echo ""
echo "=== 编译 iOS Simulator (arm64 + x86_64) ==="
mkdir -p "$CHROMAPRINT_SRC/build-ios-sim"
cd "$CHROMAPRINT_SRC/build-ios-sim"

cmake .. \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TOOLS=OFF \
    -DBUILD_TESTS=OFF \
    -DFFT_LIB=kissfft \
    -DKISSFFT_SOURCE_DIR="$KISSFFT_SRC" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build . --config Release

# 创建 xcframework
echo ""
echo "=== 创建 xcframework ==="

# 查找编译产物
DEVICE_LIB=$(find "$CHROMAPRINT_SRC/build-ios-device" -name "libchromaprint.a" -path "*Release*" | head -1)
SIM_LIB=$(find "$CHROMAPRINT_SRC/build-ios-sim" -name "libchromaprint.a" -path "*Release*" | head -1)

if [ -z "$DEVICE_LIB" ]; then
    echo "错误: 未找到 Device 库"
    exit 1
fi

if [ -z "$SIM_LIB" ]; then
    echo "错误: 未找到 Simulator 库"
    exit 1
fi

echo "Device lib: $DEVICE_LIB"
echo "Simulator lib: $SIM_LIB"

# 创建头文件目录
HEADERS_DIR="$OUTPUT_DIR/headers"
mkdir -p "$HEADERS_DIR"
cp "$CHROMAPRINT_SRC/src/chromaprint.h" "$HEADERS_DIR/"

# 创建 xcframework
rm -rf "$OUTPUT_DIR/Chromaprint.xcframework"
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" -headers "$HEADERS_DIR" \
    -library "$SIM_LIB" -headers "$HEADERS_DIR" \
    -output "$OUTPUT_DIR/Chromaprint.xcframework"

echo ""
echo "=== 完成 ==="
echo "xcframework 位于: $OUTPUT_DIR/Chromaprint.xcframework"
