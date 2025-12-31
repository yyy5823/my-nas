#!/bin/bash
# FFmpeg Download Script for my-nas
# Downloads pre-built FFmpeg binaries for each platform
#
# Usage: ./scripts/download_ffmpeg.sh [platform]
#   platform: macos, windows, linux (default: current platform)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# FFmpeg version and download URLs
FFMPEG_VERSION="8.0.1"
MARTIN_RIEDL_BASE="https://ffmpeg.martin-riedl.de/redirect/latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

download_macos() {
    local target_dir="$PROJECT_DIR/macos/Runner/Resources/ffmpeg"
    local target_file="$target_dir/ffmpeg"

    # Check if already exists
    if [ -f "$target_file" ]; then
        log_info "FFmpeg already exists at $target_file"
        file "$target_file" | grep -q "universal" && {
            log_info "Existing FFmpeg is Universal binary, skipping download"
            return 0
        }
        log_warn "Existing FFmpeg is not Universal, re-downloading..."
    fi

    log_info "Downloading FFmpeg $FFMPEG_VERSION for macOS (Universal)..."

    mkdir -p "$target_dir"
    local tmp_dir=$(mktemp -d)

    # Download arm64
    log_info "  Downloading arm64..."
    curl -L "$MARTIN_RIEDL_BASE/macos/arm64/release/ffmpeg.zip" -o "$tmp_dir/arm64.zip"
    unzip -q "$tmp_dir/arm64.zip" -d "$tmp_dir/arm64"

    # Download x86_64
    log_info "  Downloading x86_64..."
    curl -L "$MARTIN_RIEDL_BASE/macos/amd64/release/ffmpeg.zip" -o "$tmp_dir/x64.zip"
    unzip -q "$tmp_dir/x64.zip" -d "$tmp_dir/x64"

    # Create Universal binary
    log_info "  Creating Universal binary..."
    lipo -create "$tmp_dir/arm64/ffmpeg" "$tmp_dir/x64/ffmpeg" -output "$target_file"
    chmod +x "$target_file"

    # Cleanup
    rm -rf "$tmp_dir"

    # Verify
    log_info "  Verifying..."
    file "$target_file"
    "$target_file" -version | head -1

    log_info "FFmpeg downloaded successfully to $target_file"
}

download_windows() {
    local target_dir="$PROJECT_DIR/windows/ffmpeg"
    local target_file="$target_dir/ffmpeg.exe"

    if [ -f "$target_file" ]; then
        log_info "FFmpeg already exists at $target_file, skipping"
        return 0
    fi

    log_info "Downloading FFmpeg $FFMPEG_VERSION for Windows..."

    mkdir -p "$target_dir"
    local tmp_dir=$(mktemp -d)

    curl -L "$MARTIN_RIEDL_BASE/windows/amd64/release/ffmpeg.zip" -o "$tmp_dir/ffmpeg.zip"
    unzip -q "$tmp_dir/ffmpeg.zip" -d "$tmp_dir"
    mv "$tmp_dir/ffmpeg.exe" "$target_file"

    rm -rf "$tmp_dir"

    log_info "FFmpeg downloaded successfully to $target_file"
}

download_linux() {
    local target_dir="$PROJECT_DIR/linux/ffmpeg"
    local target_file="$target_dir/ffmpeg"

    if [ -f "$target_file" ]; then
        log_info "FFmpeg already exists at $target_file, skipping"
        return 0
    fi

    log_info "Downloading FFmpeg $FFMPEG_VERSION for Linux..."

    mkdir -p "$target_dir"
    local tmp_dir=$(mktemp -d)

    curl -L "$MARTIN_RIEDL_BASE/linux/amd64/release/ffmpeg.zip" -o "$tmp_dir/ffmpeg.zip"
    unzip -q "$tmp_dir/ffmpeg.zip" -d "$tmp_dir"
    mv "$tmp_dir/ffmpeg" "$target_file"
    chmod +x "$target_file"

    rm -rf "$tmp_dir"

    log_info "FFmpeg downloaded successfully to $target_file"
}

# Detect platform if not specified
detect_platform() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)  echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Main
PLATFORM="${1:-$(detect_platform)}"

case "$PLATFORM" in
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
    *)
        log_error "Unknown platform: $PLATFORM"
        echo "Usage: $0 [macos|windows|linux|all]"
        exit 1
        ;;
esac

log_info "Done!"
