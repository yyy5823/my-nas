# MyNAS 架构设计文档

## 1. 技术栈选型

### 1.1 核心框架
```
Flutter 3.x + Dart 3.x
```

### 1.2 技术栈全景

| 层级 | 技术选型 | 说明 |
|------|----------|------|
| **UI 框架** | Flutter | 跨平台 UI |
| **状态管理** | Riverpod 2.x | 响应式、类型安全 |
| **路由** | go_router | 声明式路由 |
| **网络请求** | Dio + Retrofit | HTTP 客户端 |
| **本地存储** | Hive + SQLite | 轻量 KV + 关系型 |
| **依赖注入** | get_it + injectable | 服务定位器 |
| **视频播放** | media_kit (libmpv) | 高性能播放器 |
| **音频播放** | just_audio | 跨平台音频 |
| **PDF 阅读** | pdfrx | 高性能 PDF |
| **EPUB 阅读** | epubx + flutter_html | 电子书解析 |
| **Markdown** | flutter_markdown | 笔记渲染 |
| **代码生成** | freezed + json_serializable | 数据模型 |
| **国际化** | flutter_localizations + intl | 多语言 |

---

## 2. 整体架构

### 2.1 分层架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                        │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐ │
│  │  Video  │  │  Music  │  │  Comic  │  │  Book   │  │  Note  │ │
│  │   UI    │  │   UI    │  │   UI    │  │   UI    │  │   UI   │ │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └───┬────┘ │
│       │            │            │            │            │      │
│  ┌────┴────────────┴────────────┴────────────┴────────────┴────┐ │
│  │                    State Management (Riverpod)               │ │
│  └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────────┐
│                         Domain Layer                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   Entities   │  │  Use Cases   │  │ Repositories │           │
│  │              │  │              │  │  (Interface) │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└─────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────────┐
│                          Data Layer                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Repository Impl                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│       │                    │                    │                │
│  ┌────┴────┐         ┌─────┴─────┐        ┌────┴─────┐         │
│  │  Remote │         │   Local   │        │  Cache   │         │
│  │DataSource│        │DataSource │        │ Manager  │         │
│  └────┬────┘         └─────┬─────┘        └──────────┘         │
└───────┼────────────────────┼────────────────────────────────────┘
        │                    │
┌───────┴────────────────────┴────────────────────────────────────┐
│                      NAS Adapter Layer                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Synology │  │  UGREEN  │  │  WebDAV  │  │   SMB    │        │
│  │ Adapter  │  │ Adapter  │  │ Adapter  │  │ Adapter  │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 模块划分

```
lib/
├── app/                          # 应用入口与配置
│   ├── app.dart
│   ├── router/
│   └── theme/
│
├── core/                         # 核心基础设施
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   ├── network/
│   ├── storage/
│   └── utils/
│
├── features/                     # 功能模块 (按功能垂直划分)
│   ├── connection/              # NAS 连接管理
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── video/                   # 视频模块
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── music/                   # 音乐模块
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── comic/                   # 漫画模块
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── book/                    # 书籍模块
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── note/                    # 笔记模块
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   └── tools/                   # 下载工具管理
│       ├── data/
│       ├── domain/
│       └── presentation/
│
├── shared/                       # 共享组件
│   ├── widgets/
│   ├── providers/
│   └── services/
│
└── nas_adapters/                # NAS 适配器 (解耦层)
    ├── base/
    │   ├── nas_adapter.dart     # 抽象接口
    │   ├── nas_connection.dart
    │   └── nas_file_system.dart
    │
    ├── synology/                # 群晖适配器
    │   ├── synology_adapter.dart
    │   ├── api/
    │   └── models/
    │
    ├── ugreen/                  # 绿联适配器
    │   ├── ugreen_adapter.dart
    │   ├── api/
    │   └── models/
    │
    └── generic/                 # 通用协议适配器
        ├── webdav_adapter.dart
        ├── smb_adapter.dart
        └── sftp_adapter.dart
```

---

## 3. 核心设计

### 3.1 NAS 适配器接口设计

```dart
/// NAS 适配器抽象接口
abstract class NasAdapter {
  /// 适配器信息
  NasAdapterInfo get info;

  /// 连接管理
  Future<ConnectionResult> connect(ConnectionConfig config);
  Future<void> disconnect();
  bool get isConnected;

  /// 文件系统操作
  Future<List<FileItem>> listDirectory(String path);
  Future<FileItem> getFileInfo(String path);
  Future<Stream<List<int>>> getFileStream(String path, {Range? range});
  Future<String> getFileUrl(String path, {Duration? expiry});

  /// 媒体服务 (可选实现)
  MediaService? get mediaService;

  /// 下载工具服务 (可选实现)
  ToolsService? get toolsService;
}

/// 媒体服务接口
abstract class MediaService {
  /// 获取视频库
  Future<List<VideoLibrary>> getVideoLibraries();

  /// 获取音乐库
  Future<List<MusicLibrary>> getMusicLibraries();

  /// 获取转码流 (如果支持)
  Future<String?> getTranscodedStream(String fileId, TranscodeOptions options);
}

/// 下载工具服务接口
abstract class ToolsService {
  /// 获取支持的工具列表
  List<ToolInfo> get supportedTools;

  /// 获取工具客户端
  ToolClient? getToolClient(ToolType type);
}
```

### 3.2 播放器抽象设计

