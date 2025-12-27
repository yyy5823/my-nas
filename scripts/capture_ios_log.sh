#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# My-NAS iOS 日志捕获工具
# 用于捕获和分析 iOS 设备日志，支持多模块过滤
# ═══════════════════════════════════════════════════════════════════════════════

# 检查 bash 版本，推荐使用 brew 安装的 bash 4+
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    # 尝试使用 homebrew 安装的 bash
    if [ -x /opt/homebrew/bin/bash ]; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif [ -x /usr/local/bin/bash ]; then
        exec /usr/local/bin/bash "$0" "$@"
    fi
    # 如果没有新版 bash，继续使用兼容模式
fi

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 脚本目录和日志目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs/ios"
BUNDLE_ID="com.kkape.mynas"

# 创建日志目录
mkdir -p "$LOG_DIR"

# ═══════════════════════════════════════════════════════════════════════════════
# 模块定义 - 使用函数替代关联数组以兼容 bash 3.x
# ═══════════════════════════════════════════════════════════════════════════════

get_module_filter() {
    case "$1" in
        music)
            echo "MediaRemote|NowPlaying|audio_service|MPNowPlaying|AudioSession|AVAudioSession|LiveActivity|DynamicIsland|MediaPlayer|MusicPlayer|audioSession|RemoteCommand|NowPlayingInfo"
            ;;
        video)
            echo "AVPlayer|VideoPlayer|AVKit|AVFoundation|MediaPlayer|PiP|PictureInPicture|videoSession|AVPlayerLayer|AVQueuePlayer|AVAsset"
            ;;
        network)
            echo "NSURLSession|URLSession|HTTP|HTTPS|WebDAV|SMB|NFS|NetworkExtension|Reachability|WiFi|Cellular|Connection|Socket|NetService"
            ;;
        file)
            echo "FileManager|NSFileManager|DocumentPicker|FileProvider|iCloud|Storage|Sandbox|Cache|Documents|FileHandle|FileSystem"
            ;;
        photo)
            echo "PHPhotoLibrary|Photos|ImageIO|CGImage|UIImage|PhotoKit|PhotoAlbum|ImagePicker|PhotosUI|CoreImage"
            ;;
        transfer)
            echo "Download|Upload|DownloadTask|UploadTask|BackgroundURLSession|NSURLDownload|Progress|Transfer|DataTask"
            ;;
        notification)
            echo "UserNotification|UNNotification|RemoteNotification|PushNotification|APNs|NotificationCenter|LocalNotification"
            ;;
        background)
            echo "BackgroundTask|BGTask|BGAppRefreshTask|BackgroundFetch|BackgroundProcessing|BackgroundExecution|taskExpired"
            ;;
        error)
            echo "Error|Exception|Crash|Fatal|Assert|NSException|CrashReport|abort|SIGABRT|SIGSEGV|fault"
            ;;
        performance)
            echo "Memory|CPU|Jetsam|lowMemory|MemoryPressure|thermal|performanceProfile|slowPath|hang"
            ;;
        ui)
            echo "UIKit|UIView|UIViewController|UIWindow|UIApplication|viewDidLoad|viewWillAppear|layoutSubviews|constraints"
            ;;
        flutter)
            echo "Flutter|flutter|Runner|io.flutter|FlutterEngine|FlutterViewController|MethodChannel|platform_channel"
            ;;
        bluetooth)
            echo "CoreBluetooth|CBCentralManager|CBPeripheral|Bluetooth|BLE|GATT"
            ;;
        database)
            echo "SQLite|CoreData|sqflite|Database|Realm|FMDB|sqlite3"
            ;;
        all)
            echo "$BUNDLE_ID|Runner|mynas"
            ;;
        *)
            echo ""
            ;;
    esac
}

