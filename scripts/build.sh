#!/bin/bash

# MyNAS Interactive Build Script
# Supports multi-platform and multi-architecture builds

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/build/releases"

# Get version from pubspec.yaml
get_version() {
    grep "^version:" "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | tr -d ' '
}

VERSION=$(get_version)

write_header() {
    echo -e "${CYAN}"
    echo "=================================================================="
    echo "              MyNAS Build Tool v1.0                               "
    echo "              Version: $VERSION                                   "
    echo "=================================================================="
    echo -e "${NC}"
}

show_platform_menu() {
    echo -e "${YELLOW}Select target platform:${NC}"
    echo ""
    echo "  [Android]"
    echo "    1) Android APK (split by arch)"
    echo "    2) Android APK (universal)"
    echo "    3) Android App Bundle (.aab)"
    echo ""
    echo "  [Desktop]"
    echo "    4) Windows"
    echo "    5) macOS"
    echo "    6) Linux"
    echo ""
    echo "  [Mobile]"
    echo "    7) iOS (.ipa)"
    echo ""
    echo "  0) Exit"
    echo ""
}

show_android_arch_menu() {
    echo -e "${YELLOW}Select Android architecture:${NC}"
    echo ""
    echo "  1) arm64-v8a    (64-bit ARM, modern devices)"
    echo "  2) armeabi-v7a  (32-bit ARM, older devices)"
    echo "  3) x86_64       (64-bit x86, emulator)"
    echo "  4) All architectures"
    echo ""
    echo "  0) Back"
    echo ""
}

show_windows_arch_menu() {
    echo -e "${YELLOW}Select Windows architecture:${NC}"
    echo ""
    echo "  1) x64    (64-bit Intel/AMD, most common)"
    echo "  2) x86    (32-bit Intel/AMD, legacy) [Limited support]"
    echo "  3) arm64  (ARM 64-bit, Surface Pro X) [Experimental]"
    echo ""
    echo "  0) Back"
    echo ""
}

show_macos_arch_menu() {
    echo -e "${YELLOW}Select macOS architecture:${NC}"
    echo ""
    echo "  1) Universal  (x64 + arm64, recommended)"
    echo "  2) arm64      (Apple Silicon M1/M2/M3/M4)"
    echo "  3) x64        (Intel Mac)"
    echo ""
    echo "  0) Back"
    echo ""
}

show_linux_arch_menu() {
    echo -e "${YELLOW}Select Linux architecture:${NC}"
    echo ""
    echo "  1) x64    (64-bit Intel/AMD, most common)"
    echo "  2) arm64  (ARM 64-bit, Raspberry Pi etc) [Experimental]"
    echo ""
    echo "  0) Back"
    echo ""
}

show_build_mode_menu() {
    echo -e "${YELLOW}Select build mode:${NC}"
    echo ""
    echo "  1) Release (optimized for performance)"
    echo "  2) Profile (for performance analysis)"
    echo "  3) Debug   (for debugging)"
    echo ""
}

select_build_mode() {
    show_build_mode_menu
    read -p "Enter option [1-3]: " mode_choice
    case $mode_choice in
        1) echo "release" ;;
        2) echo "profile" ;;
        3) echo "debug" ;;
        *) echo "release" ;;
    esac
}

prepare_build() {
    echo -e "${BLUE}[Prepare] Cleaning and fetching dependencies...${NC}"
    cd "$PROJECT_DIR"
    flutter clean
    flutter pub get
}

# ============ Android Build Functions ============

build_android_apk() {
    local arch=$1
    local mode=$2
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] Android APK - $arch ($mode)${NC}"

    local target_platform=""
    case $arch in
        "arm64-v8a") target_platform="android-arm64" ;;
        "armeabi-v7a") target_platform="android-arm" ;;
        "x86_64") target_platform="android-x64" ;;
    esac

    flutter build apk $mode_flag --target-platform=$target_platform

    # Copy to output directory
    mkdir -p "$OUTPUT_DIR/android"
    local output_name="mynas-${VERSION}-android-${arch}-${mode}.apk"
    cp "$PROJECT_DIR/build/app/outputs/flutter-apk/app-${mode}.apk" "$OUTPUT_DIR/android/$output_name"

    echo -e "${GREEN}[Done] $OUTPUT_DIR/android/$output_name${NC}"
}

