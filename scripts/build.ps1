# MyNAS Interactive Build Script (PowerShell)
# Supports multi-platform and multi-architecture builds

$ErrorActionPreference = "Stop"

# Project root directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$OutputDir = Join-Path $ProjectDir "build\releases"

# Get version from pubspec.yaml
function Get-AppVersion {
    $pubspec = Get-Content (Join-Path $ProjectDir "pubspec.yaml") -Raw
    if ($pubspec -match "version:\s*(\S+)") {
        return $matches[1]
    }
    return "unknown"
}

$Version = Get-AppVersion

function Write-Header {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "              MyNAS Build Tool v1.0                               " -ForegroundColor Cyan
    Write-Host "              Version: $Version                                   " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-PlatformMenu {
    Write-Host "Select target platform:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [Android]"
    Write-Host "    1) Android APK (split by arch)"
    Write-Host "    2) Android APK (universal)"
    Write-Host "    3) Android App Bundle (.aab)"
    Write-Host ""
    Write-Host "  [Desktop]"
    Write-Host "    4) Windows"
    Write-Host "    5) macOS [macOS only]"
    Write-Host "    6) Linux"
    Write-Host ""
    Write-Host "  [Mobile]"
    Write-Host "    7) iOS (.ipa) [macOS only]"
    Write-Host ""
    Write-Host "  0) Exit"
    Write-Host ""
}

function Show-AndroidArchMenu {
    Write-Host "Select Android architecture:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) arm64-v8a    (64-bit ARM, modern devices)"
    Write-Host "  2) armeabi-v7a  (32-bit ARM, older devices)"
    Write-Host "  3) x86_64       (64-bit x86, emulator)"
    Write-Host "  4) All architectures"
    Write-Host ""
    Write-Host "  0) Back"
    Write-Host ""
}

function Show-WindowsArchMenu {
    Write-Host "Select Windows architecture:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) x64    (64-bit Intel/AMD, most common)"
    Write-Host "  2) x86    (32-bit Intel/AMD, legacy) [Limited support]"
    Write-Host "  3) arm64  (ARM 64-bit, Surface Pro X) [Experimental]"
    Write-Host ""
    Write-Host "  0) Back"
    Write-Host ""
}

function Show-MacOSArchMenu {
    Write-Host "Select macOS architecture:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) Universal  (x64 + arm64, recommended)"
    Write-Host "  2) arm64      (Apple Silicon M1/M2/M3/M4)"
    Write-Host "  3) x64        (Intel Mac)"
    Write-Host ""
    Write-Host "  0) Back"
    Write-Host ""
}

function Show-LinuxArchMenu {
    Write-Host "Select Linux architecture:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) x64    (64-bit Intel/AMD, most common)"
    Write-Host "  2) arm64  (ARM 64-bit, Raspberry Pi etc) [Experimental]"
    Write-Host ""
    Write-Host "  0) Back"
    Write-Host ""
}

function Show-BuildModeMenu {
    Write-Host "Select build mode:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) Release (optimized for performance)"
    Write-Host "  2) Profile (for performance analysis)"
    Write-Host "  3) Debug   (for debugging)"
    Write-Host ""
}

function Select-BuildMode {
    Show-BuildModeMenu
    $choice = Read-Host "Enter option [1-3]"
    switch ($choice) {
        "1" { return "release" }
        "2" { return "profile" }
        "3" { return "debug" }
        default { return "release" }
    }
}

function Prepare-Build {
    Write-Host "[Prepare] Cleaning and fetching dependencies..." -ForegroundColor Blue
    Set-Location $ProjectDir
    flutter clean
    flutter pub get
}

# ============ Android Build Functions ============

function Build-AndroidApk {
    param(
        [string]$Arch,
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] Android APK - $Arch ($Mode)" -ForegroundColor Green

    $targetPlatform = switch ($Arch) {
        "arm64-v8a" { "android-arm64" }
        "armeabi-v7a" { "android-arm" }
        "x86_64" { "android-x64" }
    }

    flutter build apk $modeFlag --target-platform=$targetPlatform

    # Copy to output directory
    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $outputName = "mynas-$Version-android-$Arch-$Mode.apk"
    $sourcePath = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-$Mode.apk"
    $destPath = Join-Path $androidOutputDir $outputName

    Copy-Item $sourcePath $destPath -Force
    Write-Host "[Done] $destPath" -ForegroundColor Green
}

function Build-AndroidAllArchs {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] Android APK - All architectures ($Mode)" -ForegroundColor Green

    flutter build apk $modeFlag --split-per-abi

    # Copy to output directory
    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $apkDir = Join-Path $ProjectDir "build\app\outputs\flutter-apk"
    Get-ChildItem $apkDir -Filter "*-$Mode.apk" | ForEach-Object {
        $archName = $_.Name -replace "app-", "" -replace "-$Mode.apk", ""
        $outputName = "mynas-$Version-android-$archName-$Mode.apk"
        $destPath = Join-Path $androidOutputDir $outputName
        Copy-Item $_.FullName $destPath -Force
        Write-Host "[Done] $destPath" -ForegroundColor Green
    }
}