get_module_description() {
    case "$1" in
        music) echo "🎵 音乐/音频 (MediaRemote, NowPlaying, AudioSession)" ;;
        video) echo "🎬 视频播放 (AVPlayer, PiP, AVFoundation)" ;;
        network) echo "🌐 网络/连接 (URLSession, SMB, WebDAV)" ;;
        file) echo "📁 文件/存储 (FileManager, iCloud, Documents)" ;;
        photo) echo "📷 图片/相册 (PhotoKit, PHPhotoLibrary)" ;;
        transfer) echo "📥 下载/传输 (DownloadTask, BackgroundSession)" ;;
        notification) echo "🔔 通知 (UNNotification, APNs)" ;;
        background) echo "⏳ 后台任务 (BGTask, BackgroundFetch)" ;;
        error) echo "❌ 错误/崩溃 (Exception, Crash, Error)" ;;
        performance) echo "📊 性能 (Memory, CPU, Jetsam)" ;;
        ui) echo "🖼️  界面 (UIKit, UIView, ViewController)" ;;
        flutter) echo "💙 Flutter (FlutterEngine, MethodChannel)" ;;
        bluetooth) echo "📶 蓝牙 (CoreBluetooth, BLE)" ;;
        database) echo "💾 数据库 (SQLite, CoreData)" ;;
        all) echo "📋 全量 (仅过滤 App 相关日志)" ;;
        *) echo "" ;;
    esac
}

get_module_emoji() {
    case "$1" in
        music) echo "🎵" ;;
        video) echo "🎬" ;;
        network) echo "🌐" ;;
        file) echo "📁" ;;
        photo) echo "📷" ;;
        transfer) echo "📥" ;;
        notification) echo "🔔" ;;
        background) echo "⏳" ;;
        error) echo "❌" ;;
        performance) echo "📊" ;;
        ui) echo "🖼️" ;;
        flutter) echo "💙" ;;
        bluetooth) echo "📶" ;;
        database) echo "💾" ;;
        all) echo "📋" ;;
        custom) echo "✏️" ;;
        multi) echo "🔀" ;;
        combined) echo "📦" ;;
        *) echo "📄" ;;
    esac
}

# 模块列表
ALL_MODULES="music video network file photo transfer notification background error performance ui flutter bluetooth database all"

get_module_by_number() {
    local num=$1
    local i=1
    for mod in $ALL_MODULES; do
        if [ "$i" -eq "$num" ]; then
            echo "$mod"
            return
        fi
        i=$((i + 1))
    done
    if [ "$num" -eq 16 ]; then
        echo "custom"
    elif [ "$num" -eq 17 ]; then
        echo "multi"
    fi
}

# 合并多个模块的过滤器
combine_filters() {
    local combined=""
    for module in "$@"; do
        local filter=$(get_module_filter "$module")
        if [ -n "$filter" ]; then
            if [ -n "$combined" ]; then
                combined="${combined}|${filter}"
            else
                combined="$filter"
            fi
        fi
    done
    echo "$combined"
}

