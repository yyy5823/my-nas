# MyNAS 架构设计文档

> 最后更新：2026-04-29
> 反映项目当前实际架构。

## 1. 技术栈

### 1.1 核心框架

```
Flutter 3.x + Dart 3.x（启用 sealed classes / records / pattern matching）
```

### 1.2 关键依赖

| 层级 | 选型 | 备注 |
|---|---|---|
| **UI 框架** | Flutter | iOS/Android/macOS/Windows/Linux |
| **状态管理** | flutter_riverpod 2.x | 响应式、类型安全 |
| **路由** | go_router 15.x | 含 deep link / scheme 处理 |
| **网络请求** | dio 5.x | 自定义 DioClient（含自签证书选择性信任） |
| **本地存储** | hive_ce + sqflite | KV + 关系型 + AES 加密 box |
| **凭证存储** | flutter_secure_storage + Hive AES 降级 | 多端密钥管理 |
| **视频播放** | media_kit 1.2.x (libmpv) | 通过 NativePlayer 调 mpv 属性 |
| **音频播放** | just_audio + audio_service + media_kit | 多平台 + 后台 + 锁屏 |
| **下载** | dio + 自研 transfer_service | 断点续传、流式下载 |
| **PDF 阅读** | pdfrx | |
| **EPUB 阅读** | epubx + flutter_html / WebView 双模式 | |
| **MOBI/AZW3** | 自研 parser | |
| **加密** | crypto + pointycastle | sha256 + RSA + AES |
| **国际化** | flutter_localizations + intl | |

---

## 2. 整体架构

### 2.1 分层

```
┌─────────────────────────────────────────────────────────────────┐
│                       Presentation Layer                         │
│  Pages / Widgets （按 features 切分）                              │
│  Riverpod Providers / Notifiers / StateNotifiers                 │
└─────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────────┐
│                          Domain Layer                            │
│  Entities / Value Objects（VideoMetadata / BookSource / ...）     │
│  抽象接口（NasFileSystem / MediaServerAdapter / ServiceAdapter）    │
└─────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────────┐
│                           Data Layer                             │
│  Services（feature-level 服务）                                    │
│  Repositories / Local DataSource / Remote DataSource             │
│  HiveBox / Sqflite / SecureStorage / Cache                       │
└─────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────┴───────────────────────────────┐
│                        Adapter Layer                             │
│  ┌───────────────┐ ┌────────────────┐ ┌──────────────────┐      │
│  │ nas_adapters  │ │ media_server   │ │ service_adapters │      │
│  │ SMB/WebDAV/   │ │ Jellyfin/Emby/ │ │ qBittorrent/     │      │
│  │ Synology/fnos/│ │ Plex (只读 +   │ │ Transmission/    │      │
│  │ ugreen/local  │ │ 元数据驱动)    │ │ Aria2/MoviePilot │      │
│  └───────────────┘ └────────────────┘ └──────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 实际目录

```
lib/
├── app/                         # 应用入口、路由、主题
│   ├── app.dart
│   ├── router/
│   └── theme/
│
├── core/                        # 核心基础设施
│   ├── constants/
│   ├── errors/                  # AppError 工具类（统一错误处理）
│   ├── extensions/              # context_extensions / list_extensions ...
│   ├── network/                 # DioClient（含自签证书可选）
│   ├── storage/                 # AuthStorageService（含 Keychain 降级）
│   ├── utils/                   # logger / hive_utils / platform_capabilities ...
│   └── widgets/                 # 跨 feature 复用的基础组件
│
├── features/                    # 功能模块（垂直划分）
│   ├── connection/              # NAS 连接管理
│   ├── sources/                 # 源管理（NAS / 媒体服务器 / 下载器 / 字幕站统一抽象）
│   ├── file_browser/            # 文件浏览器
│   ├── transfer/                # 上传/下载/共享缓存
│   ├── video/                   # 视频列表/详情/播放/转码/字幕/刮削
│   ├── music/                   # 音乐列表/播放器/元数据/灵动岛
│   ├── photo/                   # 相册/人脸识别
│   ├── comic/                   # 漫画阅读
│   ├── book/                    # 电子书 + 在线书源（Legado 兼容）
│   ├── note/                    # 笔记浏览
│   ├── reading/                 # 阅读进度 + 书签统一服务
│   ├── pt_sites/                # PT 站爬取/搜索/发送下载器
│   ├── nastool/                 # NASTool 集成
│   ├── media_tracking/          # Trakt 等
│   └── mine/                    # 个人页/设置
│
├── shared/                      # 跨 feature 共享
│   ├── widgets/
│   ├── providers/
│   └── services/
│
├── nas_adapters/                # NAS 适配器层
│   ├── base/
│   │   ├── nas_adapter.dart
│   │   ├── nas_connection.dart
│   │   └── nas_file_system.dart
│   ├── smb/                     # SMB（含连接池 + 心跳 + 客户端 fallback）
│   ├── webdav/
│   ├── synology/
│   ├── fnos/                    # 飞牛 NAS（私有 API）
│   ├── ugreen/                  # 绿联 NAS（RSA 加密登录）
│   ├── local/                   # 本地文件系统
│   └── mobile/                  # 移动端虚拟文件系统（手机本地音乐/相册/文件）
│
├── media_server_adapters/       # 媒体服务器适配器
│   ├── base/
│   │   ├── media_server_adapter.dart
│   │   └── media_server_entities.dart
│   ├── jellyfin/                # Jellyfin (10.8+)
│   ├── emby/                    # Emby (4.6+)
│   └── plex/                    # Plex
│
└── service_adapters/            # 服务适配器（下载器、刮削器等）
    ├── base/
    ├── qbittorrent/
    ├── transmission/
    ├── aria2/
    ├── moviepilot/
    └── ...