function Build-AndroidUniversal {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] Android Universal APK ($Mode)" -ForegroundColor Green

    flutter build apk $modeFlag

    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $outputName = "mynas-$Version-android-universal-$Mode.apk"
    $sourcePath = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-$Mode.apk"
    $destPath = Join-Path $androidOutputDir $outputName

    Copy-Item $sourcePath $destPath -Force
    Write-Host "[Done] $destPath" -ForegroundColor Green
}

function Build-AndroidAab {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] Android App Bundle ($Mode)" -ForegroundColor Green

    flutter build appbundle $modeFlag

    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $outputName = "mynas-$Version-android-$Mode.aab"
    $sourcePath = Join-Path $ProjectDir "build\app\outputs\bundle\$Mode\app-$Mode.aab"
    $destPath = Join-Path $androidOutputDir $outputName

    Copy-Item $sourcePath $destPath -Force
    Write-Host "[Done] $destPath" -ForegroundColor Green
}

# ============ Windows Build Functions ============

function Build-Windows {
    param(
        [string]$Arch,
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] Windows $Arch ($Mode)" -ForegroundColor Green

    # Note: Flutter Windows arm64 and x86 have limited support
    if ($Arch -eq "x64") {
        flutter build windows $modeFlag
    } elseif ($Arch -eq "arm64") {
        Write-Host "[Warning] Windows ARM64 is experimental" -ForegroundColor Yellow
        flutter build windows $modeFlag --target-platform=windows-arm64
    } else {
        Write-Host "[Warning] Windows x86 has limited support" -ForegroundColor Yellow
        flutter build windows $modeFlag
    }

    $windowsOutputDir = Join-Path $OutputDir "windows"
    New-Item -ItemType Directory -Force -Path $windowsOutputDir | Out-Null

    $modeCapitalized = $Mode.Substring(0,1).ToUpper() + $Mode.Substring(1)
    $buildOutput = Join-Path $ProjectDir "build\windows\$Arch\runner\$modeCapitalized"

    # Fallback to x64 path if arch-specific doesn't exist
    if (-not (Test-Path $buildOutput)) {
        $buildOutput = Join-Path $ProjectDir "build\windows\x64\runner\$modeCapitalized"
    }

    Write-Host "[Done] Output at: $buildOutput" -ForegroundColor Green
}

# ============ macOS Build Functions ============

function Build-MacOS {
    param(
        [string]$Arch,
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] macOS $Arch ($Mode)" -ForegroundColor Green

    # macOS architecture flags
    switch ($Arch) {
        "universal" {
            flutter build macos $modeFlag
        }
        "arm64" {
            flutter build macos $modeFlag --target-platform=darwin-arm64
        }
        "x64" {
            flutter build macos $modeFlag --target-platform=darwin-x64
        }
    }

    $macosOutputDir = Join-Path $OutputDir "macos"
    New-Item -ItemType Directory -Force -Path $macosOutputDir | Out-Null

    $modeCapitalized = $Mode.Substring(0,1).ToUpper() + $Mode.Substring(1)
    $buildOutput = Join-Path $ProjectDir "build\macos\Build\Products\$modeCapitalized"
    Write-Host "[Done] Output at: $buildOutput" -ForegroundColor Green
}

# ============ Linux Build Functions ============