# 生成所有模块合并的过滤器
get_all_modules_filter() {
    local combined=""
    for module in $ALL_MODULES; do
        if [ "$module" != "all" ]; then
            local filter=$(get_module_filter "$module")
            if [ -n "$filter" ]; then
                if [ -n "$combined" ]; then
                    combined="${combined}|${filter}"
                else
                    combined="$filter"
                fi
            fi
        fi
    done
    echo "$combined"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 辅助函数
# ═══════════════════════════════════════════════════════════════════════════════

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      🍎 My-NAS iOS 日志捕获工具                               ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_separator() {
    echo -e "${BLUE}───────────────────────────────────────────────────────────────────────────────${NC}"
}

check_dependencies() {
    echo -e "${YELLOW}检查依赖...${NC}"
    
    if ! command -v idevicesyslog &> /dev/null; then
        echo -e "${RED}错误: 未找到 idevicesyslog${NC}"
        echo -e "${YELLOW}请安装 libimobiledevice: brew install libimobiledevice${NC}"
        exit 1
    fi
    
    if ! command -v idevice_id &> /dev/null; then
        echo -e "${RED}错误: 未找到 idevice_id${NC}"
        echo -e "${YELLOW}请安装 libimobiledevice: brew install libimobiledevice${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 依赖检查通过${NC}"
}

check_device() {
    echo -e "${YELLOW}检查设备连接...${NC}"
    
    DEVICE_ID=$(idevice_id -l 2>/dev/null | head -1)
    
    if [ -z "$DEVICE_ID" ]; then
        echo -e "${RED}错误: 未检测到 iOS 设备${NC}"
        echo -e "${YELLOW}请确保:${NC}"
        echo "  1. iPhone 已通过 USB 连接到 Mac"
        echo "  2. iPhone 已解锁并信任此电脑"
        echo "  3. 如果是首次连接，请在 iPhone 上点击 '信任'"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 已连接设备: ${BOLD}$DEVICE_ID${NC}"
}

show_module_menu() {
    echo ""
    echo -e "${BOLD}可用的日志模块:${NC}"
    print_separator
    local i=1
    for module in $ALL_MODULES; do
        local desc=$(get_module_description "$module")
        printf "${CYAN}%3d)${NC} %-12s - %s\n" "$i" "$module" "$desc"
        i=$((i + 1))
    done
    echo -e "${CYAN} 16)${NC} custom       - ✏️  自定义过滤关键词"
    echo -e "${CYAN} 17)${NC} multi        - 🔀 多模块同时捕获"
    print_separator
    echo -e "${CYAN}  0)${NC} 返回"
    echo ""
}

capture_logs() {
    local module=$1
    local filter=$2
    # 固定文件名，不带时间戳，每次运行会覆盖
    local output_file="$LOG_DIR/${module}.log"
    local emoji=$(get_module_emoji "$module")
    
    # 清空/创建文件（覆盖模式）
    > "$output_file"
    
    echo ""
    print_separator
    echo -e "${GREEN}${emoji} 开始捕获 ${BOLD}$module${NC}${GREEN} 模块日志...${NC}"
    echo -e "${YELLOW}过滤关键词:${NC} ${filter:0:80}..."
    echo -e "${YELLOW}输出文件:${NC} $output_file"
    echo -e "${MAGENTA}注意: 此次运行将覆盖之前的日志文件${NC}"
    print_separator
    echo -e "${CYAN}提示: 按 ${BOLD}Ctrl+C${NC}${CYAN} 停止捕获${NC}"
    echo ""
    
    # 捕获日志
    idevicesyslog 2>/dev/null | grep -iE "($filter)" | while read -r line; do
        echo "$line" | tee -a "$output_file"
    done
    
    echo ""
    print_separator
    echo -e "${GREEN}✓ 日志已保存到: ${BOLD}$output_file${NC}"
    
    # 统计日志行数
    if [ -f "$output_file" ]; then
        local line_count=$(wc -l < "$output_file")
        echo -e "${YELLOW}总共捕获: ${BOLD}$line_count${NC}${YELLOW} 条日志${NC}"
    fi
}

# 仅捕获应用日志（只匹配 Runner 进程的日志行）
capture_app_only_logs() {
    local output_file="$LOG_DIR/app_only.log"
    
    # 清空/创建文件（覆盖模式）
    > "$output_file"
    
    echo ""
    print_separator
    echo -e "${GREEN}📱 开始捕获 ${BOLD}应用日志${NC}${GREEN}...${NC}"
    echo -e "${YELLOW}过滤规则:${NC} 仅 Runner 进程日志（排除系统日志）"
    echo -e "${YELLOW}输出文件:${NC} $output_file"
    echo -e "${MAGENTA}注意: 此次运行将覆盖之前的日志文件${NC}"
    print_separator
    echo -e "${CYAN}提示: 按 ${BOLD}Ctrl+C${NC}${CYAN} 停止捕获${NC}"
    echo ""
    
    # 仅捕获以 "Runner" 开头的日志行（即 Runner 进程产生的日志）
    # 格式: Dec 27 19:08:34.252035 Runner(UIKitCore)[40007] <Notice>: ...
    idevicesyslog 2>/dev/null | grep -E "^[A-Za-z]+ [0-9]+ [0-9:.]+[[:space:]]+Runner" | while read -r line; do
        echo "$line" | tee -a "$output_file"
    done
    
    echo ""
    print_separator
    echo -e "${GREEN}✓ 日志已保存到: ${BOLD}$output_file${NC}"
    
    # 统计日志行数
    if [ -f "$output_file" ]; then
        local line_count=$(wc -l < "$output_file")
        echo -e "${YELLOW}总共捕获: ${BOLD}$line_count${NC}${YELLOW} 条日志${NC}"
    fi
}

# 多模块选择
select_multiple_modules() {
    echo ""
    echo -e "${BOLD}选择要同时捕获的模块 (输入编号，用空格或逗号分隔):${NC}"
    print_separator
    local i=1
    for module in $ALL_MODULES; do
        if [ "$module" != "all" ]; then
            local desc=$(get_module_description "$module")
            printf "${CYAN}%3d)${NC} %-12s - %s\n" "$i" "$module" "$desc"
        fi
        i=$((i + 1))
    done
    print_separator
    echo -e "${MAGENTA}提示: 输入 'all' 捕获所有模块, 或输入如 '1 2 3' 或 '1,2,3'${NC}"
    echo ""
    echo -n "请选择: "
    read -r selection
    
    # 处理 all 输入
    if [ "$selection" = "all" ] || [ "$selection" = "ALL" ]; then
        local all_filter=$(get_all_modules_filter)
        capture_logs "combined_all" "$all_filter"
        return
    fi
    
    # 替换逗号为空格
    selection=$(echo "$selection" | tr ',' ' ')
    
    local selected_modules=""
    for num in $selection; do
        if echo "$num" | grep -qE '^[0-9]+$'; then
            local mod=$(get_module_by_number "$num")
            if [ -n "$mod" ] && [ "$mod" != "all" ]; then
                if [ -n "$selected_modules" ]; then
                    selected_modules="$selected_modules $mod"
                else
                    selected_modules="$mod"
                fi
            fi
        fi
    done
    
    if [ -z "$selected_modules" ]; then
        echo -e "${RED}未选择任何有效模块${NC}"
        return
    fi
    
    echo -e "${GREEN}已选择模块: $selected_modules${NC}"
    
    local combined_filter=$(combine_filters $selected_modules)
    local module_name=$(echo "$selected_modules" | tr ' ' '_')
    
    capture_logs "$module_name" "$combined_filter"
}

view_recent_logs() {
    echo ""
    echo -e "${BOLD}最近的日志文件:${NC}"
    print_separator
    
    if [ -d "$LOG_DIR" ] && [ "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
        ls -lt "$LOG_DIR"/*.log 2>/dev/null | head -10
    else
        echo -e "${YELLOW}  暂无日志文件${NC}"
    fi
    
    print_separator
}

analyze_log() {
    echo ""
    echo -e "${BOLD}选择要分析的日志文件:${NC}"
    print_separator
    
    if [ ! -d "$LOG_DIR" ] || [ -z "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}  暂无日志文件${NC}"
        return
    fi
    
    local i=1
    local files=""
    while IFS= read -r file; do
        local basename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        local lines=$(wc -l < "$file")
        echo -e "${CYAN}  $i)${NC} $basename (${size}, ${lines} 行)"
        files="$files$file|"
        i=$((i + 1))
    done < <(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -10)
    
    if [ -z "$files" ]; then
        echo -e "${YELLOW}  暂无日志文件${NC}"
        return
    fi
    
    print_separator
    echo -n "请选择文件编号 (或输入 0 返回): "
    read -r choice
    
    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        return
    fi
    
    local selected_file=$(echo "$files" | cut -d'|' -f"$choice")
    
    if [ -n "$selected_file" ] && [ -f "$selected_file" ]; then
        echo ""
        echo -e "${GREEN}正在分析: $(basename "$selected_file")${NC}"
        print_separator
        
        echo -e "${BOLD}日志统计:${NC}"
        echo "  总行数: $(wc -l < "$selected_file")"
        echo "  错误数: $(grep -ci "error" "$selected_file" 2>/dev/null || echo 0)"
        echo "  警告数: $(grep -ci "warning" "$selected_file" 2>/dev/null || echo 0)"
        echo "  崩溃数: $(grep -ci "crash\|exception" "$selected_file" 2>/dev/null || echo 0)"
        
        echo ""
        echo -e "${BOLD}查看选项:${NC}"
        echo "  1) 查看完整日志"
        echo "  2) 查看最后 50 行"
        echo "  3) 查看错误日志"
        echo "  4) 在编辑器中打开"
        echo "  0) 返回"
        
        echo -n "请选择: "
        read -r view_choice
        
        case $view_choice in
            1) less "$selected_file" ;;
            2) tail -50 "$selected_file" ;;
            3) grep -i "error\|exception\|crash" "$selected_file" | less ;;
            4) open "$selected_file" ;;
        esac
    else
        echo -e "${RED}无效的选择${NC}"
    fi
}

cleanup_logs() {
    echo ""
    echo -e "${YELLOW}清理日志文件...${NC}"
    print_separator
    
    if [ -d "$LOG_DIR" ] && [ "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
        local count=$(ls -1 "$LOG_DIR"/*.log 2>/dev/null | wc -l)
        echo "当前有 $count 个日志文件"
        echo ""
        echo "  1) 删除 7 天前的日志"
        echo "  2) 删除所有日志"
        echo "  0) 取消"
        echo ""
        echo -n "请选择: "
        read -r choice
        
        case $choice in
            1)
                find "$LOG_DIR" -name "*.log" -mtime +7 -delete
                echo -e "${GREEN}✓ 已删除 7 天前的日志${NC}"
                ;;
            2)
                echo -n "确认删除所有日志? (y/N): "
                read -r confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    rm -f "$LOG_DIR"/*.log
                    echo -e "${GREEN}✓ 已删除所有日志${NC}"
                fi
                ;;
        esac
    else
        echo -e "${YELLOW}  暂无日志文件${NC}"
    fi
}

show_help() {
    echo "用法: $0 [选项] [模块名...]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示帮助信息"
    echo "  -l, --list              列出可用模块"
    echo "  -m, --module <模块>     指定单个模块直接开始捕获"
    echo "  -a, --all-modules       捕获所有模块日志（系统+App 混合）"
    echo "  -app, --app-only        仅捕获应用日志（Runner 进程）"
    echo "  -c, --combined <模块>   多模块组合捕获（用逗号分隔）"
    echo ""
    echo "模块列表:"
    for module in $ALL_MODULES; do
        echo "  $(get_module_emoji "$module") $module"
    done
    echo ""
    echo "示例:"
    echo "  $0                          # 交互式模式"
    echo "  $0 music                    # 直接捕获音乐模块日志"
    echo "  $0 -m video                 # 直接捕获视频模块日志"
    echo "  $0 -a                       # 捕获所有模块日志（系统+App）"
    echo "  $0 -app                     # 仅捕获应用日志"
    echo "  $0 --app-only               # 仅捕获应用日志"
    echo "  $0 -c music,video,network   # 同时捕获音乐、视频、网络模块"
    echo "  $0 music video network      # 同时捕获多个模块（空格分隔）"
    echo "  $0 -l                       # 列出所有可用模块"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主程序
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    clear
    print_banner
    
    # 检查依赖和设备
    check_dependencies
    check_device
    
    while true; do
        echo ""
        echo -e "${BOLD}主菜单:${NC}"
        print_separator
        echo -e "${CYAN}  1)${NC} 📱 捕获单个模块日志"
        echo -e "${CYAN}  2)${NC} 🔀 捕获多模块日志 (组合)"
        echo -e "${CYAN}  3)${NC} 📦 捕获所有模块日志"
        echo -e "${CYAN}  4)${NC} 📂 查看最近日志"
        echo -e "${CYAN}  5)${NC} 🔍 分析日志文件"
        echo -e "${CYAN}  6)${NC} 🧹 清理日志文件"
        print_separator
        echo -e "${CYAN}  0)${NC} 退出"
        echo ""
        echo -n "请选择操作: "
        read -r main_choice
        
        case $main_choice in
            1)
                show_module_menu
                echo -n "请选择模块 (输入编号或模块名): "
                read -r module_input
                
                # 检查是否为数字
                if echo "$module_input" | grep -qE '^[0-9]+$'; then
                    if [ "$module_input" = "0" ]; then
                        continue
                    fi
                    module=$(get_module_by_number "$module_input")
                else
                    module="$module_input"
                fi
                
                if [ -z "$module" ]; then
                    echo -e "${RED}无效的选择${NC}"
                    continue
                fi
                
                if [ "$module" = "custom" ]; then
                    echo -n "请输入自定义过滤关键词 (用 | 分隔): "
                    read -r custom_filter
                    if [ -n "$custom_filter" ]; then
                        capture_logs "custom" "$custom_filter"
                    fi
                elif [ "$module" = "multi" ]; then
                    select_multiple_modules
                else
                    local filter=$(get_module_filter "$module")
                    if [ -n "$filter" ]; then
                        capture_logs "$module" "$filter"
                    else
                        echo -e "${RED}未知模块: $module${NC}"
                    fi
                fi
                ;;
            2)
                select_multiple_modules
                ;;
            3)
                echo -e "${GREEN}📦 捕获所有模块日志...${NC}"
                local all_filter=$(get_all_modules_filter)
                capture_logs "combined_all" "$all_filter"
                ;;
            4)
                view_recent_logs
                ;;
            5)
                analyze_log
                ;;
            6)
                cleanup_logs
                ;;
            0)
                echo -e "${GREEN}再见! 👋${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# 命令行模式支持
# ═══════════════════════════════════════════════════════════════════════════════

if [ $# -gt 0 ]; then
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            echo "可用模块:"
            for module in $ALL_MODULES; do
                echo "  $(get_module_emoji "$module") $module - $(get_module_description "$module")"
            done
            exit 0
            ;;
        -a|--all-modules)
            # 捕获所有模块日志（系统+App 混合）
            check_dependencies
            check_device
            echo -e "${GREEN}📦 捕获所有模块日志（系统+App 混合）...${NC}"
            all_filter=$(get_all_modules_filter)
            capture_logs "combined_all" "$all_filter"
            exit 0
            ;;
        -app|--app-only)
            # 仅捕获应用日志（Runner 进程）
            check_dependencies
            check_device
            echo -e "${GREEN}📱 仅捕获应用日志（Runner 进程）...${NC}"
            # 只匹配以 Runner 开头的日志行
            capture_app_only_logs
            exit 0
            ;;
        -c|--combined)
            # 多模块组合捕获
            if [ -n "$2" ]; then
                check_dependencies
                check_device
                # 解析逗号分隔的模块列表
                modules_str=$(echo "$2" | tr ',' ' ')
                combined_filter=$(combine_filters $modules_str)
                if [ -n "$combined_filter" ]; then
                    module_name=$(echo "$modules_str" | tr ' ' '_')
                    capture_logs "$module_name" "$combined_filter"
                else
                    echo -e "${RED}错误: 无效的模块组合${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}错误: 请指定模块列表，如 -c music,video,network${NC}"
                exit 1
            fi
            exit 0
            ;;
        -m|--module)
            if [ -n "$2" ]; then
                check_dependencies
                check_device
                module="$2"
                filter=$(get_module_filter "$module")
                if [ -n "$filter" ]; then
                    capture_logs "$module" "$filter"
                else
                    echo -e "${RED}未知模块: $module${NC}"
                    echo "使用 '$0 -l' 查看可用模块"
                    exit 1
                fi
            else
                echo -e "${RED}错误: 请指定模块名${NC}"
                exit 1
            fi
            exit 0
            ;;
        -*)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            exit 1
            ;;
        *)
            # 支持直接传入一个或多个模块名
            check_dependencies
            check_device
            
            if [ $# -eq 1 ]; then
                # 单个模块
                module="$1"
                filter=$(get_module_filter "$module")
                if [ -n "$filter" ]; then
                    capture_logs "$module" "$filter"
                else
                    echo -e "${RED}未知模块: $module${NC}"
                    echo "使用 '$0 -l' 查看可用模块"
                    exit 1
                fi
            else
                # 多个模块
                valid_modules=""
                for mod in "$@"; do
                    filter=$(get_module_filter "$mod")
                    if [ -n "$filter" ]; then
                        if [ -n "$valid_modules" ]; then
                            valid_modules="$valid_modules $mod"
                        else
                            valid_modules="$mod"
                        fi
                    else
                        echo -e "${YELLOW}警告: 忽略未知模块 '$mod'${NC}"
                    fi
                done
                
                if [ -z "$valid_modules" ]; then
                    echo -e "${RED}错误: 没有有效的模块${NC}"
                    exit 1
                fi
                
                echo -e "${GREEN}捕获模块: $valid_modules${NC}"
                combined_filter=$(combine_filters $valid_modules)
                module_name=$(echo "$valid_modules" | tr ' ' '_')
                capture_logs "$module_name" "$combined_filter"
            fi
            exit 0
            ;;
    esac
fi

# 运行主程序
main