```

---

## 3. 核心抽象

### 3.1 NasFileSystem 接口（实际签名）

```dart
abstract class NasFileSystem {
  Future<List<FileItem>> listDirectory(String path);
  Future<FileItem> getFileInfo(String path);

  /// 流式读，可指定 Range
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range});

  /// URL 流（部分协议如 SMB 通过 smb:// 占位反解）
  Future<Stream<List<int>>> getUrlStream(String url);

  /// 直链（HTTP 协议返回真链，SMB 返回 smb://placeholder）
  Future<String> getFileUrl(String path, {Duration? expiry});

  Future<void> createDirectory(String path);
  Future<void> delete(String path);
  Future<void> rename(String oldPath, String newPath);
  Future<void> copy(String sourcePath, String destPath);
  Future<void> move(String sourcePath, String destPath);

  /// 上传本地文件
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  });

  /// 写入字节（用于 NFO/海报等）
  Future<void> writeFile(String remotePath, List<int> data);

  /// 搜索（部分协议无服务端搜索时回退到客户端 BFS，限深度+数量）
  Future<List<FileItem>> search(String query, {String? path});

  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size});
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size});
}
```

**约定**：服务端能力（copy/search/upload）失败时通过 `AppError.ignore` 回退到客户端实现，不抛出未实现错误（除非真的不可能）。

### 3.2 MediaServerAdapter 接口

```dart
abstract class MediaServerAdapter implements ServiceAdapter {
  /// 库 / 媒体浏览
  Future<List<MediaLibrary>> getLibraries();
  Future<MediaItemsResult> getItems({...});
  Future<MediaItem?> getItemDetail(String itemId);

  /// 推荐 / 继续看 / 下一集
  Future<MediaItemsResult> getLatestMedia({...});
  Future<MediaItemsResult> getResumeItems({int limit = 20});
  Future<MediaItem?> getNextUp({String? seriesId});

  /// 搜索
  Future<MediaItemsResult> search(String query, {...});

