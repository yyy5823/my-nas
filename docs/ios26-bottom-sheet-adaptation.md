# iOS 26 底部弹框 Liquid Glass 适配方案

## 概述

iOS 26 引入了 "Liquid Glass" 设计语言，所有使用 `UISheetPresentationController` 的底部弹框会自动获得玻璃效果。本文档列出所有需要适配的底部弹框，并提供统一的适配方案。

## 已有基础设施

### Flutter 层
- `lib/shared/widgets/app_bottom_sheet.dart` - 统一底部弹框入口
  - `showAppBottomSheet()` - 通用底部弹框
  - `showOptionsBottomSheet()` - 选项菜单（已使用原生实现）
- `lib/shared/widgets/adaptive_sheet.dart` - 跨平台自适应弹框

### iOS 原生层
- `ios/Runner/GlassBottomSheet.swift` - 原生弹框实现
  - 使用 `UISheetPresentationController`
  - 支持 iOS 26+ Liquid Glass
  - 支持多种 detent（small/medium/large）
  - MethodChannel: `com.kkape.mynas/glass_bottom_sheet`

## iOS 26 SDK 关键特性

### 自动 Liquid Glass 效果
```swift
// iOS 26+ 底部弹框自动应用 Liquid Glass
if #available(iOS 26.0, *) {
    // 标准 UISheetPresentationController 自动获得玻璃效果
    // 不需要手动设置材质
}
```

### presentationDetents 配置
```swift
// 推荐配置
sheet.detents = [.medium(), .large()]  // 部分高度时显示玻璃效果
sheet.prefersGrabberVisible = true      // 显示拖拽指示器
sheet.prefersEdgeAttachedInCompactHeight = true
sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
```

### 最佳实践
1. **避免自定义背景** - 让系统自动应用 Liquid Glass
2. **使用 partial detent** - `.medium` 或 custom height 更能展示玻璃效果
3. **展开到 `.large` 时** - 背景变为不透明，边缘贴合屏幕

---

## 需要适配的底部弹框清单

### 一、视频模块 (17 个文件)

#### 1. 播放器设置
| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `video_player_settings_page.dart` | 解码器选择、硬件加速设置、音频输出设置 | 中 |
| `playback_settings_sheet.dart` | 播放速度、循环模式 | 高 |
| `quick_settings_sheet.dart` | 快捷设置面板 | 高 |
| `advanced_settings_sheet.dart` | 高级播放设置 | 中 |

#### 2. 字幕相关
| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `subtitle_selector.dart` | 字幕轨道选择 | 高 |
| `subtitle_style_sheet.dart` | 字幕样式设置 | 中 |
| `subtitle_download_dialog.dart` | 字幕下载选项 | 中 |

#### 3. 音轨与画质
| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `audio_track_selector.dart` | 音轨选择 | 高 |
| `quality_selector_sheet.dart` | 画质选择 | 高 |
| `aspect_ratio_selector.dart` | 画面比例选择 | 中 |

#### 4. 其他视频功能
| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `unified_episode_selector.dart` | 剧集选择（3处弹框） | 高 |
| `bookmark_sheet.dart` | 书签管理 | 中 |
| `cast_button.dart` | 投屏设备选择（2处） | 中 |
| `video_category_settings_sheet.dart` | 分类设置 | 低 |
| `video_list_page.dart` | 排序/筛选弹框（8处） | 高 |
| `video_detail_page.dart` | 更多操作弹框（3处） | 中 |
| `tmdb_preview_page.dart` | TMDB 预览操作（2处） | 低 |
| `scraper_sources_page.dart` | 刮削源设置 | 低 |

### 二、音乐模块 (6 个文件)

| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `music_player_page.dart` | 播放器设置 | 高 |
| `music_list_page.dart` | 排序/筛选 | 高 |
| `music_queue_sheet.dart` | 播放队列 | 高 |
| `music_settings_sheet.dart` | 音乐设置 | 中 |
| `home_layout_sheet.dart` | 首页布局设置 | 中 |
| `playlist_detail_page.dart` | 播放列表操作 | 中 |
| `music_scraper_sources_page.dart` | 音乐刮削源 | 低 |

### 三、图书模块 (3 个文件)

| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `online_book_reader_page.dart` | 阅读设置 | 高 |
| `tts_control_bar.dart` | TTS 语音选择 | 中 |
| `book_sources_page.dart` | 书源管理 | 中 |
| `reader_settings_sheet.dart` (shared) | 阅读器设置 | 高 |

### 四、图片模块 (3 个文件)

| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `photo_list_page.dart` | 排序/筛选 | 中 |
| `photo_people_page.dart` | 人物管理 | 低 |
| `photo_viewer_page.dart` | 查看器操作 | 中 |

### 五、漫画模块 (1 个文件)

| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `comic_reader_page.dart` | 漫画阅读设置 | 中 |

### 六、文件与数据源 (6 个文件)

| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `sources_page.dart` | 数据源设置（2处） | 中 |
| `service_sources_page.dart` | 服务源设置（2处） | 中 |
| `media_library_page.dart` | 媒体库设置 | 中 |
| `file_browser_page.dart` | 文件操作菜单 | 中 |
| `two_fa_sheet.dart` | 两步验证（2处） | 高 |

### 七、下载与传输 (4 个文件)

| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `transfer_sheet.dart` | 传输设置 | 中 |
| `target_picker_sheet.dart` | 目标选择 | 中 |
| `transmission_detail_page.dart` | Transmission 详情（4处） | 低 |
| `qbittorrent_detail_page.dart` | qBittorrent 详情 | 低 |
| `aria2_detail_page.dart` | Aria2 详情 | 低 |
| `download_manager_sheet.dart` (shared) | 下载管理 | 中 |