build_android_all_archs() {
    local mode=$1
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] Android APK - All architectures ($mode)${NC}"

    flutter build apk $mode_flag --split-per-abi

    # Copy to output directory
    mkdir -p "$OUTPUT_DIR/android"

    for apk in "$PROJECT_DIR/build/app/outputs/flutter-apk/"*-${mode}.apk; do
        if [ -f "$apk" ]; then
            local filename=$(basename "$apk")
            local arch_name=$(echo "$filename" | sed "s/app-//" | sed "s/-${mode}.apk//")
            local output_name="mynas-${VERSION}-android-${arch_name}-${mode}.apk"
            cp "$apk" "$OUTPUT_DIR/android/$output_name"
            echo -e "${GREEN}[Done] $OUTPUT_DIR/android/$output_name${NC}"
        fi
    done
}

build_android_universal() {
    local mode=$1
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] Android Universal APK ($mode)${NC}"

    flutter build apk $mode_flag

    mkdir -p "$OUTPUT_DIR/android"
    local output_name="mynas-${VERSION}-android-universal-${mode}.apk"
    cp "$PROJECT_DIR/build/app/outputs/flutter-apk/app-${mode}.apk" "$OUTPUT_DIR/android/$output_name"

    echo -e "${GREEN}[Done] $OUTPUT_DIR/android/$output_name${NC}"
}

build_android_aab() {
    local mode=$1
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] Android App Bundle ($mode)${NC}"

    flutter build appbundle $mode_flag

    mkdir -p "$OUTPUT_DIR/android"
    local output_name="mynas-${VERSION}-android-${mode}.aab"
    cp "$PROJECT_DIR/build/app/outputs/bundle/${mode}/app-${mode}.aab" "$OUTPUT_DIR/android/$output_name"

    echo -e "${GREEN}[Done] $OUTPUT_DIR/android/$output_name${NC}"
}

# ============ Windows Build Functions ============

build_windows() {
    local arch=$1
    local mode=$2
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] Windows $arch ($mode)${NC}"

    if [[ "$OSTYPE" != "msys"* ]] && [[ "$OSTYPE" != "cygwin"* ]] && [[ "$OSTYPE" != "win"* ]]; then
        echo -e "${RED}Windows build is only supported on Windows${NC}"
        return 1
    fi

    case $arch in
        "x64")
            flutter build windows $mode_flag
            ;;
        "arm64")
            echo -e "${YELLOW}[Warning] Windows ARM64 is experimental${NC}"
            flutter build windows $mode_flag --target-platform=windows-arm64
            ;;
        "x86")
            echo -e "${YELLOW}[Warning] Windows x86 has limited support${NC}"
            flutter build windows $mode_flag
            ;;
    esac

    mkdir -p "$OUTPUT_DIR/windows"

    local mode_cap="$(tr '[:lower:]' '[:upper:]' <<< ${mode:0:1})${mode:1}"
    echo -e "${GREEN}[Done] Output at: build/windows/$arch/runner/$mode_cap${NC}"
}

# ============ macOS Build Functions ============

build_macos() {
    local arch=$1
    local mode=$2
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] macOS $arch ($mode)${NC}"

    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}macOS build is only supported on macOS${NC}"
        return 1
    fi

    case $arch in
        "universal")
            flutter build macos $mode_flag
            ;;
        "arm64")
            flutter build macos $mode_flag --target-platform=darwin-arm64
            ;;
        "x64")
            flutter build macos $mode_flag --target-platform=darwin-x64
            ;;
    esac

    mkdir -p "$OUTPUT_DIR/macos"

    local mode_cap="$(tr '[:lower:]' '[:upper:]' <<< ${mode:0:1})${mode:1}"
    echo -e "${GREEN}[Done] Output at: build/macos/Build/Products/$mode_cap${NC}"
}

