# 桌面歌词功能重构规划

## 一、当前问题分析

### 1.1 Windows 平台问题

**症状**：
- 打开桌面歌词会导致应用闪退
- 在播放器页面点击"更多"按钮直接闪退

**问题根因**（`desktop_lyric_service_windows_native.dart`）：

1. **Win32 FFI 调用不稳定**
   - 窗口过程 `_wndProc` 通过 `Pointer.fromFunction` 传递，在某些情况下会崩溃
   - FFI 函数缓存类 `_Win32Functions` 在首次调用时可能因 DLL 加载失败而崩溃

2. **内存管理问题**
   - `toNativeUtf16()` 分配的内存在异常路径上可能未释放
   - `calloc<RECT>()` 等分配在 early return 时未清理

3. **消息循环冲突**
   - 每 50ms 的定时器调用 `_processMessages()` 与 Flutter 事件循环可能冲突
   - `PeekMessage` 和 `DispatchMessage` 在主线程执行可能阻塞 UI

4. **GDI 资源泄漏**
   - 字体、画刷、区域等 GDI 对象在异常时未正确释放
   - 长时间运行后可能耗尽 GDI 句柄

5. **Provider 初始化崩溃**
   - `desktopLyricProvider` 在 `_init()` 中调用 Win32 API
   - `music_settings_sheet.dart` 第 364-367 行 watch 这些 provider
   - 如果初始化失败，整个设置面板无法显示

### 1.2 macOS 平台问题

**症状**：
- 打开桌面歌词后没有任何歌词显示
- 窗口可能存在但内容为空

**问题根因**（`DesktopLyricController.swift` 和 `DesktopLyricChannel.swift`）：

1. **窗口层级问题**
   - `window?.makeKeyAndOrderFront(nil)` 可能被其他窗口遮挡
   - 窗口 level 设置为 `.floating` 可能不够高

2. **内容视图布局问题**
   - `DesktopLyricView` 的标签位置计算基于 `bounds`，但视图可能未正确设置大小
   - `centerY = bounds.height / 2` 在窗口高度为 120 时可能导致文字被裁剪

3. **毛玻璃效果遮挡**
   - `NSVisualEffectView` 添加在 `contentView` 下层，但可能覆盖了标签
   - `addSubview(visualEffectView, positioned: .below, relativeTo: nil)` 的行为可能与预期不符

4. **插件注册问题**
   - `DesktopLyricChannel` 可能未在 `AppDelegate.swift` 中正确注册
   - Method Channel 名称可能不匹配

5. **颜色解析问题**
   - `DesktopLyricSettings.fromJson()` 中颜色解析逻辑可能错误
   - ARGB vs RGBA 格式可能不一致

---

## 二、技术方案对比

### 方案 A: 使用 window_manager 包