  /// 播放
  Future<PlaybackInfo> getPlaybackInfo(String itemId, {...});
  Future<void> reportPlaybackStart(String itemId, {...});
  Future<void> reportPlaybackProgress(String itemId, Duration position, {...});
  Future<void> reportPlaybackStopped(String itemId, Duration position);

  /// 状态同步
  Future<void> markWatched(String itemId);
  Future<bool> toggleFavorite(String itemId);

  /// 虚拟文件系统（只读）
  NasFileSystem? get virtualFileSystem;
}
```

### 3.3 ServiceAdapter（下载器/服务器统一基础）

```dart
abstract class ServiceAdapter {
  ServiceAdapterInfo get info;
  bool get isConnected;
  ServiceConnectionConfig? get connection;

  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config);
  Future<void> disconnect();
  Future<void> dispose();
}
```

### 3.4 错误处理（AppError）

```dart
class AppError {
  static void handle(Object e, [StackTrace? st, String? action, Map? extra]);
  static void handleWithUI(BuildContext ctx, Object e, [...]);
  static Future<T?> guard<T>(Future<T> Function() op, {String? action, T? fallback});
  static T? guardSync<T>(T Function() op, {...});
  static void ignore(Object e, [StackTrace? st, String? reason]);
  static void fireAndForget(Future<void> f, {String? action, Map? extra});
}
```

**核心约定**：
- 所有 catch 块必须用 AppError，禁止空 catch / 仅 print / 仅 SnackBar
- 远程上报已移除（避免客户端凭证泄露），仅本地日志
- ErrorCategory 决定日志级别（fatal / error / warn）
- `ignore` 必须填第三个参数（reason）以便代码审查

---

## 4. 关键设计决策

### 4.1 凭证存储降级

```
FlutterSecureStorage (Keychain/EncryptedSharedPreferences)
  ↓ 失败（如 macOS 缺 Keychain entitlement）
Hive AES Cipher Box (key 由 deviceName + salt 派生 sha256)
  ↓ 失败
内存临时 ID（不持久化，重启丢失）
```

实现：`lib/core/storage/auth_storage_service.dart`。降级时不阻断使用，但记录 warn 级日志。

### 4.2 媒体服务器虚拟文件系统

媒体服务器是**元数据驱动**而非文件系统驱动，所以 Jellyfin/Emby/Plex 的 `virtual_fs.dart`：
- 浏览：库 → 电影 → 项目，路径映射到 `MediaItem`
- 不支持创建/删除/上传/写入（抛 `UnsupportedError`），UI 层据此隐藏按钮
- 仅暴露 `getFileUrl` 供播放器使用

### 4.3 SMB 客户端 fallback

SMB 协议本身不支持（或库未暴露）部分操作：
- `copy` → 客户端 download + upload 流式管道
- `search` → 客户端 BFS（限深度 4、限 200 个结果）
- `getUrlStream` → 解析 `smb://placeholder<path>` 占位符回调 `getFileStream`

这套模式同样应用于绿联/飞牛 NAS，先尝试服务端 API，失败 `AppError.ignore` 后走客户端兜底。

### 4.4 PT 搜索串联

```
视频详情页 / TMDB 推荐卡片 / 缺失剧集 sheet
    ↓ launchPtSearchForMedia(context, ref, query: '片名 年份')
    ↓ 0 站点 → 提示；1 站点 → 直跳；多站点 → 弹 sheet 选
PTSiteDetailPage(initialQuery: '...')
    ↓ initState 自动填入并触发搜索
PT 搜索结果列表
    ↓ 种子卡片下载按钮 → SendToDownloaderSheet
qBittorrent / Transmission / Aria2
```

实现：`lib/features/pt_sites/presentation/utils/pt_search_launcher.dart`

### 4.5 字幕投屏（DLNA）

