#!/bin/bash
# fpcalc 下载和打包脚本
# 用于将 fpcalc 二进制文件打包到应用中

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHROMAPRINT_VERSION="1.5.1"
DOWNLOAD_DIR="$SCRIPT_DIR/downloads"
OUTPUT_DIR="$SCRIPT_DIR/binaries"

# 创建目录
mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$OUTPUT_DIR/macos"
mkdir -p "$OUTPUT_DIR/windows"
mkdir -p "$OUTPUT_DIR/linux"

echo "=== fpcalc 下载和打包脚本 ==="
echo "Chromaprint 版本: $CHROMAPRINT_VERSION"
echo ""

# 下载函数
download_file() {
    local url="$1"
    local output="$2"

    if [ -f "$output" ]; then
        echo "文件已存在: $output"
        return 0
    fi

    echo "下载: $url"
    curl -L -o "$output" "$url"
}

# macOS
download_macos() {
    echo ""
    echo "=== 下载 macOS 版本 ==="

    local url="https://github.com/acoustid/chromaprint/releases/download/v${CHROMAPRINT_VERSION}/chromaprint-fpcalc-${CHROMAPRINT_VERSION}-macos-universal.tar.gz"
    local archive="$DOWNLOAD_DIR/chromaprint-macos.tar.gz"

    download_file "$url" "$archive"

    echo "解压..."
    tar -xzf "$archive" -C "$DOWNLOAD_DIR"

    # 复制 fpcalc
    local fpcalc_path=$(find "$DOWNLOAD_DIR" -name "fpcalc" -type f | head -1)
    if [ -n "$fpcalc_path" ]; then
        cp "$fpcalc_path" "$OUTPUT_DIR/macos/fpcalc"
        chmod +x "$OUTPUT_DIR/macos/fpcalc"
        echo "已复制到: $OUTPUT_DIR/macos/fpcalc"
    else
        echo "错误: 未找到 fpcalc"
        return 1
    fi
}

# Windows
download_windows() {
    echo ""
    echo "=== 下载 Windows 版本 ==="

    local url="https://github.com/acoustid/chromaprint/releases/download/v${CHROMAPRINT_VERSION}/chromaprint-fpcalc-${CHROMAPRINT_VERSION}-windows-x86_64.zip"
    local archive="$DOWNLOAD_DIR/chromaprint-windows.zip"

    download_file "$url" "$archive"

    echo "解压..."
    unzip -o "$archive" -d "$DOWNLOAD_DIR/windows-extract"

    # 复制 fpcalc.exe
    local fpcalc_path=$(find "$DOWNLOAD_DIR/windows-extract" -name "fpcalc.exe" -type f | head -1)
    if [ -n "$fpcalc_path" ]; then
        cp "$fpcalc_path" "$OUTPUT_DIR/windows/fpcalc.exe"
        echo "已复制到: $OUTPUT_DIR/windows/fpcalc.exe"
    else
        echo "错误: 未找到 fpcalc.exe"
        return 1
    fi
}

# Linux
download_linux() {
    echo ""
    echo "=== 下载 Linux 版本 ==="

    local url="https://github.com/acoustid/chromaprint/releases/download/v${CHROMAPRINT_VERSION}/chromaprint-fpcalc-${CHROMAPRINT_VERSION}-linux-x86_64.tar.gz"
    local archive="$DOWNLOAD_DIR/chromaprint-linux.tar.gz"

    download_file "$url" "$archive"

    echo "解压..."
    tar -xzf "$archive" -C "$DOWNLOAD_DIR"

    # 复制 fpcalc
    local fpcalc_path=$(find "$DOWNLOAD_DIR" -name "fpcalc" -type f -path "*linux*" | head -1)
    if [ -z "$fpcalc_path" ]; then
        fpcalc_path=$(find "$DOWNLOAD_DIR/chromaprint-fpcalc-${CHROMAPRINT_VERSION}-linux-x86_64" -name "fpcalc" -type f | head -1)
    fi

    if [ -n "$fpcalc_path" ]; then
        cp "$fpcalc_path" "$OUTPUT_DIR/linux/fpcalc"
        chmod +x "$OUTPUT_DIR/linux/fpcalc"
        echo "已复制到: $OUTPUT_DIR/linux/fpcalc"
    else
        echo "错误: 未找到 fpcalc"
        return 1
    fi
}

# 安装到项目
install_to_project() {
    echo ""
    echo "=== 安装到项目 ==="

    # macOS
    if [ -f "$OUTPUT_DIR/macos/fpcalc" ]; then
        local macos_resources="$PROJECT_ROOT/macos/Runner/Resources"
        mkdir -p "$macos_resources"
        cp "$OUTPUT_DIR/macos/fpcalc" "$macos_resources/"
        chmod +x "$macos_resources/fpcalc"
        echo "已安装到 macOS: $macos_resources/fpcalc"
    fi

    # Windows
    if [ -f "$OUTPUT_DIR/windows/fpcalc.exe" ]; then
        local windows_data="$PROJECT_ROOT/windows/runner/data"
        mkdir -p "$windows_data"
        cp "$OUTPUT_DIR/windows/fpcalc.exe" "$windows_data/"
        echo "已安装到 Windows: $windows_data/fpcalc.exe"
    fi

    # Linux
    if [ -f "$OUTPUT_DIR/linux/fpcalc" ]; then
        local linux_data="$PROJECT_ROOT/linux/data"
        mkdir -p "$linux_data"
        cp "$OUTPUT_DIR/linux/fpcalc" "$linux_data/"
        chmod +x "$linux_data/fpcalc"
        echo "已安装到 Linux: $linux_data/fpcalc"
    fi
}

# 清理
cleanup() {
    echo ""
    echo "=== 清理临时文件 ==="
    rm -rf "$DOWNLOAD_DIR"
    echo "已清理"
}

# 主流程
main() {
    case "${1:-all}" in
        macos)
            download_macos
            ;;
        windows)
            download_windows
            ;;
        linux)
            download_linux
            ;;
        all)
            download_macos
            download_windows
            download_linux
            ;;
        install)
            install_to_project
            ;;
        clean)
            cleanup
            ;;
        *)
            echo "用法: $0 [macos|windows|linux|all|install|clean]"
            exit 1
            ;;
    esac

    if [ "${1:-all}" != "clean" ] && [ "${1:-all}" != "install" ]; then
        echo ""
        echo "=== 完成 ==="
        echo "二进制文件位于: $OUTPUT_DIR"
        echo ""
        echo "运行 '$0 install' 将文件安装到项目中"
    fi
}

main "$@"
