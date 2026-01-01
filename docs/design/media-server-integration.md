# 媒体服务器连接源设计文档

> 版本: 1.1
> 日期: 2026-01-01
> 状态: 设计阶段

## 目录

1. [概述](#1-概述)
2. [目标媒体服务器](#2-目标媒体服务器)
3. [API 接入方式](#3-api-接入方式)
4. [架构设计](#4-架构设计)
5. [与现有连接源的适配](#5-与现有连接源的适配)
6. [数据模型设计](#6-数据模型设计)
7. [刮削数据优先级策略](#7-刮削数据优先级策略)
8. [潜在问题与解决方案](#8-潜在问题与解决方案)
9. [兼容性问题](#9-兼容性问题)
10. [连接源移除处理](#10-连接源移除处理)
11. [数据库迁移策略](#11-数据库迁移策略) ⭐ NEW
12. [客户端集成注意点（Infuse 等经验）](#12-客户端集成注意点) ⭐ NEW
13. [实现优先级](#13-实现优先级)
14. [参考资料](#14-参考资料)

---

## 1. 概述

### 1.1 背景

当前应用支持的连接源主要为存储类（SMB、WebDAV、NAS 设备等）和服务类（下载工具、媒体管理等）。用户常用的媒体服务器（Jellyfin、Emby、Plex）尚未实现，这限制了用户在多平台间统一管理媒体内容的能力。

### 1.2 目标

- 实现 Jellyfin、Emby、Plex 三大主流媒体服务器的连接支持
- **优先使用服务端刮削的元数据**，而非本地重新刮削
- 与现有架构无缝集成，保持统一的用户体验
- 支持媒体库浏览、播放、元数据同步等核心功能

### 1.3 现有代码基础

在 `SourceType` 枚举中已预留：

```dart
SourceType.jellyfin => false,  // 待实现
SourceType.emby => false,      // 待实现
SourceType.plex => false,      // 待实现
```

默认端口已配置：
- Jellyfin: 8096
- Emby: 8096
- Plex: 32400

---

## 2. 目标媒体服务器

### 2.1 Jellyfin

| 特性 | 说明 |
|------|------|
| 开源性 | 完全开源免费（GPLv2） |
| API 兼容性 | 与 Emby API 高度兼容（分支自 Emby） |
| 认证方式 | 用户名/密码、API Key、Quick Connect |
| 特色功能 | 无订阅费用、完整 Live TV/DVR 支持 |
| SDK 支持 | TypeScript、Kotlin、Python、**Dart** |

### 2.2 Emby

| 特性 | 说明 |
|------|------|
| 开源性 | 部分开源（核心功能闭源） |
| API 兼容性 | REST API，与 Jellyfin 类似 |
| 认证方式 | 用户名/密码、API Key |
| 特色功能 | 成熟稳定、插件生态丰富 |
| SDK 支持 | C#、Java、JavaScript、Python |

### 2.3 Plex

| 特性 | 说明 |
|------|------|
| 开源性 | 闭源商业软件（有免费层） |
| API 兼容性 | 私有 REST API（2025 年新增官方文档） |
| 认证方式 | X-Plex-Token（通过 plex.tv 获取） |
| 特色功能 | 商业级稳定性、远程访问便捷 |
| SDK 支持 | Python、非官方社区库 |

### 2.4 对比总结

| 特性 | Jellyfin | Emby | Plex |
|------|----------|------|------|
| API 开放程度 | 完全开放 | 开放 | 有限开放（新增官方文档） |
| 认证复杂度 | 低 | 低 | 中（需 plex.tv 交互） |
| 实现难度 | 低 | 低 | 中 |
| 文档质量 | 一般（靠社区） | 良好 | 改善中 |
| Dart 支持 | 有官方包 | 无 | 无 |

---

## 3. API 接入方式

### 3.1 Jellyfin API

#### 认证流程

```
┌─────────────┐    POST /Users/AuthenticateByName    ┌─────────────┐
│   Client    │ ────────────────────────────────────▶ │   Server    │
│             │    {Username, Pw}                     │             │
│             │ ◀──────────────────────────────────── │             │
└─────────────┘    {AccessToken, User, ServerId}      └─────────────┘
```

#### 请求头格式

```http
Authorization: MediaBrowser Client="MyNAS", Device="iPhone", DeviceId="xxx", Version="1.0", Token="xxx"
```

或简化形式：
```http
X-Emby-Token: <access_token>
```

#### 核心端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/Users/AuthenticateByName` | POST | 用户认证 |
| `/Users/{userId}/Views` | GET | 获取媒体库列表 |
| `/Users/{userId}/Items` | GET | 获取媒体项列表 |
| `/Items/{itemId}` | GET | 获取单个项目详情 |
| `/Items/{itemId}/Images/{imageType}` | GET | 获取图片 |
| `/Videos/{itemId}/stream` | GET | 视频流 |
| `/System/Info` | GET | 服务器信息 |
| `/QuickConnect/Initiate` | POST | Quick Connect 初始化 |

#### Dart SDK

```yaml
dependencies:
  jellyfin_dart: ^0.6.0  # pub.dev 上的官方包
```

### 3.2 Emby API

#### 认证流程

与 Jellyfin 完全相同（Jellyfin 是 Emby 的分支）。

#### 核心端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/Users/AuthenticateByName` | POST | 用户认证 |
| `/Users/{userId}/Views` | GET | 获取媒体库列表 |
| `/Users/{userId}/Items` | GET | 获取媒体项列表 |
| `/Items/{itemId}` | GET | 获取项目详情 |
| `/Items/{itemId}/Images/{imageType}` | GET | 获取图片 |
| `/emby/Videos/{itemId}/stream` | GET | 视频流 |

#### 参考文档

- 官方 API 文档：https://dev.emby.media/doc/restapi/index.html
- API 浏览器：https://dev.emby.media/reference/index.html

### 3.3 Plex API

#### 认证流程

Plex 使用中心化认证（通过 plex.tv）：

```
┌─────────────┐    1. POST /pins    ┌─────────────┐
│   Client    │ ──────────────────▶ │  plex.tv    │
│             │ ◀────────────────── │             │
│             │    {id, code}       │             │
│             │                     │             │
│   User      │ 2. 访问链接输入 code │             │
│   Browser   │ ──────────────────▶ │             │
│             │                     │             │
│   Client    │ 3. GET /pins/{id}   │             │
│             │ ──────────────────▶ │             │
│             │ ◀────────────────── │             │
└─────────────┘    {authToken}      └─────────────┘
```

或直接使用已有 Token：

```http
X-Plex-Token: <token>
```

#### 核心端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/library/sections` | GET | 获取媒体库列表 |
| `/library/sections/{key}/all` | GET | 获取库中所有项目 |
| `/library/metadata/{ratingKey}` | GET | 获取项目元数据 |
| `/photo/:/transcode` | GET | 获取图片（带转码） |
| `/video/:/transcode/...` | GET | 视频转码流 |
| `/` | GET | 服务器基本信息 |

#### 新版 JWT 认证（2025）

Plex 引入了新的 JWT 认证机制：
- 设备上传公钥（JWK）
- 请求短期 JWT Token
- Token 有效期 7 天，可刷新

---

## 4. 架构设计

### 4.1 适配器架构

延续现有的 `NasAdapter` 模式，为每个媒体服务器创建独立适配器：

```
lib/
├── nas_adapters/
│   ├── base/
│   │   ├── nas_adapter.dart          # 基类
│   │   └── nas_file_system.dart      # 文件系统接口
│   │
│   ├── jellyfin/
│   │   ├── jellyfin_adapter.dart     # Jellyfin 适配器
│   │   ├── jellyfin_file_system.dart # 虚拟文件系统
│   │   ├── jellyfin_media_service.dart # 媒体服务
│   │   └── api/
│   │       └── jellyfin_api.dart     # API 封装
│   │
│   ├── emby/
│   │   ├── emby_adapter.dart
│   │   ├── emby_file_system.dart
│   │   ├── emby_media_service.dart
│   │   └── api/
│   │       └── emby_api.dart
│   │
│   └── plex/
│       ├── plex_adapter.dart
│       ├── plex_file_system.dart
│       ├── plex_media_service.dart
│       └── api/
│           └── plex_api.dart
```

### 4.2 统一媒体服务接口

创建专门的媒体服务接口，扩展现有的 `MediaService`：

```dart
/// 媒体服务器专用服务接口
abstract class MediaServerService extends MediaService {
  /// 获取服务器上的媒体库列表
  Future<List<MediaLibrary>> getLibraries();

  /// 获取库中的媒体项（支持分页）
  Future<MediaItemsResult> getItems({
    required String libraryId,
    MediaItemType? type,
    int? startIndex,
    int? limit,
    String? sortBy,
    SortOrder? sortOrder,
  });

  /// 获取单个媒体项详情（包含完整元数据）
  Future<MediaItemDetail> getItemDetail(String itemId);

  /// 获取媒体项的图片 URL
  String getImageUrl(String itemId, ImageType type, {int? maxWidth});

  /// 获取视频流 URL
  Future<StreamInfo> getStreamUrl(String itemId, {
    TranscodeOptions? transcode,
  });

  /// 获取续播位置
  Future<Duration?> getPlaybackPosition(String itemId);

  /// 报告播放状态
  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    required PlaybackState state,
  });

  /// 标记为已观看/未观看
  Future<void> markAsWatched(String itemId, bool watched);

  /// 搜索媒体
  Future<List<MediaItemDetail>> search(String query, {
    MediaItemType? type,
    int? limit,
  });
}
```

### 4.3 虚拟文件系统

媒体服务器不是传统文件系统，需要创建"虚拟文件系统"层来适配现有的 `NasFileSystem` 接口：

```dart
/// 媒体服务器虚拟文件系统
///
/// 将媒体库的层级结构映射为文件系统结构：
/// /
/// ├── 电影/
/// │   ├── 动作片/
/// │   │   ├── 复仇者联盟.mkv
/// │   │   └── ...
/// │   └── 科幻片/
/// ├── 电视剧/
/// │   ├── 权力的游戏/
/// │   │   ├── Season 1/
/// │   │   │   ├── S01E01.mkv
/// │   │   │   └── ...
/// │   │   └── ...
/// │   └── ...
/// └── 音乐/
class JellyfinFileSystem implements NasFileSystem {
  @override
  Future<List<FileItem>> listDirectory(String path) async {
    if (path == '/') {
      // 返回所有媒体库
      final libraries = await _mediaService.getLibraries();
      return libraries.map(_libraryToFileItem).toList();
    }

    // 解析路径，映射到对应的 API 调用
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    // ...
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    // 从 path 解析出 itemId，调用流接口
    final itemId = _extractItemId(path);
    final streamInfo = await _mediaService.getStreamUrl(itemId);
    // ...
  }
}
```

### 4.4 路径映射策略

| 虚拟路径 | 映射到 |
|---------|--------|
| `/` | 媒体库列表 (Libraries/Views) |
| `/{libraryName}` | 库内容 (Items) |
| `/{libraryName}/{folder}/...` | 按服务器组织的层级 |
| `/{libraryName}/.../file.mkv` | 具体媒体文件 (Item) |

---

## 5. 与现有连接源的适配

### 5.1 SourceEntity 扩展

无需修改 `SourceEntity`，已有字段可复用：

| 字段 | 用途 |
|------|------|
| `host` | 服务器地址 |
| `port` | 端口（Jellyfin/Emby: 8096, Plex: 32400） |
| `username` | 用户名（Jellyfin/Emby）或 Plex 账户 |
| `useSsl` | 是否使用 HTTPS |
| `accessToken` | 认证 Token |
| `apiKey` | API Key（可选认证方式） |
| `extraConfig` | 扩展配置（userId、serverId 等） |

### 5.2 extraConfig 结构设计

```dart
// Jellyfin/Emby
{
  'userId': 'xxx',          // 登录用户的 ID
  'serverId': 'xxx',        // 服务器 ID
  'deviceId': 'xxx',        // 设备 ID（用于播放状态追踪）
  'preferTranscode': false, // 是否优先转码
  'maxBitrate': null,       // 最大码率限制
}

// Plex
{
  'userId': 'xxx',
  'machineIdentifier': 'xxx',  // Plex 服务器唯一标识
  'clientIdentifier': 'xxx',   // 客户端标识
  'preferDirectPlay': true,    // 优先直接播放
}
```

### 5.3 表单配置扩展

为媒体服务器类型添加特殊表单字段：

```dart
// source_form_config.dart
SourceType.jellyfin || SourceType.emby => SourceFormConfig(
  showHost: true,
  showPort: true,
  showUsername: true,
  showPassword: true,
  showSsl: true,
  showApiKey: true,  // 可选的 API Key 认证
  showQuickConnect: true,  // Jellyfin Quick Connect
  extraFields: [
    FormField(
      key: 'preferTranscode',
      type: FormFieldType.switch_,
      label: '优先转码',
      description: '在网络不稳定时自动转码',
      defaultValue: false,
    ),
  ],
),

SourceType.plex => SourceFormConfig(
  showHost: true,
  showPort: true,
  showUsername: false,  // Plex 使用 OAuth
  showPassword: false,
  showSsl: true,
  customAuth: PlexAuthWidget(),  // 自定义 OAuth 登录组件
  extraFields: [
    FormField(
      key: 'preferDirectPlay',
      type: FormFieldType.switch_,
      label: '优先直接播放',
      description: '尽可能使用直接播放而非转码',
      defaultValue: true,
    ),
  ],
),
```

### 5.4 与文件浏览器集成

媒体服务器在文件浏览器中显示为特殊源，使用虚拟文件系统：

```dart
// file_browser_provider.dart
final selectedSourceConnectionProvider = Provider<SourceConnection?>((ref) {
  final connection = ref.watch(...);

  // 媒体服务器使用虚拟文件系统
  if (connection?.source.type.category == SourceCategory.mediaServers) {
    // 返回带有虚拟文件系统的连接
    return connection?.copyWith(
      adapter: connection.adapter, // 适配器包含虚拟文件系统
    );
  }

  return connection;
});
```

---

## 6. 数据模型设计

### 6.1 媒体服务器元数据模型

```dart
/// 来自媒体服务器的元数据
class MediaServerMetadata {
  final String serverId;         // 服务器 ID
  final String serverType;       // jellyfin/emby/plex
  final String itemId;           // 服务器上的项目 ID

  // 基础信息
  final String title;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final double? communityRating;
  final int? runtimeMinutes;

  // 分类信息
  final MediaCategory category;  // movie/tvShow
  final List<String> genres;

  // 剧集信息
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String? seriesId;        // 所属剧集的 ID
  final String? seasonId;        // 所属季的 ID

  // 外部 ID（用于跨服务器关联）
  final int? tmdbId;
  final String? imdbId;
  final int? tvdbId;

  // 图片（服务器端 URL）
  final String? posterUrl;
  final String? backdropUrl;
  final String? thumbUrl;

  // 技术信息
  final List<MediaStream> mediaStreams;  // 视频/音频/字幕流
  final String? container;               // mkv, mp4 等
  final int? bitrate;

  // 播放状态
  final Duration? playbackPosition;
  final bool isWatched;
  final DateTime? lastPlayedDate;
}
```

### 6.2 与本地 VideoMetadata 的映射

```dart
extension MediaServerMetadataExtension on MediaServerMetadata {
  /// 转换为本地 VideoMetadata
  VideoMetadata toVideoMetadata({
    required String sourceId,
    required String filePath,
  }) => VideoMetadata(
    sourceId: sourceId,
    filePath: filePath,
    fileName: _extractFileName(filePath),
    category: category,

    // 标记为服务器刮削数据
    scrapeStatus: ScrapeStatus.completed,
    scrapeSource: serverType,  // 'jellyfin', 'emby', 'plex'

    // 基础信息
    title: title,
    originalTitle: originalTitle,
    year: year,
    overview: overview,

    // 外部 ID
    tmdbId: tmdbId,
    imdbId: imdbId,

    // 图片（使用服务器 URL）
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,

    // 剧集信息
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    episodeTitle: episodeTitle,

    // 扩展信息（存储服务器特有数据）
    extraData: {
      'serverId': serverId,
      'serverType': serverType,
      'itemId': itemId,
      'seriesId': seriesId,
      'seasonId': seasonId,
      'tvdbId': tvdbId,
    },
  );
}
```

---

## 7. 刮削数据优先级策略

### 7.1 核心原则

**服务器数据优先**：媒体服务器已完成刮削的数据应直接使用，避免重复刮削。

### 7.2 优先级顺序

```
1. 媒体服务器元数据（Jellyfin/Emby/Plex）
   ↓ 服务器无数据或不完整
2. 本地 NFO 文件
   ↓ 无 NFO 或 NFO 不完整
3. 在线刮削（TMDB/豆瓣）
   ↓ 在线刮削失败
4. 基于文件名的基础信息
```

### 7.3 实现策略

```dart
class VideoMetadataService {
  /// 获取视频元数据（带优先级）
  Future<VideoMetadata> getMetadata({
    required String sourceId,
    required String filePath,
  }) async {
    final source = await _sourceManager.getSource(sourceId);

    // 1. 如果是媒体服务器源，优先从服务器获取
    if (source.type.category == SourceCategory.mediaServers) {
      final serverMetadata = await _fetchFromMediaServer(source, filePath);
      if (serverMetadata != null && serverMetadata.isComplete) {
        return serverMetadata.toVideoMetadata(
          sourceId: sourceId,
          filePath: filePath,
        );
      }
    }

    // 2. 尝试本地 NFO
    final nfoMetadata = await _nfoService.scrapeFromDirectory(...);
    if (nfoMetadata != null) {
      return _mergeMetadata(serverMetadata, nfoMetadata);
    }

    // 3. 在线刮削
    return _onlineScrape(filePath);
  }
}
```

### 7.4 数据合并策略

当多个来源都有数据时，采用字段级别的合并：

| 字段 | 优先级 |
|------|--------|
| `title` | 服务器 > NFO > TMDB |
| `overview` | 服务器 > NFO > TMDB |
| `posterUrl` | 服务器 > 本地图片 > TMDB |
| `tmdbId` | 服务器 = NFO = TMDB |
| `playbackPosition` | 服务器 > 本地 |
| `isWatched` | 服务器 > 本地 |

### 7.5 刮削状态扩展

```dart
enum ScrapeStatus {
  pending,           // 待刮削
  scraping,          // 刮削中
  completed,         // 完成（本地刮削）
  failed,            // 失败
  skipped,           // 跳过
  fromServer,        // 来自媒体服务器（新增）
}

enum ScrapeSource {
  tmdb,
  douban,
  nfo,
  jellyfin,    // 新增
  emby,        // 新增
  plex,        // 新增
}
```

---

## 8. 潜在问题与解决方案

### 8.1 网络与连接问题

| 问题 | 影响 | 解决方案 |
|------|------|----------|
| 服务器在内网，外网无法访问 | 无法远程使用 | 1. 引导用户配置反向代理<br>2. Plex 提供中继服务 |
| SSL 证书问题（自签名） | 连接失败 | 提供"忽略证书验证"选项（警告用户风险） |
| 服务器响应慢 | 列表加载慢 | 1. 分页加载<br>2. 本地缓存<br>3. 骨架屏 UI |
| Token 过期 | 操作失败 | 自动刷新 Token 或提示重新登录 |

### 8.2 数据同步问题

| 问题 | 影响 | 解决方案 |
|------|------|----------|
| 服务器数据变更 | 本地缓存过期 | 1. 监听服务器事件（WebSocket）<br>2. 定期增量同步<br>3. 手动刷新 |
| 播放进度冲突 | 多设备不同步 | 以服务器数据为准，实时上报 |
| 离线状态 | 无法获取数据 | 使用本地缓存，标记为离线模式 |

### 8.3 媒体流问题

| 问题 | 影响 | 解决方案 |
|------|------|----------|
| 格式不支持 | 播放失败 | 1. 请求服务器转码<br>2. 回退到 HLS 流 |
| 字幕不内嵌 | 字幕显示问题 | 1. 获取外挂字幕列表<br>2. 服务器烧录字幕 |
| 带宽不足 | 卡顿 | 1. 自适应码率<br>2. 用户手动选择质量 |

### 8.4 Plex 特殊问题

| 问题 | 影响 | 解决方案 |
|------|------|----------|
| 需要 plex.tv 认证 | 离线无法使用 | 支持本地 Token 认证（高级选项） |
| Plex Pass 功能 | 部分功能受限 | 检测并提示用户 |
| 服务器共享 | 权限复杂 | 明确显示当前用户权限 |

---

## 9. 兼容性问题

### 9.1 API 版本兼容

| 服务 | 版本要求 | 兼容策略 |
|------|----------|----------|
| Jellyfin | 10.8+ | 检查 `/System/Info` 返回的版本 |
| Emby | 4.6+ | 检查服务器版本 |
| Plex | 任意（使用官方 API） | 检查 machineIdentifier |

```dart
Future<void> checkServerCompatibility() async {
  final info = await api.getServerInfo();
  final version = Version.parse(info.version);

  if (version < minSupportedVersion) {
    throw IncompatibleServerException(
      '服务器版本 ${info.version} 过低，需要 $minSupportedVersion 或更高',
    );
  }
}
```

### 9.2 跨平台兼容

| 平台 | 特殊处理 |
|------|----------|
| iOS | HTTP 需要 ATS 例外或使用 HTTPS |
| Android | Android 9+ 默认禁用 HTTP 明文 |
| Windows/macOS/Linux | 无特殊限制 |

### 9.3 功能降级策略

```dart
class MediaServerCapabilities {
  final bool supportsDirectPlay;
  final bool supportsTranscoding;
  final bool supportsLiveTV;
  final bool supportsSync;
  final bool supportsPlaybackReporting;

  factory MediaServerCapabilities.detect(ServerInfo info) {
    // 根据服务器类型和版本判断能力
  }
}
```

---

## 10. 连接源移除处理

### 10.1 移除流程

与现有源一致，扩展处理媒体服务器特有的清理：

```dart
Future<void> removeMediaServerSource(String sourceId) async {
  // 1. 断开连接
  await _adapter.disconnect();

  // 2. 停止所有正在进行的同步任务
  await _syncManager.cancelSourceTasks(sourceId);

  // 3. 清理本地缓存
  await Future.wait([
    // 元数据缓存
    _metadataCache.clearSource(sourceId),
    // 图片缓存
    _imageCache.clearSource(sourceId),
    // 播放进度缓存
    _playbackCache.clearSource(sourceId),
  ]);

  // 4. 删除数据库记录
  await Future.wait([
    VideoDatabaseService().deleteBySourceId(sourceId),
    VideoLibraryCacheService().deleteBySourceId(sourceId),
    // ...其他媒体类型
  ]);

  // 5. 删除媒体库配置
  final config = await getMediaLibraryConfig();
  final newConfig = config.removePathsForSource(sourceId);
  await saveMediaLibraryConfig(newConfig);

  // 6. 删除凭证
  await removeCredential(sourceId);

  // 7. 从源列表删除
  await _removeFromSourceList(sourceId);
}
```

### 10.2 用户确认

```dart
Future<bool> confirmRemoveMediaServer(BuildContext context, SourceEntity source) async {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('移除媒体服务器'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要移除 ${source.name} 吗？'),
          const SizedBox(height: 16),
          const Text(
            '以下数据将被清除：',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text('• 该服务器的所有缓存元数据'),
          const Text('• 本地保存的播放进度'),
          const Text('• 收藏和播放列表关联'),
          const SizedBox(height: 16),
          const Text(
            '注意：服务器上的数据不会受到影响',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('移除'),
        ),
      ],
    ),
  ) ?? false;
}
```

### 10.3 数据保留选项

```dart
enum RemoveDataOption {
  /// 完全删除所有数据
  deleteAll,

  /// 保留观看历史（存储为离线记录）
  keepHistory,

  /// 保留收藏（转换为本地收藏）
  keepFavorites,

  /// 保留历史和收藏
  keepAll,
}
```

---

## 11. 数据库迁移策略

### 11.1 现有数据库架构概述

当前项目使用 **SQLite + Hive** 混合存储策略：

| 数据库 | 当前版本 | 用途 |
|--------|----------|------|
| `video_metadata.db` | **V18** | 视频元数据、剧集分组、字幕索引 |
| `music_metadata.db` | V1 | 音乐曲目、艺术家、专辑 |
| `book_library.db` | V3 | 图书、阅读进度 |
| `photo_library.db` | V2 | 照片、哈希去重 |
| `transfer.db` | V1 | 传输任务 |

### 11.2 需要添加的字段

为支持媒体服务器，需要在 `video_metadata` 表中添加以下字段：

```sql
-- V19 迁移：媒体服务器支持
ALTER TABLE video_metadata ADD COLUMN server_type TEXT;        -- jellyfin/emby/plex
ALTER TABLE video_metadata ADD COLUMN server_item_id TEXT;     -- 服务器端项目 ID
ALTER TABLE video_metadata ADD COLUMN scrape_source TEXT;      -- 刮削来源标识
ALTER TABLE video_metadata ADD COLUMN server_rating REAL;      -- 服务器端评分
ALTER TABLE video_metadata ADD COLUMN is_watched INTEGER DEFAULT 0;  -- 已观看标记
ALTER TABLE video_metadata ADD COLUMN playback_position INTEGER;     -- 播放进度(ticks)
ALTER TABLE video_metadata ADD COLUMN last_played_at INTEGER;        -- 最后播放时间
```

### 11.3 新用户 vs 已有用户处理

#### 场景分析

| 用户类型 | 数据库状态 | 处理方式 |
|---------|-----------|----------|
| **新用户** | 无数据库文件 | 直接创建 V19 版本表结构 |
| **已有用户（V18）** | 有完整 V18 数据 | 执行 V18→V19 迁移 |
| **已有用户（<V18）** | 旧版本数据 | 链式迁移 V?→V18→V19 |

#### 迁移实现

```dart
// video_database_service.dart
class VideoDatabaseService {
  static const _currentVersion = 19;  // 从 18 升级到 19

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 链式迁移：逐版本升级
    for (var v = oldVersion; v < newVersion; v++) {
      await _migrateToVersion(db, v + 1);
    }
  }

  Future<void> _migrateToVersion(Database db, int version) async {
    switch (version) {
      // ... 现有迁移 V1-V18 ...

      case 19:
        await _migrateToV19(db);
        break;
    }
  }

  /// V19 迁移：媒体服务器支持
  Future<void> _migrateToV19(Database db) async {
    logger.i('执行 V19 迁移：添加媒体服务器支持字段');

    // 使用 _safeAddColumn 防止重复升级时报错
    await _safeAddColumn(db, _table, 'server_type', 'TEXT');
    await _safeAddColumn(db, _table, 'server_item_id', 'TEXT');
    await _safeAddColumn(db, _table, 'scrape_source', 'TEXT');
    await _safeAddColumn(db, _table, 'server_rating', 'REAL');
    await _safeAddColumn(db, _table, 'is_watched', 'INTEGER DEFAULT 0');
    await _safeAddColumn(db, _table, 'playback_position', 'INTEGER');
    await _safeAddColumn(db, _table, 'last_played_at', 'INTEGER');

    // 创建索引
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_server_type
      ON $_table(server_type)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_server_item_id
      ON $_table(source_id, server_item_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_is_watched
      ON $_table(is_watched, last_played_at DESC)
    ''');

    // 为已有数据设置默认刮削来源
    await db.execute('''
      UPDATE $_table
      SET scrape_source = CASE
        WHEN tmdb_id IS NOT NULL THEN 'tmdb'
        WHEN has_nfo = 1 THEN 'nfo'
        ELSE NULL
      END
      WHERE scrape_source IS NULL AND scrape_status = 2
    ''');

    logger.i('V19 迁移完成');
  }
}
```

### 11.4 新表创建

需要创建两个新表来支持媒体服务器功能：

```dart
/// V19 迁移：创建媒体服务器缓存表
Future<void> _createMediaServerCacheTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS media_server_cache (
      id TEXT PRIMARY KEY,
      source_id TEXT NOT NULL,
      item_id TEXT NOT NULL,
      parent_id TEXT,
      item_type TEXT NOT NULL,
      metadata_json TEXT NOT NULL,
      image_urls_json TEXT,
      last_updated INTEGER NOT NULL,

      UNIQUE(source_id, item_id)
    )
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_msc_source_parent
    ON media_server_cache(source_id, parent_id)
  ''');
}

/// V19 迁移：创建播放同步队列表
Future<void> _createPlaybackSyncTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS playback_sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_id TEXT NOT NULL,
      item_id TEXT NOT NULL,
      position_ticks INTEGER NOT NULL,
      is_watched INTEGER NOT NULL DEFAULT 0,
      event_type TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pending',
      retry_count INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      synced_at INTEGER,
      error_message TEXT
    )
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_psq_status
    ON playback_sync_queue(sync_status, created_at)
  ''');
}
```

### 11.5 迁移安全策略

#### 防止数据丢失

```dart
/// 安全添加列（幂等操作）
Future<void> _safeAddColumn(
  Database db,
  String table,
  String column,
  String type,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  final exists = columns.any((col) => col['name'] == column);

  if (!exists) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    logger.d('已添加列: $table.$column ($type)');
  } else {
    logger.d('列已存在，跳过: $table.$column');
  }
}

/// 安全创建索引（幂等操作）
Future<void> _safeCreateIndex(
  Database db,
  String indexName,
  String table,
  String columns,
) async {
  await db.execute('''
    CREATE INDEX IF NOT EXISTS $indexName ON $table($columns)
  ''');
}
```

#### 迁移失败回滚

```dart
Future<void> _migrateToV19(Database db) async {
  try {
    await db.transaction((txn) async {
      // 所有迁移操作在事务中执行
      await _safeAddColumn(txn as Database, _table, 'server_type', 'TEXT');
      // ...其他操作
    });
  } catch (e, st) {
    logger.e('V19 迁移失败', e, st);
    // 迁移失败会自动回滚，保持原版本号
    rethrow;
  }
}
```

### 11.6 删除源时的数据清理

```dart
/// 删除指定媒体服务器源的所有相关数据
Future<void> deleteMediaServerData(String sourceId) async {
  await _db!.transaction((txn) async {
    // 1. 删除视频元数据
    await txn.delete(
      _table,
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );

    // 2. 删除服务器缓存
    await txn.delete(
      'media_server_cache',
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );

    // 3. 删除待同步队列
    await txn.delete(
      'playback_sync_queue',
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );

    // 4. 删除 TV 分组中该源的数据
    await txn.rawDelete('''
      DELETE FROM tv_show_groups
      WHERE group_key IN (
        SELECT DISTINCT
          CASE WHEN tmdb_id IS NOT NULL
            THEN 'tmdb_' || tmdb_id
            ELSE 'title_' || normalized_title
          END
        FROM $_table WHERE source_id = ?
      )
    ''', [sourceId]);

    // 5. 清理扫描进度
    await txn.delete(
      'scan_progress',
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
  });
}
```

### 11.7 数据迁移测试清单

| 测试场景 | 验证点 |
|---------|--------|
| 新安装 | 数据库直接创建 V19，所有表和索引正确 |
| V18→V19 升级 | 新字段已添加，已有数据保留，scrape_source 已回填 |
| V15→V19 升级 | 链式迁移正常，V15-V19 所有变更应用 |
| 升级中断后重试 | _safeAddColumn 确保幂等，不报错 |
| 删除媒体服务器源 | 所有相关数据清理完毕，不影响其他源 |

---

## 12. 客户端集成注意点（Infuse 等经验）

### 12.1 Infuse 的两种连接模式

根据 [Infuse 官方文档](https://support.firecore.com/hc/en-us/articles/360006462093-Streaming-from-Plex-Emby-and-Jellyfin)，成熟客户端通常提供两种模式：

| 模式 | 特点 | 适用场景 |
|------|------|----------|
| **Direct Mode** | 数据按需获取，不本地缓存 | 大型媒体库、网络稳定环境 |
| **Library Mode** | 预缓存到本地，离线可用 | 需要离线访问、快速浏览 |

#### 推荐策略

```dart
enum MediaServerMode {
  /// 直连模式：数据按需获取，不缓存到本地数据库
  /// 优点：快速设置、实时更新、节省存储
  /// 缺点：需要网络、每次加载
  direct,

  /// 库模式：预缓存元数据到本地
  /// 优点：快速浏览、离线可用、可与本地刮削数据合并
  /// 缺点：首次同步慢、需要同步机制
  library,
}

// 默认使用直连模式（与 Infuse 7.7+ 一致）
final defaultMode = MediaServerMode.direct;
```

### 12.2 元数据同步策略

#### Infuse 的做法

> "When connecting to a media server like Emby, Jellyfin, or Plex, Infuse will **always display metadata from the server** instead of fetching its own from TMDB."

#### 我们的策略

```dart
class MediaServerMetadataPolicy {
  /// 元数据来源优先级
  static const priority = [
    MetadataSource.mediaServer,  // 1. 服务器元数据（最高优先级）
    MetadataSource.localNfo,     // 2. 本地 NFO 补充
    MetadataSource.tmdb,         // 3. TMDB 补充缺失字段
  ];

  /// 哪些字段从服务器获取
  static const serverFields = {
    'title', 'originalTitle', 'overview', 'year',
    'genres', 'rating', 'runtime',
    'posterUrl', 'backdropUrl',
    'seasonNumber', 'episodeNumber', 'episodeTitle',
    'tmdbId', 'imdbId', 'tvdbId',
    'isWatched', 'playbackPosition',  // 播放状态必须从服务器
  };

  /// 服务器无数据时，可从 TMDB 补充的字段
  static const tmdbFallbackFields = {
    'overview',     // 简介可能服务器没有
    'posterUrl',    // 海报可能缺失
    'backdropUrl',  // 背景图可能缺失
  };
}
```

### 12.3 播放进度同步

#### 关键原则

> "When streaming, Infuse will send watched history and progress to both the media server and Trakt."

```dart
class PlaybackReporter {
  /// 播放状态上报时机
  static const reportEvents = {
    PlaybackEvent.started,      // 开始播放
    PlaybackEvent.paused,       // 暂停
    PlaybackEvent.resumed,      // 继续
    PlaybackEvent.stopped,      // 停止
    PlaybackEvent.progress,     // 定期进度（每 10 秒）
    PlaybackEvent.completed,    // 播放完成（进度 > 90%）
  };

  /// 上报到媒体服务器
  Future<void> reportToMediaServer(PlaybackState state) async {
    final endpoint = switch (state.event) {
      PlaybackEvent.started => '/Sessions/Playing',
      PlaybackEvent.stopped => '/Sessions/Playing/Stopped',
      _ => '/Sessions/Playing/Progress',
    };

    await _api.post(endpoint, {
      'ItemId': state.itemId,
      'PositionTicks': state.positionTicks,
      'IsPaused': state.isPaused,
      'PlayMethod': state.playMethod,  // DirectPlay/DirectStream/Transcode
    });
  }

  /// 同时上报到 Trakt（如果已连接）
  Future<void> reportToTrakt(PlaybackState state) async {
    if (!_traktService.isConnected) return;

    // Trakt 使用不同的 API 格式
    await _traktService.scrobble(state);
  }
}
```

### 12.4 直接播放 vs 转码

#### Infuse 的策略

> "Infuse will attempt to **direct stream all content**... there is no enforced transcoding, everything is using Direct Stream / Direct Play."

#### 决策流程

```dart
enum PlayMethod {
  directPlay,    // 直接播放原始文件
  directStream,  // 容器转换，不转码视频
  transcode,     // 服务器转码
}

class PlayMethodDecider {
  Future<PlayMethod> decide(MediaItem item, DeviceCapabilities device) async {
    // 1. 检查容器兼容性
    final containerOk = device.supportedContainers.contains(item.container);

    // 2. 检查视频编码兼容性
    final videoOk = device.supportedVideoCodecs.contains(item.videoCodec);

    // 3. 检查音频编码兼容性
    final audioOk = device.supportedAudioCodecs.contains(item.audioCodec);

    // 4. 检查字幕（可能需要烧录）
    final subtitleNeedsBurn = item.selectedSubtitle?.format == 'ass' ||
        item.selectedSubtitle?.format == 'pgs';

    if (videoOk && audioOk && containerOk && !subtitleNeedsBurn) {
      return PlayMethod.directPlay;  // 最优
    }

    if (videoOk && audioOk && !subtitleNeedsBurn) {
      return PlayMethod.directStream;  // 仅转换容器
    }

    return PlayMethod.transcode;  // 需要转码
  }
}
```

### 12.5 带宽与质量设置

#### Plex 特殊注意

> "In some cases to direct stream, you will need to adjust the bandwidth settings in Plex to be **twice the bitrate** of the video."

```dart
class StreamQualitySettings {
  /// 远程播放带宽限制（Mbps）
  final int? remoteBandwidthLimit;

  /// 本地播放带宽限制（通常无限制）
  final int? localBandwidthLimit;

  /// 是否使用 Plex Relay
  final bool usePlexRelay;

  /// 计算推荐带宽
  int getRecommendedBandwidth(MediaItem item) {
    final videoBitrate = item.videoBitrate ?? 20000000; // 默认 20Mbps
    // Plex 建议：带宽设置为视频码率的 2 倍
    return (videoBitrate * 2 / 1000000).ceil();
  }
}
```

### 12.6 InfuseSync 插件模式

Infuse 为 Library Mode 提供了 [InfuseSync 插件](https://github.com/firecore/InfuseSync)，用于增量同步：

#### 增量同步机制

```dart
/// 增量同步服务（Library Mode 使用）
class MediaServerSyncService {
  /// 获取上次同步后的变更
  Future<ChangeSet> getChanges(String sourceId) async {
    final lastSync = await _getLastSyncTime(sourceId);

    // Jellyfin/Emby: 使用 ActivityLog API
    // Plex: 使用 Library Recently Added + updatedAt
    final changes = await _api.getChanges(since: lastSync);

    return ChangeSet(
      added: changes.where((c) => c.type == 'ItemAdded').toList(),
      updated: changes.where((c) => c.type == 'ItemUpdated').toList(),
      removed: changes.where((c) => c.type == 'ItemRemoved').toList(),
    );
  }

  /// 应用变更到本地数据库
  Future<void> applyChanges(String sourceId, ChangeSet changes) async {
    await _db.transaction((txn) async {
      // 处理新增
      for (final item in changes.added) {
        await _insertOrUpdate(txn, sourceId, item);
      }

      // 处理更新
      for (final item in changes.updated) {
        await _insertOrUpdate(txn, sourceId, item);
      }

      // 处理删除
      for (final item in changes.removed) {
        await _delete(txn, sourceId, item.id);
      }
    });

    await _setLastSyncTime(sourceId, DateTime.now());
  }
}
```

### 12.7 服务器事件监听（WebSocket）

```dart
/// 实时同步服务（可选）
class MediaServerEventListener {
  WebSocket? _socket;

  Future<void> connect(String sourceId, String serverUrl) async {
    // Jellyfin/Emby WebSocket 端点
    final wsUrl = serverUrl
        .replaceFirst('http', 'ws')
        .replaceFirst('https', 'wss');

    _socket = await WebSocket.connect('$wsUrl/socket');

    _socket!.listen((event) {
      final data = jsonDecode(event);
      switch (data['MessageType']) {
        case 'LibraryChanged':
          _handleLibraryChange(sourceId, data['Data']);
          break;
        case 'UserDataChanged':
          _handleUserDataChange(sourceId, data['Data']);
          break;
        case 'PlaybackStart':
        case 'PlaybackStopped':
          _handlePlaybackEvent(sourceId, data['Data']);
          break;
      }
    });
  }
}
```

### 12.8 注意事项总结

| 类别 | 注意点 | 解决方案 |
|------|--------|----------|
| **元数据** | 服务器数据优先，不重复刮削 | 实现 MetadataSource 优先级 |
| **播放进度** | 必须实时上报到服务器 | PlaybackReporter 组件 |
| **直接播放** | 优先 DirectPlay，减少服务器负载 | PlayMethodDecider 决策 |
| **带宽** | Plex 需要 2 倍码率设置 | 动态计算推荐带宽 |
| **字幕** | ASS/PGS 可能需要烧录 | 检测并请求转码 |
| **同步** | 大库首次同步慢 | 支持 Direct Mode + 增量同步 |
| **离线** | 断网时无法获取数据 | 本地缓存 + 离线模式提示 |
| **Token** | Plex Token 可能过期 | 自动刷新机制 |

### 12.9 参考客户端

| 客户端 | 平台 | 特色 | 参考价值 |
|--------|------|------|----------|
| [Infuse](https://firecore.com/infuse) | iOS/tvOS/macOS | Direct Mode、强大解码能力 | 连接模式、元数据策略 |
| [Finamp](https://github.com/jmshrv/finamp) | 跨平台 | Jellyfin 音乐客户端（Flutter） | Dart 实现参考 |
| [Swiftfin](https://github.com/jellyfin/Swiftfin) | iOS | Jellyfin 官方 iOS 客户端 | UI/UX 参考 |
| [Jellyfin Media Player](https://github.com/jellyfin/jellyfin-media-player) | 桌面 | 基于 MPV 的客户端 | 播放器集成 |

---

## 13. 实现优先级

### 13.1 推荐实现顺序

```
Phase 1: Jellyfin（优先级：高）
├── 原因：
│   ├── 完全开源，API 文档透明
│   ├── 有官方 Dart SDK
│   └── 与 Emby API 高度兼容，可复用代码
├── 工作量：中等
└── 预计收益：高（用户群体大）

Phase 2: Emby（优先级：中）
├── 原因：
│   ├── 与 Jellyfin 架构类似
│   └── 可复用大部分 Jellyfin 代码
├── 工作量：低（复用代码）
└── 预计收益：中

Phase 3: Plex（优先级：中）
├── 原因：
│   ├── API 不同，需独立开发
│   ├── 认证流程复杂
│   └── 但用户基数大
├── 工作量：高
└── 预计收益：高
```

### 13.2 MVP 功能范围

| 功能 | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|
| 连接认证 | ✓ | ✓ | ✓ |
| 媒体库浏览 | ✓ | ✓ | ✓ |
| 视频播放 | ✓ | ✓ | ✓ |
| 元数据显示 | ✓ | ✓ | ✓ |
| 播放进度同步 | ✓ | ✓ | ✓ |
| Quick Connect | ✓ | - | - |
| 转码支持 | 后期 | 后期 | 后期 |
| Live TV | 后期 | 后期 | 后期 |

---

## 14. 参考资料

### 14.1 Jellyfin

- [Jellyfin API Overview](https://jmshrv.com/posts/jellyfin-api/)
- [Jellyfin API Authorization](https://gist.github.com/nielsvanvelzen/ea047d9028f676185832e51ffaf12a6f)
- [Jellyfin TypeScript SDK](https://typescript-sdk.jellyfin.org/)
- [Jellyfin Dart Package](https://pub.dev/documentation/jellyfin_dart/latest/)
- [Jellyfin Kotlin SDK - Authentication](https://kotlin-sdk.jellyfin.org/guide/authentication.html)

### 14.2 Emby

- [Emby REST API Documentation](https://dev.emby.media/doc/restapi/index.html)
- [Emby API Reference](https://dev.emby.media/reference/index.html)
- [Emby User Authentication](https://dev.emby.media/doc/restapi/User-Authentication.html)
- [Emby API Key Authentication](https://github.com/MediaBrowser/Emby/wiki/Api-Key-Authentication)

### 14.3 Plex

- [Plex Media Server Developer Docs](https://developer.plex.tv/pms/)
- [Finding X-Plex-Token](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/)
- [Plex Media Server URL Commands](https://support.plex.tv/articles/201638786-plex-media-server-url-commands/)
- [Python PlexAPI](https://python-plexapi.readthedocs.io/en/latest/)
- [Plex API Documentation (Community)](https://plexapi.dev/)

### 14.4 对比文章

- [Best Media Server 2025 Comparison](https://www.videosdk.live/developer-hub/media-server/best-media-server)
- [Jellyfin vs Plex vs Emby Comparison](https://mediapeanut.com/jellyfin-vs-plex-vs-emby-comparison/)
- [NAS Compares: Best Plex/Jellyfin/Emby NAS 2025](https://nascompares.com/2025/12/26/best-plex-jellyfin-or-emby-nas-of-2025/)

---

## 附录 A: Jellyfin/Emby 共用代码架构

由于 Jellyfin 是 Emby 的分支，可以创建共用基类：

```dart
/// Jellyfin/Emby 共用 API 基类
abstract class EmbyLikeApi {
  final String baseUrl;
  final String? accessToken;

  Future<AuthResult> authenticate(String username, String password);
  Future<List<Library>> getLibraries(String userId);
  Future<ItemsResult> getItems(String userId, ItemsQuery query);
  Future<Item> getItem(String itemId);

  // 子类实现差异部分
  String get authHeaderScheme;  // 'MediaBrowser' vs 'Emby'
  String get streamEndpoint;     // 不同的流媒体端点
}

class JellyfinApi extends EmbyLikeApi {
  @override
  String get authHeaderScheme => 'MediaBrowser';
}

class EmbyApi extends EmbyLikeApi {
  @override
  String get authHeaderScheme => 'Emby';
}
```

---

## 附录 B: 数据库 Schema 扩展

```sql
-- 添加媒体服务器来源字段
ALTER TABLE video_metadata ADD COLUMN server_type TEXT;
ALTER TABLE video_metadata ADD COLUMN server_item_id TEXT;
ALTER TABLE video_metadata ADD COLUMN scrape_source TEXT;

-- 创建服务器元数据缓存表
CREATE TABLE IF NOT EXISTS media_server_cache (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    metadata_json TEXT NOT NULL,
    last_updated INTEGER NOT NULL,
    FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE
);

-- 创建播放进度同步表
CREATE TABLE IF NOT EXISTS playback_sync_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    position_ticks INTEGER NOT NULL,
    is_watched INTEGER NOT NULL,
    sync_status TEXT NOT NULL,  -- pending, syncing, synced, failed
    created_at INTEGER NOT NULL,
    synced_at INTEGER
);
```

---

*文档结束*