`dlna_dart` 内置 metadata 不携带字幕。MyNAS 自构 DIDL-Lite XML，**同时携带三种字幕扩展**以最大化设备兼容：

- 三星：`<sec:CaptionInfoEx sec:type="srt">URL</sec:CaptionInfoEx>`
- 通用：`<res protocolInfo="http-get:*:text/srt:*">URL</res>` 作为独立 res
- Sony：`<res ... pv:subtitleFileUri="URL" pv:subtitleFileType="srt">videoUrl</res>`

不支持字幕的设备会自然忽略，正常播视频。

### 4.6 跨平台播放器属性

`media_kit` 没暴露公共 `setProperty`。MyNAS 通过 `_player.platform is NativePlayer` 检查后调用 `NativePlayer.setProperty('sub-delay', value)` 直接写入 mpv 属性。Web 平台返回 false 不调用。

---

## 5. UI / UX

### 5.1 主题系统

- Material 3 (`AppColors` / `AppSpacing`)
- iOS 26 Liquid Glass 模式（玻璃效果导航栏 + 弹层 + 浮动按钮）
- 暗色 / 亮色 / 跟随系统

### 5.2 响应式

- compact (< 600)：手机
- medium (600–840)：折叠屏 / 小平板
- expanded (840–1200)：平板
- large (≥ 1200)：桌面 / 大屏

`AdaptiveLayout`、`ScreenSize` 工具支持自适应。

### 5.3 平台原生集成

- **macOS**：原生菜单栏 / 触控板手势 / 通知 / Spotlight 索引
- **Windows**：媒体键 / 任务栏 / 系统主题跟随 / 桌面歌词原生窗口
- **iOS**：AirPlay / Now Playing / 灵动岛 / 媒体小组件 / 麦克风权限
- **Android**：媒体通知 / 灵动岛风格通知 / 应用快捷方式

---

## 6. 安全设计

### 6.1 凭证存储
见 §4.1 三级降级。

### 6.2 网络
- 默认 HTTPS，自签证书可选信任（用户配置）
- DioClient 拦截器统一注入 token / device-id / user-agent

### 6.3 本地数据
- Hive 加密 box（auth_fallback_v1 / book_sources / settings 等）
- 临时文件分享后 5 分钟清理
- SQLite 缓存（视频元数据、人脸库等）

### 6.4 合规
- **不内嵌任何书源**（用户自行导入）
- 公共 API key（OpenSubtitles 等）用户可覆盖
- 错误处理已移除远程上报（避免凭证泄露）

---

## 7. 数据流

### 7.1 离线优先

```
UI ──watch── Riverpod Provider ──读── Cache (Hive/SQLite)
                                    │
                                    └── 同时后台 fetch Remote ─→ 写入 Cache
                                                                ↓
                                                            UI 自动刷新
```

### 7.2 进度同步

```
本地立即写入 ReadingProgressService (Hive box)
    ↓ 防抖 5s
媒体服务器 reportPlaybackProgress / Trakt 同步 / NASTool 同步
    ↓ 冲突解决
取最新 lastReadAt / playedAt
```

---

## 8. 测试策略

- ✅ Widget 测试：核心组件（cast_service、video_player、book_reader）
- ✅ 单元测试：解析器（mobi/epub/nfo/legado_rule）
- 🚧 集成测试：端到端流程（NAS 连接 → 浏览 → 播放）
- 📝 性能测试基线

---

## 9. 已知技术债

| 项 | 说明 | 优先级 |
|---|---|---|
| Plex WebSocket | Plex 协议本身不提供，需轮询或 webhook，工程价值低 | 低 |
| 国际化覆盖率 | 部分硬编码中文，需逐步迁移到 .arb | 中 |
| 完整无障碍 | Semantics 标注覆盖率不足 | 中 |
| 单元测试覆盖率 | 现状偏低 | 中 |
| iOS 26 Liquid Glass | 部分页面未完全适配 | 低 |
