# FFmpeg Download Script for Windows
# Downloads pre-built FFmpeg binary from BtbN's GitHub Releases (most stable mirror)
#
# Usage: .\scripts\download_ffmpeg.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$TargetDir = Join-Path $ProjectDir "windows\ffmpeg"
$TargetFile = Join-Path $TargetDir "ffmpeg.exe"

# BtbN/FFmpeg-Builds: 自动构建的 FFmpeg Windows 二进制（GPL 版含全部编解码器）
$DownloadUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"

function Write-Info { param($Message) Write-Host "[FFmpeg] $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[FFmpeg] $Message" -ForegroundColor Yellow }

# Check if already exists
if (Test-Path $TargetFile) {
    Write-Info "FFmpeg already exists at $TargetFile, skipping download"
    exit 0
}

Write-Info "Downloading FFmpeg for Windows..."

# Create target directory
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

# Download to temp
$TempDir = Join-Path $env:TEMP "ffmpeg_download_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

try {
    $ZipFile = Join-Path $TempDir "ffmpeg.zip"

    Write-Info "  Downloading from $DownloadUrl..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile -UseBasicParsing

    Write-Info "  Extracting..."
    Expand-Archive -Path $ZipFile -DestinationPath $TempDir -Force

    # BtbN 压缩包结构：ffmpeg-master-latest-win64-gpl/bin/ffmpeg.exe
    # 兼容老结构（顶层 ffmpeg.exe）以防上游变更
    $ExtractedExe = Get-ChildItem -Path $TempDir -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ExtractedExe) {
        Move-Item -Path $ExtractedExe.FullName -Destination $TargetFile -Force
    } else {
        throw "ffmpeg.exe not found in downloaded archive"
    }

    Write-Info "FFmpeg downloaded successfully to $TargetFile"
}
finally {
    # Cleanup
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Verify
$Version = & $TargetFile -version 2>&1 | Select-Object -First 1
Write-Info "Installed: $Version"