### 八、其他模块 (4 个文件)

| 文件 | 弹框用途 | 优先级 |
|------|----------|--------|
| `mine_page.dart` | 个人中心操作 | 中 |
| `trakt_connection_page.dart` | Trakt 连接 | 低 |
| `nastool_main_page.dart` | NasTool 设置 | 低 |
| `pt_site_detail_page.dart` | PT 站点详情 | 低 |

---

## 适配策略

### 策略一：使用统一入口（推荐）

**适用于**: 简单选项菜单类型的弹框

1. 将 `showModalBottomSheet` 替换为 `showOptionsBottomSheet`
2. 自动使用原生 iOS Sheet（已实现）

```dart
// 之前
showModalBottomSheet(
  context: context,
  builder: (context) => Column(
    children: [
      ListTile(title: Text('选项1'), onTap: ...),
      ListTile(title: Text('选项2'), onTap: ...),
    ],
  ),
);

// 之后
showOptionsBottomSheet(
  context: context,
  title: '选择操作',
  options: [
    OptionItem(icon: Icons.play_arrow, title: '选项1', value: 1),
    OptionItem(icon: Icons.pause, title: '选项2', value: 2),
  ],
);
```

### 策略二：扩展原生 Sheet 类型

**适用于**: 复杂内容弹框（播放器设置、队列管理等）

1. 在 `GlassBottomSheet.swift` 扩展新的 Sheet 类型
2. 添加对应的 MethodChannel 方法
3. 在 Flutter 层添加调用入口

**新增 Sheet 类型**:
- `showNativeSliderSheet` - 滑块设置（速度、音量等）
- `showNativeListSheet` - 列表选择（轨道、字幕等）
- `showNativeFormSheet` - 表单设置（复杂设置页）

### 策略三：保持 Flutter 实现但优化样式

**适用于**: 非常复杂的交互或动态内容

1. 继续使用 `showAppBottomSheet`
2. 在 iOS 26+ 移除自定义背景，让内容透明
3. 使用 `.presentationBackground(.clear)` 类似效果

---

## 实施任务清单

### Phase 1: 高优先级（视频播放器核心）
- [ ] `playback_settings_sheet.dart` - 播放设置
- [ ] `quick_settings_sheet.dart` - 快捷设置
- [ ] `subtitle_selector.dart` - 字幕选择
- [ ] `audio_track_selector.dart` - 音轨选择
- [ ] `quality_selector_sheet.dart` - 画质选择
- [ ] `unified_episode_selector.dart` - 剧集选择

### Phase 2: 高优先级（列表页交互）
- [ ] `video_list_page.dart` - 筛选/排序弹框
- [ ] `music_list_page.dart` - 筛选/排序弹框
- [ ] `music_queue_sheet.dart` - 播放队列
- [ ] `reader_settings_sheet.dart` - 阅读设置

### Phase 3: 中优先级（设置页面）
- [ ] `video_player_settings_page.dart` - 播放器设置
- [ ] `music_settings_sheet.dart` - 音乐设置
- [ ] `subtitle_style_sheet.dart` - 字幕样式
- [ ] `advanced_settings_sheet.dart` - 高级设置
- [ ] `two_fa_sheet.dart` - 两步验证

### Phase 4: 中优先级（其他功能）
- [ ] `video_detail_page.dart` - 视频详情操作
- [ ] `bookmark_sheet.dart` - 书签管理
- [ ] `cast_button.dart` - 投屏选择
- [ ] `sources_page.dart` - 数据源设置
- [ ] `file_browser_page.dart` - 文件操作

### Phase 5: 低优先级
- [ ] `transmission_detail_page.dart`
- [ ] `qbittorrent_detail_page.dart`
- [ ] `aria2_detail_page.dart`
- [ ] `tmdb_preview_page.dart`
- [ ] `scraper_sources_page.dart`
- [ ] `pt_site_detail_page.dart`
- [ ] `nastool_main_page.dart`

---

## 技术实现细节

### iOS 原生扩展示例

```swift
// 在 GlassBottomSheet.swift 添加新类型

/// 滑块设置 Sheet
class SliderSheetViewController: UIViewController {
    private let sliderConfig: SliderConfig
    
    struct SliderConfig {
        let title: String
        let value: Double
        let min: Double
        let max: Double
        let step: Double
        let valueFormatter: (Double) -> String
    }
    
    // iOS 26+ 自动获得 Liquid Glass 效果
    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 26.0, *) {
            // 使用系统提供的玻璃材质
            view.backgroundColor = .clear
        }
    }
}
```

### Flutter MethodChannel 调用

```dart
// 新增调用方法
Future<double?> showNativeSliderSheet({
  required BuildContext context,
  required String title,
  required double value,
  required double min,
  required double max,
  double step = 0.1,
}) async {
  if (!Platform.isIOS) {
    return _showFlutterSliderSheet(...);
  }
  
  return await _channel.invokeMethod('showSliderSheet', {
    'title': title,
    'value': value,
    'min': min,
    'max': max,
    'step': step,
  });
}
```

---

## 验证清单

每个弹框适配后需要验证：
- [ ] iOS 26+ 显示 Liquid Glass 效果
- [ ] iOS 15-25 显示标准 Sheet 样式
- [ ] Android/其他平台显示 Flutter 样式
- [ ] 深色/浅色模式正确
- [ ] 拖拽关闭正常
- [ ] 点击背景关闭正常
- [ ] 回调正确返回选中值

---

## 参考资料

1. [Apple Developer - UISheetPresentationController](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller)
2. [WWDC 2025 - What's new in UIKit](https://developer.apple.com/videos/play/wwdc2025/101/)
3. [Liquid Glass Design Guidelines](https://developer.apple.com/design/human-interface-guidelines/materials)
