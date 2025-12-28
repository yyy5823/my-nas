# Android 灵动岛实现文档

## 概述

本项目为 Android 平台实现了类似 iOS 灵动岛的音乐播放控制功能。支持两种实现方式：

1. **华为 Live View Kit** - 适用于华为/荣耀设备（HarmonyOS 4.0+ 或 EMUI 14+）
2. **通用悬浮窗** - 适用于所有 Android 6.0+ 设备

## 架构设计

```
Flutter Layer (Dart)
    └── AndroidDynamicIslandService
            │
            ▼
    MethodChannel ("com.kkape.mynas/dynamic_island")
            │
            ▼
Android Native Layer (Kotlin)
    └── DynamicIslandChannel
            │
            ▼
    DynamicIslandFactory
            │
            ├── HuaweiLiveViewManager (华为设备)
            │       └── Live View Kit SDK
            │
            └── FloatingWindowManager (其他设备)
                    └── WindowManager + 悬浮窗
```

## 文件结构

### Android Native (Kotlin)

```
android/app/src/main/kotlin/com/kkape/mynas/dynamicisland/
├── DynamicIslandData.kt       # 数据模型和回调接口
├── DynamicIslandManager.kt    # 抽象管理器基类
├── DynamicIslandFactory.kt    # 工厂类，选择实现
├── DynamicIslandChannel.kt    # Flutter Method Channel
├── FloatingWindowManager.kt   # 通用悬浮窗实现
└── HuaweiLiveViewManager.kt   # 华为 Live View Kit 实现
```

### Android Resources

```
android/app/src/main/res/
├── layout/
│   └── dynamic_island_floating.xml     # 悬浮窗布局
└── drawable/
    ├── dynamic_island_background.xml   # 收起状态背景
    ├── dynamic_island_background_expanded.xml  # 展开状态背景
    ├── dynamic_island_progress.xml     # 进度条样式
    └── ic_close.xml                    # 关闭图标
```

### Flutter (Dart)

```
lib/features/music/data/services/
└── android_dynamic_island_service.dart  # Flutter 服务类
```

## 使用方法

### 1. 初始化

```dart
final dynamicIsland = AndroidDynamicIslandService();
await dynamicIsland.init();
```

### 2. 检查权限

```dart
if (!dynamicIsland.hasPermission) {
  await dynamicIsland.requestPermission();
}
```

### 3. 显示灵动岛

```dart
await dynamicIsland.startMusicActivity(
  music: currentMusic,
  isPlaying: true,
  position: Duration(seconds: 30),
  duration: Duration(minutes: 3),
  coverData: coverImageBytes,
);
```

### 4. 更新状态

```dart
await dynamicIsland.updateActivity(
  music: currentMusic,
  isPlaying: isPlaying,
  position: currentPosition,
  duration: totalDuration,
);
```

### 5. 处理控制回调

```dart
dynamicIsland.onControlAction = (action) {
  switch (action) {
    case 'playPause':
      togglePlayPause();
      break;
    case 'next':
      playNext();
      break;
    case 'previous':
      playPrevious();
      break;
    case 'dismiss':
      // 用户关闭了灵动岛
      break;
  }
};
```

### 6. 隐藏灵动岛

```dart
await dynamicIsland.endActivity();
```

## 权限配置

### AndroidManifest.xml

已添加悬浮窗权限：

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
```

## 华为 Live View Kit 集成（可选）

如果需要在华为设备上使用原生 Live View Kit：

### 1. 添加华为 Maven 仓库

在 `android/build.gradle` 中添加：

```gradle
allprojects {
    repositories {
        maven { url 'https://developer.huawei.com/repo/' }
    }
}
```

### 2. 添加 SDK 依赖

在 `android/app/build.gradle` 中添加：

```gradle
dependencies {
    implementation 'com.huawei.hms:liveviewkit:x.x.x'
}
```

### 3. 配置 agconnect-services.json

从华为开发者后台下载并放置到 `android/app/` 目录。

### 4. 在华为开发者后台申请 Live View Kit 权限

## 悬浮窗功能特性

### 收起状态（胶囊形态）
- 显示封面缩略图
- 显示歌曲标题（滚动）
- 播放/暂停按钮
- 点击展开

### 展开状态
- 大封面图片
- 歌曲标题和艺术家
- 进度条
- 时间显示
- 上一首/播放暂停/下一首按钮
- 关闭按钮
- 5秒后自动收起

### 交互功能
- 可拖动位置
- 自动吸附到屏幕边缘
- 平滑动画过渡

## 注意事项

1. **悬浮窗权限**：需要用户手动在系统设置中授权
2. **电池优化**：建议将应用加入电池优化白名单
3. **后台运行**：需要配合前台服务使用才能在后台正常显示
4. **华为设备**：如果集成了 Live View Kit SDK，将自动使用原生实现

## 设置项

在 `MusicSettings` 中添加了 `dynamicIslandEnabled` 设置项，可以通过以下方式控制：

```dart
// 获取当前设置
final settings = ref.read(musicSettingsProvider);
final isEnabled = settings.dynamicIslandEnabled;

// 切换设置
ref.read(musicSettingsProvider.notifier).setDynamicIslandEnabled(enabled: !isEnabled);
```

## 集成位置

- `music_player_provider.dart` - 音乐播放器状态管理
  - `_initDynamicIsland()` - 初始化服务和设置回调
  - `_startDynamicIsland()` - 开始播放时显示灵动岛
  - `_updateDynamicIsland()` - 更新播放状态和封面
  - `_hideDynamicIsland()` - 停止播放时隐藏灵动岛
  - `setDynamicIslandEnabled()` - 启用/禁用灵动岛

- `music_settings_provider.dart` - 设置管理
  - `dynamicIslandEnabled` - 是否启用灵动岛
  - `setDynamicIslandEnabled()` - 设置方法

## 后续优化

1. [ ] 添加进度条拖动功能
2. [ ] 添加歌词滚动显示
3. [ ] 添加更多动画效果
4. [ ] 支持 OPPO 流体云（需要等待官方 API 发布）
5. [ ] 支持小米灵动岛（需要等待官方 API 发布）
6. [ ] 在设置页面添加灵动岛开关 UI
