# MyNAS 交互式构建脚本 (PowerShell)
# 支持多平台和多架构构建

$ErrorActionPreference = "Stop"

# 项目根目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$OutputDir = Join-Path $ProjectDir "build\releases"

# 获取版本号
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
    Write-Host "              MyNAS 构建工具 v1.0                                 " -ForegroundColor Cyan
    Write-Host "                  版本: $Version                                  " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-PlatformMenu {
    Write-Host "请选择目标平台:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) Android APK (按架构分包)"
    Write-Host "  2) Android APK (通用包)"
    Write-Host "  3) Android App Bundle (.aab)"
    Write-Host "  4) iOS (.ipa) [仅 macOS]"
    Write-Host "  5) macOS (.app) [仅 macOS]"
    Write-Host "  6) Windows (.exe)"
    Write-Host "  7) Linux"
    Write-Host "  8) 全部 Android 架构"
    Write-Host ""
    Write-Host "  0) 退出"
    Write-Host ""
}

function Show-AndroidArchMenu {
    Write-Host "请选择 Android 架构:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) arm64-v8a (64位 ARM，推荐现代设备)"
    Write-Host "  2) armeabi-v7a (32位 ARM，兼容旧设备)"
    Write-Host "  3) x86_64 (64位 x86，模拟器/特殊设备)"
    Write-Host "  4) 全部架构"
    Write-Host ""
    Write-Host "  0) 返回"
    Write-Host ""
}

function Show-BuildModeMenu {
    Write-Host "请选择构建模式:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) Release (发布版，优化性能)"
    Write-Host "  2) Profile (性能分析版)"
    Write-Host "  3) Debug (调试版)"
    Write-Host ""
}

function Select-BuildMode {
    Show-BuildModeMenu
    $choice = Read-Host "请输入选项 [1-3]"
    switch ($choice) {
        "1" { return "release" }
        "2" { return "profile" }
        "3" { return "debug" }
        default { return "release" }
    }
}

function Prepare-Build {
    Write-Host "[准备] 清理并获取依赖..." -ForegroundColor Blue
    Set-Location $ProjectDir
    flutter clean
    flutter pub get
}

function Build-AndroidApk {
    param(
        [string]$Arch,
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[构建] Android APK - $Arch ($Mode)" -ForegroundColor Green

    $targetPlatform = switch ($Arch) {
        "arm64-v8a" { "android-arm64" }
        "armeabi-v7a" { "android-arm" }
        "x86_64" { "android-x64" }
    }

    flutter build apk $modeFlag --target-platform=$targetPlatform

    # 复制到输出目录
    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $outputName = "mynas-$Version-$Arch-$Mode.apk"
    $sourcePath = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-$Mode.apk"
    $destPath = Join-Path $androidOutputDir $outputName

    Copy-Item $sourcePath $destPath -Force
    Write-Host "[完成] $destPath" -ForegroundColor Green
}

function Build-AndroidAllArchs {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[构建] Android APK - 全部架构 ($Mode)" -ForegroundColor Green

    flutter build apk $modeFlag --split-per-abi

    # 复制到输出目录
    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $apkDir = Join-Path $ProjectDir "build\app\outputs\flutter-apk"
    Get-ChildItem $apkDir -Filter "*-$Mode.apk" | ForEach-Object {
        $archName = $_.Name -replace "app-", "" -replace "-$Mode.apk", ""
        $outputName = "mynas-$Version-$archName-$Mode.apk"
        $destPath = Join-Path $androidOutputDir $outputName
        Copy-Item $_.FullName $destPath -Force
        Write-Host "[完成] $destPath" -ForegroundColor Green
    }
}

function Build-AndroidUniversal {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[构建] Android 通用 APK ($Mode)" -ForegroundColor Green

    flutter build apk $modeFlag

    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $outputName = "mynas-$Version-universal-$Mode.apk"
    $sourcePath = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-$Mode.apk"
    $destPath = Join-Path $androidOutputDir $outputName

    Copy-Item $sourcePath $destPath -Force
    Write-Host "[完成] $destPath" -ForegroundColor Green
}

function Build-AndroidAab {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[构建] Android App Bundle ($Mode)" -ForegroundColor Green

    flutter build appbundle $modeFlag

    $androidOutputDir = Join-Path $OutputDir "android"
    New-Item -ItemType Directory -Force -Path $androidOutputDir | Out-Null

    $outputName = "mynas-$Version-$Mode.aab"
    $sourcePath = Join-Path $ProjectDir "build\app\outputs\bundle\$Mode\app-$Mode.aab"
    $destPath = Join-Path $androidOutputDir $outputName

    Copy-Item $sourcePath $destPath -Force
    Write-Host "[完成] $destPath" -ForegroundColor Green
}

function Build-Windows {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[构建] Windows ($Mode)" -ForegroundColor Green

    flutter build windows $modeFlag

    $windowsOutputDir = Join-Path $OutputDir "windows"
    New-Item -ItemType Directory -Force -Path $windowsOutputDir | Out-Null

    $buildOutput = Join-Path $ProjectDir "build\windows\x64\runner\$($Mode.Substring(0,1).ToUpper() + $Mode.Substring(1))"
    Write-Host "[完成] 请在 $buildOutput 目录查看输出" -ForegroundColor Green
}

function Build-Linux {
    param(
        [string]$Mode
    )

    $modeFlag = "--$Mode"

    Write-Host "[构建] Linux ($Mode)" -ForegroundColor Green

    flutter build linux $modeFlag

    Write-Host "[完成] 请在 build/linux/x64/release/bundle/ 目录查看输出" -ForegroundColor Green
}

# 检查 Flutter 是否可用
$flutterPath = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterPath) {
    Write-Host "错误: Flutter 未安装或不在 PATH 中" -ForegroundColor Red
    exit 1
}

# 主循环
while ($true) {
    Clear-Host
    Write-Header
    Show-PlatformMenu

    $platformChoice = Read-Host "请输入选项 [0-8]"

    switch ($platformChoice) {
        "0" {
            Write-Host "再见!" -ForegroundColor Cyan
            exit 0
        }
        "1" {
            # Android APK 按架构
            Show-AndroidArchMenu
            $archChoice = Read-Host "请输入选项 [0-4]"

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
                    Write-Host "无效选项" -ForegroundColor Red
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
            Write-Host "iOS 构建仅支持 macOS" -ForegroundColor Red
        }
        "5" {
            Write-Host "macOS 构建仅支持 macOS" -ForegroundColor Red
        }
        "6" {
            $mode = Select-BuildMode
            Prepare-Build
            Build-Windows -Mode $mode
        }
        "7" {
            $mode = Select-BuildMode
            Prepare-Build
            Build-Linux -Mode $mode
        }
        "8" {
            $mode = Select-BuildMode
            Prepare-Build
            Build-AndroidAllArchs -Mode $mode
        }
        default {
            Write-Host "无效选项，请重新选择" -ForegroundColor Red
        }
    }

    Write-Host ""
    Read-Host "按回车键继续..."
}
