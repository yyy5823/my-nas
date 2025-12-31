# FFmpeg Download Script for Windows
# Downloads pre-built FFmpeg binary from Martin Riedl's build server
#
# Usage: .\scripts\download_ffmpeg.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$TargetDir = Join-Path $ProjectDir "windows\ffmpeg"
$TargetFile = Join-Path $TargetDir "ffmpeg.exe"

$DownloadUrl = "https://ffmpeg.martin-riedl.de/redirect/latest/windows/amd64/release/ffmpeg.zip"

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

    # Move ffmpeg.exe to target
    $ExtractedExe = Join-Path $TempDir "ffmpeg.exe"
    if (Test-Path $ExtractedExe) {
        Move-Item -Path $ExtractedExe -Destination $TargetFile -Force
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