**描述**：使用成熟的 [window_manager](https://pub.dev/packages/window_manager) 包创建独立窗口

**优点**：
- ✅ 成熟稳定，被 RustDesk、Biyi 等知名应用使用
- ✅ 跨平台一致的 API
- ✅ 支持 `setAlwaysOnTop`、`setIgnoreMouseEvents` 等功能
- ✅ 活跃维护（迁移到 nativeapi-flutter）

**缺点**：
- ❌ 需要创建完整的 Flutter 窗口，资源占用较高
- ❌ 透明窗口支持有限（需要额外配置）
- ❌ 窗口管理与主窗口独立，通信需要额外处理

### 方案 B: 使用 Flutter 多窗口

**描述**：使用 Flutter 3.10+ 的原生多窗口支持

**优点**：
- ✅ 纯 Dart 实现，无需平台代码
- ✅ 与主应用共享状态（Riverpod）
- ✅ 可以使用现有的 Flutter UI 组件

**缺点**：
- ❌ 实验性功能，API 可能变化
- ❌ 透明背景支持有限
- ❌ 桌面端多窗口仍在完善中

### 方案 C: 修复现有实现

**描述**：保持现有架构，逐一修复问题

**优点**：
- ✅ 改动最小
- ✅ 保持现有的性能优化（Win32 原生绘制）

**缺点**：
- ❌ Win32 FFI 复杂度高，难以完全稳定
- ❌ 需要深入了解两个平台的原生 API
- ❌ 维护成本高

### 方案 D: 混合方案（推荐）

**描述**：
- Windows：使用 `window_manager` 创建窗口 + 自定义渲染
- macOS：修复现有 Method Channel 方案

**优点**：
- ✅ Windows 使用成熟方案，稳定性有保障
- ✅ macOS 保持原生体验，仅修复 bug
- ✅ 渐进式改进，降低风险

**缺点**：
- ❌ 两个平台实现不一致
- ❌ 需要同时维护两套代码

---

## 三、推荐方案详细设计

### 采用方案 D：混合方案

### 3.1 Windows 平台重构

#### 3.1.1 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    DesktopLyricProvider                     │
│                   (Riverpod StateNotifier)                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────┐    ┌─────────────────────────┐    │
│  │ WindowsLyricService │    │  MacOSLyricService      │    │
│  │                     │    │  (现有 MethodChannel)   │    │
│  │ - window_manager    │    │                         │    │
│  │ - 独立 Flutter 窗口  │    └─────────────────────────┘    │
│  └─────────────────────┘                                    │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────────┐                                    │
│  │ DesktopLyricWindow  │ ◄── 独立窗口路由                   │
│  │ (纯 Flutter Widget) │                                    │
│  │                     │                                    │
│  │ - 透明背景          │                                    │
│  │ - 圆角卡片          │                                    │
│  │ - 卡拉OK渲染        │                                    │
│  │ - 拖拽支持          │                                    │
│  └─────────────────────┘                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 3.1.2 核心实现

**a) 创建独立窗口服务**

```dart
// lib/features/music/data/services/desktop_lyric_service_windows.dart
class DesktopLyricServiceWindowsImpl implements DesktopLyricService {
  WindowController? _windowController;

  @override
  Future<void> show() async {
    if (_windowController != null) {
      await _windowController!.show();
      return;
    }

    // 创建新窗口
    _windowController = await DesktopMultiWindow.createWindow(jsonEncode({
      'route': '/desktop_lyric',
      'settings': _settings.toJson(),
    }));

    await _windowController!.setFrame(Rect.fromLTWH(
      _settings.windowX ?? _getDefaultX(),
      _settings.windowY ?? _getDefaultY(),
      _settings.windowWidth,
      _settings.windowHeight,
    ));

    // 设置窗口属性
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);

    // Windows 特定：透明窗口
    // 需要在 runner/flutter_window.cpp 中配置
  }
}
```

**b) 歌词窗口 Widget**

```dart
// lib/features/music/presentation/pages/desktop_lyric_window.dart
class DesktopLyricWindow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(desktopLyricWindowProvider);

    return GestureDetector(
      onPanUpdate: (details) => _handleDrag(details),
      child: Container(
        decoration: BoxDecoration(
          color: lyricState.settings.backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 当前歌词（卡拉OK效果）
            KaraokeLyricLine(
              text: lyricState.currentLyric ?? '',
              progress: lyricState.progress,
              textColor: lyricState.settings.textColor,
              highlightColor: lyricState.settings.highlightColor,
              fontSize: lyricState.settings.fontSize,
            ),
            // 翻译
            if (lyricState.showTranslation && lyricState.translation != null)
              Text(lyricState.translation!, ...),
            // 下一行
            if (lyricState.showNextLine && lyricState.nextLyric != null)
              Text(lyricState.nextLyric!, ...),
          ],
        ),
      ),
    );
  }
}
```

**c) Windows 透明窗口配置**

需要修改 `windows/runner/flutter_window.cpp`：

