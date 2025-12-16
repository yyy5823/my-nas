#!/bin/bash

# 替换为你的 Bundle ID
BUNDLE_ID="com.kkape.mynas"

echo "正在清理 $BUNDLE_ID 的本地数据..."
rm -rf ~/Library/Containers/$BUNDLE_ID
rm -rf ~/Library/Application\ Support/$BUNDLE_ID

echo "开始全新的 Flutter 运行..."
flutter run -d macos 2>&1 | tee macos.log