# ============ Linux Build Functions ============

build_linux() {
    local arch=$1
    local mode=$2
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] Linux $arch ($mode)${NC}"

    if [[ "$OSTYPE" != "linux"* ]]; then
        echo -e "${RED}Linux build is only supported on Linux${NC}"
        return 1
    fi

    case $arch in
        "x64")
            flutter build linux $mode_flag
            ;;
        "arm64")
            echo -e "${YELLOW}[Warning] Linux ARM64 is experimental${NC}"
            flutter build linux $mode_flag --target-platform=linux-arm64
            ;;
    esac

    mkdir -p "$OUTPUT_DIR/linux"
    echo -e "${GREEN}[Done] Output at: build/linux/$arch/release/bundle/${NC}"
}

# ============ iOS Build Functions ============

build_ios() {
    local mode=$1
    local mode_flag="--$mode"

    echo -e "${GREEN}[Build] iOS ($mode)${NC}"

    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}iOS build is only supported on macOS${NC}"
        return 1
    fi

    flutter build ipa $mode_flag --no-codesign

    mkdir -p "$OUTPUT_DIR/ios"
    echo -e "${GREEN}[Done] Output at: build/ios/ipa/${NC}"
}

# ============ Main ============

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed or not in PATH${NC}"
    exit 1
fi

# Main loop
while true; do
    clear
    write_header
    show_platform_menu

    read -p "Enter option [0-7]: " platform_choice

    case $platform_choice in
        0)
            echo -e "${CYAN}Goodbye!${NC}"
            exit 0
            ;;
        1)
            # Android APK by architecture
            show_android_arch_menu
            read -p "Enter option [0-4]: " arch_choice

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
                    echo -e "${RED}Invalid option${NC}"
                    ;;
            esac
            ;;
        2)
            mode=$(select_build_mode)
            prepare_build
            build_android_universal "$mode"
            ;;
        3)
            mode=$(select_build_mode)
            prepare_build
            build_android_aab "$mode"
            ;;
        4)
            # Windows
            show_windows_arch_menu
            read -p "Enter option [0-3]: " arch_choice

            case $arch_choice in
                0) continue ;;
                1)
                    mode=$(select_build_mode)
                    prepare_build
                    build_windows "x64" "$mode"
                    ;;
                2)
                    mode=$(select_build_mode)
                    prepare_build
                    build_windows "x86" "$mode"
                    ;;
                3)
                    mode=$(select_build_mode)
                    prepare_build
                    build_windows "arm64" "$mode"
                    ;;
                *)
                    echo -e "${RED}Invalid option${NC}"
                    ;;
            esac
            ;;
        5)
            # macOS
            show_macos_arch_menu
            read -p "Enter option [0-3]: " arch_choice

            case $arch_choice in
                0) continue ;;
                1)
                    mode=$(select_build_mode)
                    prepare_build
                    build_macos "universal" "$mode"
                    ;;
                2)
                    mode=$(select_build_mode)
                    prepare_build
                    build_macos "arm64" "$mode"
                    ;;
                3)
                    mode=$(select_build_mode)
                    prepare_build
                    build_macos "x64" "$mode"
                    ;;
                *)
                    echo -e "${RED}Invalid option${NC}"
                    ;;
            esac
            ;;
        6)
            # Linux
            show_linux_arch_menu
            read -p "Enter option [0-2]: " arch_choice

            case $arch_choice in
                0) continue ;;
                1)
                    mode=$(select_build_mode)
                    prepare_build
                    build_linux "x64" "$mode"
                    ;;
                2)
                    mode=$(select_build_mode)
                    prepare_build
                    build_linux "arm64" "$mode"
                    ;;
                *)
                    echo -e "${RED}Invalid option${NC}"
                    ;;
            esac
            ;;
        7)
            # iOS
            mode=$(select_build_mode)
            prepare_build
            build_ios "$mode"
            ;;
        *)
            echo -e "${RED}Invalid option, please try again${NC}"
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
