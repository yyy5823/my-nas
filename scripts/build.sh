#!/bin/bash

# MyNAS 交互式构建脚本
# 支持多平台和多架构构建

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 输出目录
OUTPUT_DIR="$PROJECT_DIR/build/releases"

# 获取版本号
get_version() {
    grep "^version:" "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | tr -d ' '
}

VERSION=$(get_version)

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              MyNAS 构建工具 v1.0                             ║"
echo "║                  版本: $VERSION                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 平台选择菜单
show_platform_menu() {
    echo -e "${YELLOW}请选择目标平台:${NC}"
    echo ""
    echo "  1) Android APK (按架构分包)"
    echo "  2) Android APK (通用包)"
    echo "  3) Android App Bundle (.aab)"
    echo "  4) iOS (.ipa)"
    echo "  5) macOS (.app)"
    echo "  6) Windows (.exe)"
    echo "  7) Linux"
    echo "  8) 全部 Android 架构"
    echo ""
    echo "  0) 退出"
    echo ""
}

# Android 架构选择菜单
show_android_arch_menu() {
    echo -e "${YELLOW}请选择 Android 架构:${NC}"
    echo ""
    echo "  1) arm64-v8a (64位 ARM，推荐现代设备)"
    echo "  2) armeabi-v7a (32位 ARM，兼容旧设备)"
    echo "  3) x86_64 (64位 x86，模拟器/特殊设备)"
    echo "  4) 全部架构"
    echo ""
    echo "  0) 返回"
    echo ""
}

# 构建模式选择
show_build_mode_menu() {
    echo -e "${YELLOW}请选择构建模式:${NC}"
    echo ""
    echo "  1) Release (发布版，优化性能)"
    echo "  2) Profile (性能分析版)"
    echo "  3) Debug (调试版)"
    echo ""
}

# 准备构建环境
prepare_build() {
    echo -e "${BLUE}[准备] 清理并获取依赖...${NC}"
    cd "$PROJECT_DIR"
    flutter clean
    flutter pub get
}

# 构建 Android APK (指定架构)
build_android_apk() {
    local arch=$1
    local mode=$2
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] Android APK - $arch ($mode)${NC}"

    local target_platform=""
    case $arch in
        "arm64-v8a") target_platform="android-arm64" ;;
        "armeabi-v7a") target_platform="android-arm" ;;
        "x86_64") target_platform="android-x64" ;;
    esac

    flutter build apk $mode_flag --target-platform=$target_platform

    # 复制到输出目录
    mkdir -p "$OUTPUT_DIR/android"
    local output_name="mynas-${VERSION}-${arch}-${mode}.apk"
    cp "$PROJECT_DIR/build/app/outputs/flutter-apk/app-${mode}.apk" "$OUTPUT_DIR/android/$output_name"

    echo -e "${GREEN}[完成] $OUTPUT_DIR/android/$output_name${NC}"
}

# 构建全部 Android 架构
build_android_all_archs() {
    local mode=$1
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] Android APK - 全部架构 ($mode)${NC}"

    flutter build apk $mode_flag --split-per-abi

    # 复制到输出目录
    mkdir -p "$OUTPUT_DIR/android"

    for apk in "$PROJECT_DIR/build/app/outputs/flutter-apk/"*-${mode}.apk; do
        if [ -f "$apk" ]; then
            local filename=$(basename "$apk")
            local arch_name=$(echo "$filename" | sed "s/app-//" | sed "s/-${mode}.apk//")
            local output_name="mynas-${VERSION}-${arch_name}-${mode}.apk"
            cp "$apk" "$OUTPUT_DIR/android/$output_name"
            echo -e "${GREEN}[完成] $OUTPUT_DIR/android/$output_name${NC}"
        fi
    done
}

# 构建通用 Android APK
build_android_universal() {
    local mode=$1
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] Android 通用 APK ($mode)${NC}"

    flutter build apk $mode_flag

    mkdir -p "$OUTPUT_DIR/android"
    local output_name="mynas-${VERSION}-universal-${mode}.apk"
    cp "$PROJECT_DIR/build/app/outputs/flutter-apk/app-${mode}.apk" "$OUTPUT_DIR/android/$output_name"

    echo -e "${GREEN}[完成] $OUTPUT_DIR/android/$output_name${NC}"
}

# 构建 Android App Bundle
build_android_aab() {
    local mode=$1
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] Android App Bundle ($mode)${NC}"

    flutter build appbundle $mode_flag

    mkdir -p "$OUTPUT_DIR/android"
    local output_name="mynas-${VERSION}-${mode}.aab"
    cp "$PROJECT_DIR/build/app/outputs/bundle/${mode}/app-${mode}.aab" "$OUTPUT_DIR/android/$output_name"

    echo -e "${GREEN}[完成] $OUTPUT_DIR/android/$output_name${NC}"
}