```dart
/// 统一播放器接口
abstract class MediaPlayer<T extends MediaItem> {
  /// 播放状态
  Stream<PlaybackState> get stateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;

  /// 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  /// 媒体操作
  Future<void> setMedia(T media);
  Future<void> setPlaylist(List<T> items, {int startIndex = 0});

  /// 资源释放
  Future<void> dispose();
}

/// 视频播放器扩展
abstract class VideoPlayer extends MediaPlayer<VideoItem> {
  /// 视频特有功能
  Future<void> setSubtitle(SubtitleTrack? track);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setPlaybackSpeed(double speed);
  Stream<VideoSize> get videoSizeStream;
}

/// 音频播放器扩展
abstract class AudioPlayer extends MediaPlayer<AudioItem> {
  /// 音频特有功能
  Future<void> setEqualizerPreset(EqualizerPreset preset);
  Future<void> setVolume(double volume);
}
```

### 3.3 状态管理设计 (Riverpod)

```dart
/// NAS 连接状态
@riverpod
class NasConnection extends _$NasConnection {
  @override
  AsyncValue<NasAdapter?> build() => const AsyncValue.data(null);

  Future<void> connect(ConnectionConfig config) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final adapter = ref.read(nasAdapterFactoryProvider).create(config.type);
      await adapter.connect(config);
      return adapter;
    });
  }
}

/// 视频列表状态
@riverpod
class VideoList extends _$VideoList {
  @override
  Future<List<VideoItem>> build(String path) async {
    final adapter = ref.watch(nasConnectionProvider).valueOrNull;
    if (adapter == null) throw NotConnectedException();

    final files = await adapter.listDirectory(path);
    return files.whereType<VideoItem>().toList();
  }
}

/// 播放器状态
@riverpod
class VideoPlayerController extends _$VideoPlayerController {
  @override
  VideoPlayerState build() => VideoPlayerState.initial();

  Future<void> play(VideoItem video) async {
    // 实现播放逻辑
  }
}
```

---

## 4. UI 设计规范

### 4.1 设计系统

```dart
/// 主题配置
class AppTheme {
  // 颜色系统 (Material 3)
  static const primaryColor = Color(0xFF6366F1);  // Indigo
  static const secondaryColor = Color(0xFF8B5CF6); // Violet
  static const tertiaryColor = Color(0xFF06B6D4);  // Cyan

  // 暗色主题强调色
  static const darkSurface = Color(0xFF1E1E2E);
  static const darkBackground = Color(0xFF11111B);

  // 圆角系统
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;
  static const radiusXLarge = 24.0;

  // 间距系统 (4px 基准)
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
}
```

### 4.2 响应式布局

```dart
/// 响应式断点
enum ScreenSize {
  compact(0, 600),     // 手机
  medium(600, 840),    // 折叠屏/小平板
  expanded(840, 1200), // 平板
  large(1200, 1600),   // 桌面
  extraLarge(1600, double.infinity); // 大屏

  final double minWidth;
  final double maxWidth;
  const ScreenSize(this.minWidth, this.maxWidth);
}

/// 自适应布局
class AdaptiveLayout extends StatelessWidget {
  final Widget compactLayout;
  final Widget? mediumLayout;
  final Widget? expandedLayout;

  // ... 根据屏幕尺寸选择布局
}
```

### 4.3 组件规范

- **卡片**: 使用毛玻璃效果 + 微妙阴影
- **列表**: 支持网格/列表视图切换
- **导航**: 底部导航(移动) / 侧边栏(桌面)
- **动画**: 使用 Spring 动画曲线，时长 200-400ms
- **图标**: 使用 Lucide Icons 或 Phosphor Icons

---

## 5. 数据流设计

### 5.1 离线优先架构

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│     UI      │────▶│   Cache     │────▶│   Remote    │
│             │◀────│  (SQLite)   │◀────│   (NAS)     │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       │    ┌──────────────┴──────────────┐
       │    │                             │
       ▼    ▼                             ▼
  ┌─────────────┐                  ┌─────────────┐
  │  显示缓存   │                  │  后台同步   │
  │  (立即)     │                  │  (增量)     │
  └─────────────┘                  └─────────────┘
```

### 5.2 播放进度同步

```dart
/// 进度同步策略
class PlaybackProgressSync {
  // 本地存储 (立即)
  Future<void> saveLocal(String mediaId, Duration position);

  // 远程同步 (防抖 5秒)
  Future<void> syncRemote(String mediaId, Duration position);

  // 冲突解决 (取最新)
  Duration resolveConflict(Duration local, Duration remote, DateTime localTime, DateTime remoteTime);
}
```

---

## 6. 安全设计

### 6.1 凭证存储
- iOS/macOS: Keychain
- Android: EncryptedSharedPreferences
- Windows: Windows Credential Manager
- 使用 `flutter_secure_storage`

### 6.2 网络安全
- 强制 HTTPS (可选跳过证书验证 for 自签名)
- Certificate Pinning (可选)
- 请求签名

### 6.3 本地数据保护
- SQLite 加密 (sqlcipher)
- 敏感数据加密存储
- 应用锁 (PIN/生物识别)

---

## 7. 平台特定适配

### 7.1 macOS
- 菜单栏集成
- 触控板手势
- 画中画
- 通知中心

### 7.2 Windows
- 任务栏预览
- 媒体键支持
- 系统主题跟随

### 7.3 iOS
- AirPlay 支持
- CarPlay 集成 (音乐)
- 小组件
- Handoff

### 7.4 Android
- 媒体通知
- Android Auto
- 分屏支持
- 快捷方式