function Build-Linux {
    param(
        [string]$Arch,
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] Linux $Arch ($Mode)" -ForegroundColor Green

    if ($Arch -eq "arm64") {
        Write-Host "[Warning] Linux ARM64 is experimental" -ForegroundColor Yellow
        flutter build linux $modeFlag --target-platform=linux-arm64
    } else {
        flutter build linux $modeFlag
    }

    $linuxOutputDir = Join-Path $OutputDir "linux"
    New-Item -ItemType Directory -Force -Path $linuxOutputDir | Out-Null

    Write-Host "[Done] Output at: build/linux/$Arch/release/bundle/" -ForegroundColor Green
}

# ============ iOS Build Functions ============

function Build-iOS {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[Build] iOS ($Mode)" -ForegroundColor Green

    flutter build ipa $modeFlag --no-codesign

    $iosOutputDir = Join-Path $OutputDir "ios"
    New-Item -ItemType Directory -Force -Path $iosOutputDir | Out-Null

    Write-Host "[Done] Output at: build/ios/ipa/" -ForegroundColor Green
}

# ============ Main ============

# Check if Flutter is available
$flutterPath = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterPath) {
    Write-Host "Error: Flutter is not installed or not in PATH" -ForegroundColor Red
    exit 1
}

# Main loop
while ($true) {
    Clear-Host
    Write-Header
    Show-PlatformMenu

    $platformChoice = Read-Host "Enter option [0-7]"

    switch ($platformChoice) {
        "0" {
            Write-Host "Goodbye!" -ForegroundColor Cyan
            exit 0
        }
        "1" {
            # Android APK by architecture
            Show-AndroidArchMenu
            $archChoice = Read-Host "Enter option [0-4]"

            switch ($archChoice) {
                "0" { continue }
                "1" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-AndroidApk -Arch "arm64-v8a" -Mode $mode
                }
                "2" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-AndroidApk -Arch "armeabi-v7a" -Mode $mode
                }
                "3" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-AndroidApk -Arch "x86_64" -Mode $mode
                }
                "4" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-AndroidAllArchs -Mode $mode
                }
                default {
                    Write-Host "Invalid option" -ForegroundColor Red
                }
            }
        }
        "2" {
            $mode = Select-BuildMode
            Prepare-Build
            Build-AndroidUniversal -Mode $mode
        }
        "3" {
            $mode = Select-BuildMode
            Prepare-Build
            Build-AndroidAab -Mode $mode
        }
        "4" {
            # Windows
            Show-WindowsArchMenu
            $archChoice = Read-Host "Enter option [0-3]"

            switch ($archChoice) {
                "0" { continue }
                "1" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-Windows -Arch "x64" -Mode $mode
                }
                "2" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-Windows -Arch "x86" -Mode $mode
                }
                "3" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-Windows -Arch "arm64" -Mode $mode
                }
                default {
                    Write-Host "Invalid option" -ForegroundColor Red
                }
            }
        }
        "5" {
            # macOS
            if ($env:OS -ne $null) {
                Write-Host "macOS build is only supported on macOS" -ForegroundColor Red
                Read-Host "Press Enter to continue..."
                continue
            }
            Show-MacOSArchMenu
            $archChoice = Read-Host "Enter option [0-3]"

            switch ($archChoice) {
                "0" { continue }
                "1" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-MacOS -Arch "universal" -Mode $mode
                }
                "2" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-MacOS -Arch "arm64" -Mode $mode
                }
                "3" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-MacOS -Arch "x64" -Mode $mode
                }
                default {
                    Write-Host "Invalid option" -ForegroundColor Red
                }
            }
        }
        "6" {
            # Linux
            Show-LinuxArchMenu
            $archChoice = Read-Host "Enter option [0-2]"

            switch ($archChoice) {
                "0" { continue }
                "1" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-Linux -Arch "x64" -Mode $mode
                }
                "2" {
                    $mode = Select-BuildMode
                    Prepare-Build
                    Build-Linux -Arch "arm64" -Mode $mode
                }
                default {
                    Write-Host "Invalid option" -ForegroundColor Red
                }
            }
        }
        "7" {
            # iOS
            if ($env:OS -ne $null) {
                Write-Host "iOS build is only supported on macOS" -ForegroundColor Red
                Read-Host "Press Enter to continue..."
                continue
            }
            $mode = Select-BuildMode
            Prepare-Build
            Build-iOS -Mode $mode
        }
        default {
            Write-Host "Invalid option, please try again" -ForegroundColor Red
        }
    }

    Write-Host ""
    Read-Host "Press Enter to continue..."
}