```cpp
bool FlutterWindow::Create(const wchar_t* title) {
  // 添加透明窗口支持
  DWORD ex_style = WS_EX_LAYERED;
  // ... 创建窗口代码
  SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA);
}
```

#### 3.1.3 窗口间通信

使用 `desktop_multi_window` 包的消息机制：

```dart
// 主窗口 -> 歌词窗口
DesktopMultiWindow.invokeMethod(
  _windowController!.windowId,
  'updateLyric',
  {
    'currentLine': currentLine.toJson(),
    'nextLine': nextLine?.toJson(),
    'progress': progress,
  },
);

// 歌词窗口监听
DesktopMultiWindow.setMethodHandler((call) async {
  switch (call.method) {
    case 'updateLyric':
      _updateLyricFromMessage(call.arguments);
      break;
    // ...
  }
});
```

### 3.2 macOS 平台修复

#### 3.2.1 问题修复清单

| 问题 | 修复方案 | 文件 |
|------|----------|------|
| 窗口不可见 | 提高窗口 level 到 `.screenSaver` | DesktopLyricController.swift:140-145 |
| 文字被裁剪 | 修正 Y 坐标计算，使用 AutoLayout | DesktopLyricView:276-315 |
| 毛玻璃遮挡 | 确保标签在 visualEffectView 上方 | DesktopLyricController.swift:113-126 |
| 颜色解析错误 | 修正 ARGB 解析顺序 | DesktopLyricSettings:163-179 |
| 插件未注册 | 在 AppDelegate 中注册 | AppDelegate.swift |

#### 3.2.2 关键代码修复

**a) 修复窗口层级**

```swift
// DesktopLyricController.swift
private func updateWindowLevel() {
    if settings.alwaysOnTop {
        // 使用更高的层级确保可见
        window?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow) - 1))
    } else {
        window?.level = .floating
    }
}
```

**b) 修复视图布局**

```swift
// DesktopLyricView.swift
private func updateLayout() {
    let padding: CGFloat = 24
    let spacing: CGFloat = 4

    // 计算所有可见元素的总高度
    var totalHeight: CGFloat = settings.fontSize + 4  // 当前歌词
    if settings.showTranslation {
        totalHeight += settings.fontSize * 0.7 + spacing
    }
    if settings.showNextLine {
        totalHeight += settings.fontSize * 0.6 + spacing
    }

    // 从顶部开始布局（垂直居中）
    var yPos = (bounds.height - totalHeight) / 2 + totalHeight

    // 当前歌词
    yPos -= settings.fontSize + 4
    currentLyricLabel.frame = NSRect(
        x: padding,
        y: yPos,
        width: bounds.width - padding * 2,
        height: settings.fontSize + 4
    )

    // ... 其他标签
}
```

**c) 修复毛玻璃层次**

```swift
// DesktopLyricController.swift
private func addVisualEffectView() {
    guard let window = window else { return }

    // 创建一个容器视图
    let containerView = NSView(frame: window.contentView!.bounds)
    containerView.autoresizingMask = [.width, .height]

    // 毛玻璃在最底层
    let visualEffectView = NSVisualEffectView(frame: containerView.bounds)
    visualEffectView.material = .hudWindow
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.state = .active
    visualEffectView.wantsLayer = true
    visualEffectView.layer?.cornerRadius = 12
    visualEffectView.layer?.masksToBounds = true
    visualEffectView.autoresizingMask = [.width, .height]
    containerView.addSubview(visualEffectView)

    // 内容视图在上层
    contentView = DesktopLyricView(frame: containerView.bounds, settings: settings)
    contentView?.autoresizingMask = [.width, .height]
    // ... 设置回调
    containerView.addSubview(contentView!)

    window.contentView = containerView
}
```

**d) 确保插件注册**

```swift
// AppDelegate.swift
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController

        // 注册桌面歌词插件
        DesktopLyricChannel.register(with: controller.registrar(forPlugin: "DesktopLyricChannel"))

        super.applicationDidFinishLaunching(notification)
    }
}
```

