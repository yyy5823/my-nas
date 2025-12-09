#!/bin/bash

# iOS 构建修复脚本
# 解决 Xcode 16+ 兼容性问题："Unable to find compatibility version string for object version 70"

set -e

echo "🔧 开始修复 iOS 构建问题..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查 CocoaPods 安装方式
POD_PATH=$(which pod)
echo -e "${BLUE}📍 CocoaPods 路径: $POD_PATH${NC}"

# 1. 更新 CocoaPods
if [[ "$POD_PATH" == *"homebrew"* ]]; then
    echo -e "${YELLOW}🍺 检测到 Homebrew 安装的 CocoaPods，正在更新...${NC}"
    brew update
    brew upgrade cocoapods || echo "CocoaPods 已是最新版本"
else
    echo -e "${YELLOW}💎 更新系统 gem 安装的 CocoaPods...${NC}"
    sudo gem update --system
    sudo gem install cocoapods
    sudo gem install xcodeproj --pre
fi

# 2. 关闭 Xcode
echo -e "${YELLOW}📱 关闭 Xcode...${NC}"
killall Xcode 2>/dev/null || echo "Xcode 未运行"

# 3. 清理 Flutter 构建
echo -e "${YELLOW}🧹 清理 Flutter 构建...${NC}"
flutter clean

# 4. 清理 iOS 相关文件
echo -e "${YELLOW}🗑️  删除 iOS 构建产物...${NC}"
cd ios
rm -rf Pods
rm -rf Podfile.lock
rm -rf .symlinks
rm -rf Flutter/Flutter.framework
rm -rf Flutter/Flutter.podspec

# 5. 清理 Xcode DerivedData
echo -e "${YELLOW}💾 清理 Xcode DerivedData...${NC}"
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# 6. 清理 Xcode 缓存
echo -e "${YELLOW}🗂️  清理 Xcode 缓存...${NC}"
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# 7. 清理 Scheme 配置
echo -e "${YELLOW}⚙️  清理 Scheme 配置...${NC}"
rm -rf Runner.xcworkspace/xcuserdata
rm -rf Runner.xcodeproj/xcuserdata
rm -rf Runner.xcodeproj/xcshareddata/xcschemes

# 8. 返回项目根目录
cd ..

# 9. 重新获取 Flutter 依赖
echo -e "${YELLOW}📦 重新获取 Flutter 依赖...${NC}"
flutter pub get

# 10. 重新安装 Pods
echo -e "${YELLOW}🍎 重新安装 CocoaPods 依赖...${NC}"
cd ios
pod deintegrate 2>/dev/null || echo "跳过 deintegrate"

# 尝试安装，如果失败则提示
if ! pod install --repo-update; then
    echo -e "${RED}❌ pod install 失败${NC}"
    echo -e "${YELLOW}🔄 尝试更新 xcodeproj gem...${NC}"
    
    if [[ "$POD_PATH" == *"homebrew"* ]]; then
        brew reinstall cocoapods
    else
        sudo gem install xcodeproj --pre
    fi
    
    echo -e "${YELLOW}🔄 重试 pod install...${NC}"
    pod install --repo-update
fi

cd ..

echo -e "${GREEN}✅ 修复完成！${NC}"
echo ""
echo -e "${YELLOW}📝 接下来的步骤：${NC}"
echo "1. 打开 Xcode: open ios/Runner.xcworkspace"
echo "2. 在 Xcode 中: Product → Clean Build Folder (⇧⌘K)"
echo "3. 在 Xcode 中: Product → Scheme → Manage Schemes..."
echo "4. 点击 'Autocreate Schemes Now'"
echo "5. 确保 Runner scheme 被选中并勾选 Shared"
echo "6. 运行: Product → Run (⌘R)"
echo ""
echo -e "${GREEN}或者直接运行: flutter run${NC}"