# 构建 iOS
build_ios() {
    local mode=$1
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] iOS IPA ($mode)${NC}"

    flutter build ipa $mode_flag --no-codesign

    mkdir -p "$OUTPUT_DIR/ios"
    echo -e "${GREEN}[完成] 请在 $PROJECT_DIR/build/ios/ipa/ 目录查看输出${NC}"
}

# 构建 macOS
build_macos() {
    local mode=$1
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] macOS App ($mode)${NC}"

    flutter build macos $mode_flag

    mkdir -p "$OUTPUT_DIR/macos"
    echo -e "${GREEN}[完成] 请在 $PROJECT_DIR/build/macos/Build/Products/ 目录查看输出${NC}"
}

# 构建 Windows
build_windows() {
    local mode=$1
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] Windows ($mode)${NC}"

    flutter build windows $mode_flag

    mkdir -p "$OUTPUT_DIR/windows"
    echo -e "${GREEN}[完成] 请在 $PROJECT_DIR/build/windows/x64/runner/ 目录查看输出${NC}"
}

# 构建 Linux
build_linux() {
    local mode=$1
    local mode_flag=""

    case $mode in
        "release") mode_flag="--release" ;;
        "profile") mode_flag="--profile" ;;
        "debug") mode_flag="--debug" ;;
    esac

    echo -e "${GREEN}[构建] Linux ($mode)${NC}"

    flutter build linux $mode_flag

    mkdir -p "$OUTPUT_DIR/linux"
    echo -e "${GREEN}[完成] 请在 $PROJECT_DIR/build/linux/x64/release/bundle/ 目录查看输出${NC}"
}

# 选择构建模式
select_build_mode() {
    show_build_mode_menu
    read -p "请输入选项 [1-3]: " mode_choice

    case $mode_choice in
        1) echo "release" ;;
        2) echo "profile" ;;
        3) echo "debug" ;;
        *) echo "release" ;;
    esac
}

# 主菜单循环
main() {
    while true; do
        show_platform_menu
        read -p "请输入选项 [0-8]: " platform_choice

        case $platform_choice in
            0)
                echo -e "${CYAN}再见!${NC}"
                exit 0
                ;;
            1)
                # Android APK 按架构
                show_android_arch_menu
                read -p "请输入选项 [0-4]: " arch_choice

                case $arch_choice in
                    0) continue ;;
                    1)
                        mode=$(select_build_mode)
                        prepare_build
                        build_android_apk "arm64-v8a" "$mode"
                        ;;
                    2)
                        mode=$(select_build_mode)
                        prepare_build
                        build_android_apk "armeabi-v7a" "$mode"
                        ;;
                    3)
                        mode=$(select_build_mode)
                        prepare_build
                        build_android_apk "x86_64" "$mode"
                        ;;
                    4)
                        mode=$(select_build_mode)
                        prepare_build
                        build_android_all_archs "$mode"
                        ;;
                    *)
                        echo -e "${RED}无效选项${NC}"
                        ;;
                esac
                ;;
            2)
                # Android 通用 APK
                mode=$(select_build_mode)
                prepare_build
                build_android_universal "$mode"
                ;;
            3)
                # Android App Bundle
                mode=$(select_build_mode)
                prepare_build
                build_android_aab "$mode"
                ;;
            4)
                # iOS
                if [[ "$OSTYPE" != "darwin"* ]]; then
                    echo -e "${RED}iOS 构建仅支持 macOS${NC}"
                    continue
                fi
                mode=$(select_build_mode)
                prepare_build
                build_ios "$mode"
                ;;
            5)
                # macOS
                if [[ "$OSTYPE" != "darwin"* ]]; then
                    echo -e "${RED}macOS 构建仅支持 macOS${NC}"
                    continue
                fi
                mode=$(select_build_mode)
                prepare_build
                build_macos "$mode"
                ;;
            6)
                # Windows
                mode=$(select_build_mode)
                prepare_build
                build_windows "$mode"
                ;;
            7)
                # Linux
                mode=$(select_build_mode)
                prepare_build
                build_linux "$mode"
                ;;
            8)
                # 全部 Android 架构
                mode=$(select_build_mode)
                prepare_build
                build_android_all_archs "$mode"
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                ;;
        esac

        echo ""
        read -p "按回车键继续..."
        clear
    done
}

# 检查 Flutter 是否可用
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}错误: Flutter 未安装或不在 PATH 中${NC}"
    exit 1
fi

# 运行主函数
main