---

## 四、实施计划

### 阶段一：修复 macOS 问题 ✅ 已完成

**任务**：
1. [x] 检查并修复 `AppDelegate.swift` 中的插件注册（已确认正常）
2. [x] 修复 `DesktopLyricController.swift` 中的窗口层级
3. [x] 修复 `DesktopLyricView` 中的布局计算
4. [x] 修复毛玻璃效果的层次关系
5. [x] 验证颜色解析逻辑

**验证标准**：
- macOS 上能正常显示桌面歌词
- 歌词文字可见且位置正确
- 拖动和关闭功能正常

### 阶段二：Windows 平台修复 ✅ 已完成

**实际方案**：发现已存在稳定的 `desktop_multi_window` 实现，切换服务即可

**任务**：
1. [x] 分析现有实现，发现两套方案
2. [x] 切换 Provider 使用稳定的 `DesktopLyricServiceWindowsImpl`
3. [x] 更新 `main.dart` 多窗口入口
4. [ ] 可选：删除废弃的 `desktop_lyric_service_windows_native.dart`

**验证标准**：
- Windows 上能正常显示桌面歌词
- 无闪退问题
- "更多"按钮正常工作
- 卡拉OK效果正常

### 阶段三：功能完善（可选）

**任务**：
1. [ ] 统一两平台的设置 UI
2. [ ] 优化窗口位置记忆
3. [ ] 添加更多自定义选项（字体、阴影等）
4. [ ] 性能优化（减少重绘）
5. [ ] 添加错误恢复机制

**验证标准**：
- 所有设置项正常工作
- 关闭重启后位置正确恢复
- 长时间运行无内存泄漏

---

## 五、依赖和配置

### 5.1 新增依赖

```yaml
# pubspec.yaml
dependencies:
  window_manager: ^0.4.3          # 窗口管理（已有）
  desktop_multi_window: ^0.2.0    # 多窗口支持（新增）
```

### 5.2 Windows 配置

需要在 `windows/runner/main.cpp` 中添加多窗口入口点支持。

### 5.3 移除依赖

重构后可移除的代码：
- `desktop_lyric_service_windows_native.dart`（716行）
- 相关的 Win32 FFI 常量和结构体

---

## 六、风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| `desktop_multi_window` 不稳定 | 中 | 高 | 准备回退方案，保留单窗口模式 |
| 透明窗口在某些 Windows 版本不工作 | 低 | 中 | 提供非透明备选样式 |
| 窗口间通信延迟 | 低 | 低 | 使用高效的序列化格式 |
| macOS 修复不完整 | 低 | 中 | 增加调试日志，便于问题追踪 |

---

## 七、实施记录

### 7.1 阶段一：macOS 平台修复（已完成）

#### 7.1.1 AppDelegate 插件注册
- **文件**：`macos/Runner/AppDelegate.swift`
- **问题**：`super.applicationDidFinishLaunching(notification)` 先于自定义插件注册被调用，导致 Flutter 引擎启动时插件未就绪，抛出 `MissingPluginException`
- **修复**：将 `super.applicationDidFinishLaunching(notification)` 移到所有插件注册**之后**

```swift
override func applicationDidFinishLaunching(_ notification: Notification) {
    // 重要：必须在 super.applicationDidFinishLaunching 之前注册，
    // 否则 Flutter 引擎启动时可能已经在调用这些通道，导致 MissingPluginException
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      super.applicationDidFinishLaunching(notification)
      return
    }

    // ... 注册所有自定义插件 ...
    DesktopLyricChannel.register(
      with: controller.engine.registrar(forPlugin: "DesktopLyricChannel")
    )
    // ... 其他插件 ...

    // 调用父类方法启动 Flutter 引擎（必须在插件注册之后）
    super.applicationDidFinishLaunching(notification)
}
```

#### 7.1.2 窗口层级修复
- **文件**：`macos/Runner/DesktopLyric/DesktopLyricController.swift:140-149`
- **问题**：窗口层级 `.floating` 太低，容易被其他窗口遮挡
- **修复**：将 `alwaysOnTop` 模式的窗口层级改为 `.statusBar`

```swift
private func updateWindowLevel() {
    if settings.alwaysOnTop {
        // 使用更高的窗口层级，确保在全屏应用之上也能显示
        // .floating (3) < .statusBar (25) < .modalPanel (8)
        window?.level = .statusBar
    } else {
        window?.level = .floating
    }
}
```

#### 7.1.3 毛玻璃效果层次修复
- **文件**：`macos/Runner/DesktopLyric/DesktopLyricController.swift:55-126`
- **问题**：`NSVisualEffectView` 直接添加到 `contentView` 可能遮挡标签
- **修复**：创建容器视图，确保毛玻璃在底层、内容视图在上层

```swift
// 创建容器视图（用于正确分层）
let containerView = NSView(frame: window.contentView!.bounds)
containerView.wantsLayer = true
containerView.autoresizingMask = [.width, .height]

// 1. 先添加毛玻璃背景（最底层）
let visualEffectView = NSVisualEffectView(frame: containerView.bounds)
visualEffectView.material = .hudWindow
visualEffectView.blendingMode = .behindWindow
visualEffectView.state = .active
visualEffectView.wantsLayer = true
visualEffectView.layer?.cornerRadius = 12
visualEffectView.layer?.masksToBounds = true
visualEffectView.autoresizingMask = [.width, .height]
containerView.addSubview(visualEffectView)

// 2. 再添加内容视图（在毛玻璃上方）
contentView = DesktopLyricView(frame: containerView.bounds, settings: settings)
contentView?.autoresizingMask = [.width, .height]
// ... 设置回调
containerView.addSubview(contentView!)

window.contentView = containerView
```

#### 7.1.4 视图布局计算修复
- **文件**：`macos/Runner/DesktopLyric/DesktopLyricController.swift:279-337`
- **问题**：macOS 坐标系 Y 轴从底部开始，原有计算导致元素位置不正确
- **修复**：重新计算垂直布局，确保所有元素正确居中显示

```swift
private func updateLayout() {
    let padding: CGFloat = 24
    let labelWidth = bounds.width - padding * 2
    let spacing: CGFloat = 4

    // 计算所有可见元素的总高度
    let currentHeight = settings.fontSize + 4
    let translationHeight = settings.showTranslation ? (settings.fontSize * 0.7 + 4) : 0
    let nextLineHeight = settings.showNextLine ? (settings.fontSize * 0.6 + 4) : 0

    var totalHeight = currentHeight
    if settings.showTranslation {
        totalHeight += translationHeight + spacing
    }
    if settings.showNextLine {
        totalHeight += nextLineHeight + spacing
    }

    // 从顶部开始布局（macOS Y 坐标从底部开始，所以需要从 bounds.height 减）
    // 垂直居中：起始 Y 位置 = (总高度 - 内容高度) / 2 + 内容高度
    var yPos = (bounds.height + totalHeight) / 2

    // 当前歌词（最上方）
    yPos -= currentHeight
    currentLyricLabel.frame = NSRect(
        x: padding,
        y: yPos,
        width: labelWidth,
        height: currentHeight
    )
    // ... 其他标签类似处理
}
```

#### 7.1.5 颜色解析修复
- **文件**：`macos/Runner/DesktopLyric/DesktopLyricChannel.swift:158-178`
- **问题**：Flutter 传递的颜色值可能是有符号整数，需要正确处理
- **修复**：添加有符号/无符号整数转换逻辑

```swift
private static func colorFromARGB(_ value: Any?) -> NSColor? {
    guard let value = value else { return nil }

    // Flutter 传递的颜色可能是 Int 或 Int64
    let colorValue: UInt32
    if let intValue = value as? Int {
        colorValue = UInt32(bitPattern: Int32(truncatingIfNeeded: intValue))
    } else if let int64Value = value as? Int64 {
        colorValue = UInt32(truncatingIfNeeded: int64Value)
    } else {
        return nil
    }

    return NSColor(
        red: CGFloat((colorValue >> 16) & 0xFF) / 255.0,
        green: CGFloat((colorValue >> 8) & 0xFF) / 255.0,
        blue: CGFloat(colorValue & 0xFF) / 255.0,
        alpha: CGFloat((colorValue >> 24) & 0xFF) / 255.0
    )
}
```

### 7.2 阶段二：Windows 平台修复（已完成）

#### 7.2.1 问题分析
- **发现**：项目中已存在两套 Windows 实现：
  1. `DesktopLyricServiceWindowsNativeImpl`（Win32 FFI，不稳定）
  2. `DesktopLyricServiceWindowsImpl`（desktop_multi_window，稳定）

#### 7.2.2 解决方案
- **决策**：切换到使用稳定的 `desktop_multi_window` 实现
- **原因**：无需重新开发，只需切换服务实现

#### 7.2.3 Provider 修改
- **文件**：`lib/features/music/presentation/providers/desktop_lyric_provider.dart`
- **修改**：
  1. 导入 `desktop_lyric_service_windows.dart` 替代 `desktop_lyric_service_windows_native.dart`
  2. 使用 `DesktopLyricServiceWindowsImpl.instance` 替代 `DesktopLyricServiceWindowsNativeImpl.instance`
  3. 更新类型检查代码

```dart
// 修改前
import 'package:my_nas/features/music/data/services/desktop_lyric_service_windows_native.dart';
// ...
if (Platform.isWindows) {
  _service = DesktopLyricServiceWindowsNativeImpl.instance;
}

// 修改后
import 'package:my_nas/features/music/data/services/desktop_lyric_service_windows.dart';
// ...
if (Platform.isWindows) {
  _service = DesktopLyricServiceWindowsImpl.instance;
}
```

#### 7.2.4 主入口修改
- **文件**：`lib/main.dart:40-45`
- **修改**：更新注释，说明 macOS 和 Windows 都使用 `desktop_multi_window`

```dart
// 检查是否是桌面歌词子窗口（macOS 和 Windows 都使用 desktop_multi_window）
if (args.isNotEmpty && args.first == 'multi_window') {
  await desktopLyricMain(args.sublist(1));
  return;
}
```

### 7.3 修改文件清单

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `macos/Runner/AppDelegate.swift` | 修改 | 插件注册顺序，super 调用移到最后 |
| `macos/Runner/DesktopLyric/DesktopLyricController.swift` | 修改 | 窗口层级、毛玻璃层次、布局计算 |
| `macos/Runner/DesktopLyric/DesktopLyricChannel.swift` | 修改 | 颜色解析逻辑 |
| `lib/features/music/presentation/providers/desktop_lyric_provider.dart` | 修改 | 切换 Windows 服务实现 |
| `lib/main.dart` | 修改 | 更新多窗口入口注释 |

### 7.4 后续建议

1. **测试验证**：在 macOS 和 Windows 上进行完整功能测试
2. **清理代码**：可考虑删除 `desktop_lyric_service_windows_native.dart`（716 行代码）
3. **性能监控**：长时间运行测试，确保无内存泄漏

---

## 八、参考资源

- [window_manager 文档](https://pub.dev/packages/window_manager)
- [desktop_multi_window 文档](https://pub.dev/packages/desktop_multi_window)
- [Flutter 透明窗口 Issue #71735](https://github.com/flutter/flutter/issues/71735)
- [macOS NSWindow 透明窗口](https://gaitatzis.medium.com/create-a-translucent-overlay-window-on-macos-in-swift-67d5e000ce90)
- [NSWindowStyles 示例](https://github.com/lukakerr/NSWindowStyles)
- [Apple NSWindow.Level 文档](https://developer.apple.com/documentation/appkit/nswindow/1419511-level)
