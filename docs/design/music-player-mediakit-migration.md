# 音乐播放器 media_kit 迁移设计文档

> 版本：1.0
> 日期：2024-12-30
> 状态：设计中

## 目录

1. [背景与目标](#1-背景与目标)
2. [现状分析](#2-现状分析)
3. [技术方案对比](#3-技术方案对比)
4. [架构设计](#4-架构设计)
5. [接口设计](#5-接口设计)
6. [音频直通与空间音频](#6-音频直通与空间音频)
7. [实现计划](#7-实现计划)
8. [迁移策略](#8-迁移策略)
9. [测试计划](#9-测试计划)
10. [风险评估](#10-风险评估)

---

## 1. 背景与目标

### 1.1 背景

当前音乐播放器使用 `just_audio` 库，依赖平台原生解码器（iOS 的 AVFoundation、Android 的 ExoPlayer）。这导致以下高级音频格式无法播放：

- **Dolby Digital (AC3)** - 常见于电影原声、DVD 音轨
- **Dolby Digital Plus (EAC3)** - 流媒体高清音频
- **Dolby TrueHD** - 蓝光无损音频
- **Dolby Atmos** - 空间音频（封装在 TrueHD/EAC3 JOC 中）
- **DTS / DTS-HD MA** - 蓝光高清音频
- **DTS:X** - DTS 空间音频

### 1.2 目标

1. **格式支持**：支持播放所有主流音频格式，包括杜比和 DTS 系列
2. **音频直通**：支持将原始比特流直通到外部功放/Soundbar 解码
3. **保持现有功能**：锁屏控制、灵动岛、通知栏、蓝牙控制等系统集成
4. **统一引擎**：音乐和视频使用相同的 media_kit 引擎，减少维护成本

### 1.3 非目标

- 不实现 Apple Spatial Audio 渲染（需要 Apple 授权）
- 不实现耳机头部追踪（系统级功能）
- 不改变现有的播放队列、收藏、历史等业务逻辑

---

## 2. 现状分析

### 2.1 当前架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                     当前架构: just_audio + audio_service            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    MusicPlayerNotifier                       │   │
│  │  lib/features/music/presentation/providers/                  │   │
│  │  music_player_provider.dart (1626 行)                        │   │
│  │                                                               │   │
│  │  职责：                                                       │   │
│  │  - 播放队列管理                                               │   │
│  │  - 播放模式 (循环/随机/单曲)                                  │   │
│  │  - 交叉淡化 (Crossfade)                                       │   │
│  │  - NCM 解密播放                                               │   │
│  │  - 状态持久化                                                 │   │
│  │  - Android 灵动岛集成                                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    MusicAudioHandler                         │   │
│  │  lib/features/music/data/services/                           │   │
│  │  music_audio_handler.dart (720 行)                           │   │
│  │                                                               │   │
│  │  职责：                                                       │   │
│  │  - 封装 just_audio AudioPlayer                                │   │
│  │  - 集成 audio_service (BaseAudioHandler)                      │   │
│  │  - iOS 锁屏/灵动岛控制                                        │   │
│  │  - Android 通知栏控制                                         │   │
│  │  - 蓝牙/CarPlay 控制                                          │   │
│  │  - 封面图片处理和缓存                                         │   │
│  │  - 生命周期管理                                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│              ┌───────────────┼───────────────┐                     │
│              ▼               ▼               ▼                     │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐          │
│  │  just_audio   │  │ audio_service │  │ audio_session │          │
│  │  AudioPlayer  │  │               │  │               │          │
│  │               │  │ - mediaItem   │  │ - 音频中断    │          │
│  │ - 解码播放   │  │ - playbackSt. │  │ - 设备切换    │          │
│  │ - 缓存      │  │ - queue       │  │               │          │
│  └───────────────┘  └───────────────┘  └───────────────┘          │
│         │                                                          │
│         ▼                                                          │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │                  平台原生解码器                             │    │
│  │  iOS: AVFoundation  |  Android: ExoPlayer                  │    │
│  │  ❌ 不支持 AC3/DTS/TrueHD 等格式                           │    │
│  └───────────────────────────────────────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 已实现的功能清单

#### 核心播放功能

| 功能 | 实现位置 | 说明 |
|------|---------|------|
| 播放/暂停/停止 | MusicAudioHandler | 通过 audio_service 广播状态 |
| 上一曲/下一曲 | MusicPlayerNotifier | 支持锁屏/蓝牙控制 |
| 进度控制 (Seek) | MusicAudioHandler | 支持拖动和快进快退 |
| 音量控制 | MusicPlayerNotifier | 0.0-1.0 范围 |
| 播放模式 | MusicPlayerNotifier | 列表循环/单曲循环/随机 |
| 播放速度 | MusicAudioHandler | 支持变速播放 |

#### 高级功能

| 功能 | 实现位置 | 说明 |
|------|---------|------|
| 交叉淡化 | MusicPlayerNotifier | 等功率曲线，双播放器实现 |
| 淡入淡出 | MusicPlayerNotifier | 正弦曲线，可配置时长 |
| 边下边播 | MusicPlayerNotifier | LockCachingAudioSource |
| 播放缓存 | MusicAudioCacheService | 持久化缓存到本地 |
| NCM 解密 | NcmDecryptService | 网易云音乐格式支持 |
| 元数据提取 | MusicMetadataService | 后台异步提取 |

#### 系统集成

| 功能 | 实现位置 | 平台 |
|------|---------|------|
| 锁屏控制 | MusicAudioHandler | iOS/Android |
| 灵动岛 | MusicAudioHandler + 原生修复 | iOS |
| 控制中心 | MusicAudioHandler | iOS |
| 通知栏 | MusicAudioHandler | Android |
| 灵动悬浮窗 | AndroidDynamicIslandService | Android |
| 蓝牙控制 | audio_service 自动 | iOS/Android |
| CarPlay | audio_service 自动 | iOS |
| 来电暂停 | audio_session | iOS/Android |
| 耳机拔出暂停 | audio_session | iOS/Android |

### 2.3 关键依赖

```yaml
# pubspec.yaml 当前配置
dependencies:
  just_audio: ^0.9.42
  just_audio_windows: ^0.2.2
  just_audio_media_kit: ^2.1.0  # macOS/Linux
  audio_service:
    path: packages/audio_service_fixed  # 修复版本
  audio_session: ^0.1.25
  media_kit: ^1.1.11  # 视频播放已使用
  media_kit_video: ^1.2.5
  media_kit_libs_video: ^1.0.5
```

---

## 3. 技术方案对比

### 3.1 方案 A：保持 just_audio + 转码

**原理**：检测到不支持的格式时，先用 FFmpeg 转码为 AAC/FLAC，再播放

```
AC3/DTS 文件 → FFmpeg 转码 → AAC/FLAC → just_audio 播放
```

**优点**：
- 改动最小，仅需添加转码层
- 系统集成无需修改

**缺点**：
- 首次播放延迟（转码耗时）
- 丢失空间音频信息
- 无法实现音频直通
- 占用额外存储空间

### 3.2 方案 B：迁移到 media_kit（推荐）

**原理**：使用 media_kit (libmpv/FFmpeg) 替代 just_audio，保持 audio_service 集成

```
任意格式文件 → media_kit Player (FFmpeg 解码) → 音频输出
                     ↓
              audio_service (系统控制)
```

**优点**：
- 支持所有音频格式
- 支持音频直通
- 与视频播放器统一引擎
- 无转码延迟

**缺点**：
- 需要重新实现 audio_service 集成
- 系统集成需要手动维护
- 开发工作量较大

### 3.3 方案对比总结

| 维度 | 方案 A (转码) | 方案 B (media_kit) |
|------|--------------|-------------------|
| 开发工作量 | ⭐ 小 | ⭐⭐⭐⭐ 大 |
| 格式支持 | ✅ 全部 | ✅ 全部 |
| 音频直通 | ❌ 不支持 | ✅ 支持 |
| 播放延迟 | ❌ 有延迟 | ✅ 无延迟 |
| 音质损失 | ❌ 有损失 | ✅ 无损失 |
| 系统集成 | ✅ 无需修改 | ⚠️ 需重新实现 |
| 维护成本 | ⭐⭐ 中等 | ⭐ 低（统一引擎） |

**结论**：选择方案 B，虽然开发工作量大，但长期收益更高。

---

## 4. 架构设计

### 4.1 新架构总览

```
┌─────────────────────────────────────────────────────────────────────┐
│                     新架构: media_kit + audio_service               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    MusicPlayerNotifier                       │   │
│  │  (保持不变 - 业务逻辑层)                                      │   │
│  │                                                               │   │
│  │  - 播放队列管理                                               │   │
│  │  - 播放模式控制                                               │   │
│  │  - 交叉淡化                                                   │   │
│  │  - NCM 解密                                                   │   │
│  │  - 状态持久化                                                 │   │
│  │  - Android 灵动岛                                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              │ 接口不变                             │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │           MusicMediaKitAudioHandler (新)                     │   │
│  │  extends BaseAudioHandler                                    │   │
│  │                                                               │   │
│  │  职责：                                                       │   │
│  │  - 封装 media_kit Player                                     │   │
│  │  - 实现 audio_service 接口                                   │   │
│  │  - 同步 playbackState / mediaItem / queue                    │   │
│  │  - 管理音频直通配置                                           │   │
│  │  - 封面图片处理                                               │   │
│  │  - 生命周期管理                                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│      ┌───────────────────────┼───────────────────────┐             │
│      │                       │                       │             │
│      ▼                       ▼                       ▼             │
│  ┌────────────┐      ┌───────────────┐      ┌───────────────┐     │
│  │ media_kit  │      │ audio_service │      │ audio_session │     │
│  │   Player   │      │               │      │               │     │
│  │            │      │ - mediaItem   │      │ - 音频中断    │     │
│  │ - FFmpeg   │      │ - playbackSt. │      │ - 设备切换    │     │
│  │ - libmpv   │      │ - queue       │      │ - 焦点管理    │     │
│  │ - 直通    │      │ - controls    │      │               │     │
│  └────────────┘      └───────────────┘      └───────────────┘     │
│        │                                                           │
│        ▼                                                           │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │              MusicAudioPassthroughService (新)             │    │
│  │                                                            │    │
│  │  - 检测音频输出设备能力                                     │    │
│  │  - 配置 MPV 音频直通参数                                    │    │
│  │  - 支持 HDMI/eARC/SPDIF                                    │    │
│  └───────────────────────────────────────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 模块职责

#### 4.2.1 MusicPlayerNotifier (保持不变)

```
lib/features/music/presentation/providers/music_player_provider.dart

职责：
├── 播放队列管理
│   ├── setQueue() - 设置播放列表
│   ├── addToQueue() - 添加到队列
│   ├── removeFromQueue() - 从队列移除
│   └── reorderQueue() - 队列重排序
│
├── 播放控制
│   ├── play() - 播放指定音乐
│   ├── playAt() - 播放队列中指定索引
│   ├── playNext() - 下一曲
│   ├── playPrevious() - 上一曲
│   └── playOrPause() - 播放/暂停切换
│
├── 播放模式
│   ├── togglePlayMode() - 切换模式
│   └── setPlayMode() - 设置模式
│
├── 高级功能
│   ├── 交叉淡化 - _startCrossfade()
│   ├── NCM 解密 - _getDecryptedNcmFile()
│   ├── 元数据提取 - _extractMetadataInBackground()
│   └── 状态持久化 - _savePlayStateIfNeeded()
│
└── Android 灵动岛
    ├── _startDynamicIsland()
    ├── _updateDynamicIsland()
    └── _hideDynamicIsland()
```

#### 4.2.2 MusicMediaKitAudioHandler (新建)

```
lib/features/music/data/services/music_media_kit_handler.dart

职责：
├── 播放器管理
│   ├── init() - 初始化 media_kit Player
│   ├── dispose() - 释放资源
│   └── player - 获取 Player 实例
│
├── BaseAudioHandler 实现
│   ├── play() - 开始播放
│   ├── pause() - 暂停播放
│   ├── stop() - 停止播放
│   ├── seek() - 跳转位置
│   ├── skipToNext() - 下一曲
│   ├── skipToPrevious() - 上一曲
│   ├── setSpeed() - 设置播放速度
│   └── setRepeatMode() / setShuffleMode()
│
├── 状态同步
│   ├── _broadcastPlaybackState() - 广播播放状态
│   ├── _updateMediaItem() - 更新媒体信息
│   └── _syncQueueToAudioService() - 同步队列
│
├── 音频源管理
│   ├── setAudioSource() - 设置播放源
│   ├── setCurrentMusic() - 设置当前音乐（含元数据）
│   └── updateArtwork() - 更新封面
│
├── 音频直通
│   ├── setPassthroughEnabled() - 启用/禁用直通
│   └── _configurePassthrough() - 配置 MPV 参数
│
└── 生命周期
    ├── didChangeAppLifecycleState() - 处理 App 前后台切换
    └── _reactivateAudioSession() - 重新激活音频会话
```

#### 4.2.3 MusicAudioPassthroughService (新建)

```
lib/features/music/data/services/music_audio_passthrough_service.dart

职责：
├── 能力检测
│   ├── detectCapability() - 检测音频输出设备能力
│   ├── getOutputDevice() - 获取当前输出设备类型
│   └── getSupportedCodecs() - 获取支持的直通编码
│
├── 直通配置
│   ├── applyToPlayer() - 应用配置到 Player
│   ├── getMpvSpdifProperty() - 生成 MPV 直通参数
│   └── getOptimalAudioDevice() - 获取最优音频设备
│
└── 用户设置
    ├── setPassthroughMode() - 设置直通模式（自动/启用/禁用）
    └── setEnabledCodecs() - 设置启用的直通编码
```

### 4.3 文件结构

```
lib/features/music/
├── data/
│   ├── services/
│   │   ├── music_audio_handler.dart          # 保留（兼容模式）
│   │   ├── music_media_kit_handler.dart      # 新增（主要实现）
│   │   ├── music_audio_passthrough_service.dart  # 新增
│   │   ├── music_audio_cache_service.dart    # 保留
│   │   ├── music_cover_cache_service.dart    # 保留
│   │   ├── music_favorites_service.dart      # 保留
│   │   ├── music_metadata_service.dart       # 保留
│   │   ├── music_tag_writer_service.dart     # 保留
│   │   ├── ncm_decrypt_service.dart          # 保留
│   │   └── android_dynamic_island_service.dart  # 保留
│   │
│   └── repositories/
│       └── ...
│
├── domain/
│   ├── entities/
│   │   ├── music_item.dart                   # 保留
│   │   └── music_audio_config.dart           # 新增（直通配置实体）
│   └── ...
│
├── presentation/
│   ├── providers/
│   │   ├── music_player_provider.dart        # 修改（切换底层引擎）
│   │   ├── music_settings_provider.dart      # 修改（添加直通设置）
│   │   └── ...
│   │
│   ├── pages/
│   │   └── music_settings_page.dart          # 修改（添加直通设置 UI）
│   │
│   └── widgets/
│       └── ...
│
└── ...
```

---

## 5. 接口设计

### 5.1 MusicMediaKitAudioHandler 接口

```dart
/// 基于 media_kit 的音乐播放 AudioHandler
///
/// 功能：
/// - 使用 media_kit Player 解码播放（支持 AC3/DTS/TrueHD 等）
/// - 集成 audio_service 实现系统媒体控制
/// - 支持音频直通模式（HDMI/eARC 场景）
class MusicMediaKitAudioHandler extends BaseAudioHandler
    with SeekHandler, WidgetsBindingObserver {

  // ==================== 构造与初始化 ====================

  MusicMediaKitAudioHandler();

  /// 初始化播放器
  /// 必须在使用前调用
  Future<void> init();

  /// 释放资源
  Future<void> dispose();

  // ==================== 播放器访问 ====================

  /// 获取底层 media_kit Player
  Player get player;

  /// 获取当前封面数据
  Uint8List? get currentArtworkData;

  /// 获取当前音乐项
  MusicItem? get currentMusicItem;

  /// 获取当前队列索引
  int get currentIndex;

  // ==================== 音频源设置 ====================

  /// 设置音频源
  ///
  /// [url] 音频文件 URL（支持 file://, http://, https://）
  /// [headers] HTTP 请求头（可选）
  Future<Duration?> setAudioSource(String url, {Map<String, String>? headers});

  /// 设置当前播放的音乐
  ///
  /// [music] 音乐项
  /// [artworkData] 封面数据（可选）
  Future<void> setCurrentMusic(MusicItem music, {Uint8List? artworkData});

  /// 更新封面图片
  Future<void> updateArtwork(Uint8List artworkData);

  /// 更新时长
  void updateDuration(Duration duration);

  // ==================== 播放队列 ====================

  /// 设置播放队列
  ///
  /// [items] 音乐列表
  /// [startIndex] 起始索引
  void setQueue(List<MusicItem> items, {int startIndex = 0});

  /// 更新当前索引
  void updateCurrentIndex(int index);

  /// 外部切歌回调
  /// 当用户通过锁屏/控制中心/蓝牙切歌时调用
  Future<void> Function(int index)? onSkipToIndex;

  // ==================== BaseAudioHandler 实现 ====================

  @override
  Future<void> play();

  @override
  Future<void> pause();

  @override
  Future<void> stop();

  @override
  Future<void> seek(Duration position);

  @override
  Future<void> skipToNext();

  @override
  Future<void> skipToPrevious();

  @override
  Future<void> skipToQueueItem(int index);

  @override
  Future<void> setSpeed(double speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode);

  // ==================== 音频控制 ====================

  /// 设置音量
  Future<void> setVolume(double volume);

  /// 准备切换到新歌曲
  /// 在设置新歌曲之前调用，确保旧的播放状态被正确清理
  Future<void> prepareForNewTrack();

  // ==================== 音频直通 ====================

  /// 设置音频直通模式
  ///
  /// [enabled] 是否启用直通
  /// [codecs] 启用的直通编码（null 表示全部支持的编码）
  Future<void> setPassthroughEnabled({
    required bool enabled,
    List<AudioCodec>? codecs,
  });

  /// 获取当前直通配置
  AudioPassthroughConfig get passthroughConfig;

  // ==================== 流订阅 ====================

  /// 播放位置流
  Stream<Duration> get positionStream;

  /// 缓冲位置流
  Stream<Duration> get bufferedPositionStream;

  /// 时长流
  Stream<Duration> get durationStream;

  /// 播放状态流
  Stream<bool> get playingStream;

  /// 缓冲状态流
  Stream<bool> get bufferingStream;

  /// 播放完成流
  Stream<void> get completedStream;
}
```

### 5.2 MusicAudioPassthroughService 接口

```dart
/// 音乐播放的音频直通服务
///
/// 检测设备是否支持音频直通，并配置 MPV 输出
class MusicAudioPassthroughService {
  factory MusicAudioPassthroughService();

  // ==================== 能力检测 ====================

  /// 检测当前音频输出设备的直通能力
  ///
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<AudioPassthroughCapability> detectCapability({
    bool forceRefresh = false,
  });

  /// 获取当前输出设备类型
  Future<AudioOutputDevice> getCurrentOutputDevice();

  /// 检查指定编码是否支持直通
  Future<bool> isCodecSupported(AudioCodec codec);

  // ==================== 直通配置 ====================

  /// 应用直通配置到 media_kit Player
  ///
  /// [player] media_kit Player 实例
  /// [config] 直通配置
  Future<void> applyToPlayer(Player player, AudioPassthroughConfig config);

  /// 生成 MPV audio-spdif 属性值
  ///
  /// [codecs] 要直通的编码列表
  String getMpvSpdifProperty(List<AudioCodec> codecs);

  /// 获取最优音频设备名称
  ///
  /// 在多个输出设备可用时选择最优的（如优先 HDMI）
  Future<String?> getOptimalAudioDevice();

  // ==================== 用户设置 ====================

  /// 获取用户的直通设置
  AudioPassthroughConfig getUserConfig();

  /// 保存用户的直通设置
  Future<void> saveUserConfig(AudioPassthroughConfig config);

  // ==================== 清理 ====================

  /// 清除能力检测缓存
  void clearCache();
}

/// 音频直通配置
class AudioPassthroughConfig {
  const AudioPassthroughConfig({
    this.mode = AudioPassthroughMode.auto,
    this.enabledCodecs,
    this.exclusiveMode = false,
  });

  /// 直通模式
  final AudioPassthroughMode mode;

  /// 用户启用的直通编码（null 表示使用设备支持的全部）
  final List<AudioCodec>? enabledCodecs;

  /// 是否使用独占模式（WASAPI Exclusive / CoreAudio Exclusive）
  final bool exclusiveMode;

  /// 从 Map 创建
  factory AudioPassthroughConfig.fromMap(Map<String, dynamic> map);

  /// 转为 Map
  Map<String, dynamic> toMap();

  /// 获取实际启用的编码列表
  List<AudioCodec> getEffectiveCodecs(AudioPassthroughCapability capability);
}
```

### 5.3 实体类

```dart
/// 音乐音频配置实体
/// lib/features/music/domain/entities/music_audio_config.dart

/// 音频输出设备类型（复用视频模块定义）
/// 参见：lib/features/video/domain/entities/audio_capability.dart
// enum AudioOutputDevice { ... }

/// 音频编码格式（复用视频模块定义）
/// 参见：lib/features/video/domain/entities/audio_capability.dart
// enum AudioCodec { ... }

/// 音频直通模式（复用视频模块定义）
/// 参见：lib/features/video/domain/entities/audio_capability.dart
// enum AudioPassthroughMode { ... }

/// 音频直通能力（复用视频模块定义）
/// 参见：lib/features/video/domain/entities/audio_capability.dart
// class AudioPassthroughCapability { ... }
```

### 5.4 Provider 修改

```dart
/// 音乐设置 Provider 扩展
/// lib/features/music/presentation/providers/music_settings_provider.dart

class MusicSettings {
  // ... 现有字段

  /// 音频直通设置（新增）
  final AudioPassthroughConfig passthroughConfig;

  /// 是否使用 media_kit 引擎（新增，用于兼容模式切换）
  final bool useMediaKitEngine;
}

class MusicSettingsNotifier extends StateNotifier<MusicSettings> {
  // ... 现有方法

  /// 设置音频直通配置（新增）
  Future<void> setPassthroughConfig(AudioPassthroughConfig config);

  /// 切换播放引擎（新增）
  Future<void> setUseMediaKitEngine(bool value);
}
```

---

## 6. 音频直通与空间音频

### 6.1 音频直通原理

```
┌─────────────────────────────────────────────────────────────────────┐
│                         音频直通原理                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  普通模式（解码后输出）：                                            │
│  ┌──────────┐   解码    ┌──────────┐   PCM    ┌──────────┐        │
│  │ AC3/DTS  │ ───────► │  FFmpeg  │ ───────► │  DAC     │        │
│  │ 文件     │          │  解码器   │          │  输出    │        │
│  └──────────┘          └──────────┘          └──────────┘        │
│                              ↓                                     │
│                        丢失空间信息                                 │
│                                                                     │
│  直通模式（比特流输出）：                                            │
│  ┌──────────┐  透传     ┌──────────┐  HDMI   ┌──────────┐        │
│  │ AC3/DTS  │ ───────► │  SPDIF   │ ───────► │  功放    │        │
│  │ 文件     │  原始流   │  封装    │  eARC   │  解码    │        │
│  └──────────┘          └──────────┘          └──────────┘        │
│                              ↓                                     │
│                        保留空间信息                                 │
│                        由外部设备解码                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 MPV 直通配置

```dart
/// MPV 音频直通配置示例
Future<void> configurePassthrough(NativePlayer player, AudioPassthroughCapability cap) async {
  if (!cap.isSupported) return;

  // 1. 设置 SPDIF 直通编码
  // 格式："ac3,eac3,dts,dts-hd,truehd"
  final codecs = cap.supportedCodecs.map((c) => c.mpvName).join(',');
  await player.setProperty('audio-spdif', codecs);

  // 2. 设置音频声道
  await player.setProperty('audio-channels', 'auto-safe');

  // 3. 可选：设置独占模式（Windows WASAPI / macOS CoreAudio）
  if (Platform.isWindows) {
    await player.setProperty('audio-exclusive', 'yes');
  }

  // 4. 可选：指定音频设备
  final device = await getOptimalAudioDevice();
  if (device != null) {
    await player.setProperty('audio-device', device);
  }
}
```

### 6.3 不同设备的空间音频支持

#### 6.3.1 HomePod / HomePod mini

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HomePod 音频路径                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  传输协议：AirPlay 2                                                │
│  ├── 支持格式：AAC (最高 256kbps), ALAC (无损)                      │
│  ├── 不支持：AC3, DTS, TrueHD 直通                                  │
│  └── 限制：AirPlay 会对音频重新编码                                  │
│                                                                     │
│  Dolby Atmos 支持：                                                 │
│  ├── 仅支持 Apple Music 内容                                        │
│  ├── 需要 Apple 的空间音频元数据格式                                 │
│  └── 第三方 App 无法发送 Atmos 音频                                  │
│                                                                     │
│  实现方案：                                                          │
│  ├── 方案 A：降级为立体声播放（当前可实现）                           │
│  │   - 解码 AC3/DTS 为 PCM，通过 AirPlay 发送                        │
│  │   - 丢失空间信息，但可以正常播放                                   │
│  │                                                                   │
│  └── 方案 B：不支持（告知用户）                                       │
│      - 检测到 AirPlay 输出时提示用户                                  │
│      - 建议使用有线连接获得最佳效果                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

#### 6.3.2 Sony / Denon / 其他功放

```
┌─────────────────────────────────────────────────────────────────────┐
│                       外部功放音频路径                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  连接方式 1：HDMI eARC（推荐）                                       │
│  ├── 带宽：37 Mbps                                                  │
│  ├── 支持格式：                                                      │
│  │   ✅ Dolby TrueHD + Atmos                                        │
│  │   ✅ DTS-HD MA + DTS:X                                           │
│  │   ✅ 7.1ch LPCM                                                  │
│  └── 适用设备：Apple TV, Mac mini, Android TV                       │
│                                                                     │
│  连接方式 2：HDMI ARC                                                │
│  ├── 带宽：~1 Mbps                                                  │
│  ├── 支持格式：                                                      │
│  │   ✅ Dolby Digital (AC3)                                         │
│  │   ✅ DTS                                                         │
│  │   ❌ TrueHD / DTS-HD MA（带宽不足）                               │
│  └── 适用设备：大部分电视                                            │
│                                                                     │
│  连接方式 3：光纤 / 同轴 (S/PDIF)                                    │
│  ├── 带宽：~1.5 Mbps                                                │
│  ├── 支持格式：                                                      │
│  │   ✅ Dolby Digital (AC3)                                         │
│  │   ✅ DTS                                                         │
│  │   ❌ 高比特率格式                                                 │
│  └── 适用设备：传统音响设备                                          │
│                                                                     │
│  连接方式 4：蓝牙                                                    │
│  ├── 协议：SBC, AAC, aptX, LDAC                                     │
│  ├── 支持格式：                                                      │
│  │   ✅ 立体声（重编码）                                             │
│  │   ❌ 环绕声 / 空间音频                                            │
│  └── 限制：所有蓝牙协议都不支持环绕声直通                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

#### 6.3.3 支持矩阵

| 设备类型 | 连接方式 | AC3 | EAC3 | TrueHD | DTS | DTS-HD | Atmos | DTS:X |
|---------|---------|-----|------|--------|-----|--------|-------|-------|
| Apple TV 4K | HDMI eARC | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mac mini | HDMI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Android TV | HDMI eARC | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| iPhone/iPad | AirPlay→HomePod | ❌ | ❌ | ❌ | ❌ | ❌ | ❌* | ❌ |
| iPhone/iPad | 蓝牙→音响 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Windows PC | HDMI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Linux PC | HDMI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> *: HomePod 的 Atmos 仅支持 Apple Music 内容

### 6.4 实现建议

```dart
/// 音频输出检测与用户提示
class AudioOutputAdvisor {
  /// 检测当前输出并给出建议
  Future<AudioOutputAdvice> getAdvice(AudioCodec sourceCodec) async {
    final device = await detectOutputDevice();
    final capability = await detectCapability();

    // AirPlay 输出
    if (device == AudioOutputDevice.airplay) {
      return AudioOutputAdvice(
        canPlayOriginal: false,
        degradedMode: true,
        message: '当前通过 AirPlay 输出，空间音频将降级为立体声。'
                 '如需完整空间音频体验，请使用 HDMI 连接支持 Atmos 的设备。',
      );
    }

    // 蓝牙输出
    if (device == AudioOutputDevice.bluetooth) {
      return AudioOutputAdvice(
        canPlayOriginal: false,
        degradedMode: true,
        message: '蓝牙不支持环绕声直通，将播放立体声版本。',
      );
    }

    // HDMI/eARC 输出
    if (device == AudioOutputDevice.hdmi || device == AudioOutputDevice.arc) {
      if (capability.supportedCodecs.contains(sourceCodec)) {
        return AudioOutputAdvice(
          canPlayOriginal: true,
          degradedMode: false,
          message: '已启用音频直通，将由外部设备解码播放。',
        );
      }
    }

    // 默认：解码后输出
    return AudioOutputAdvice(
      canPlayOriginal: false,
      degradedMode: false,
      message: '将解码为多声道 PCM 播放。',
    );
  }
}
```

---

## 7. 实现计划

### 7.1 阶段划分

```
┌─────────────────────────────────────────────────────────────────────┐
│                         实现阶段规划                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  阶段 1：基础框架 (2-3 天)                                          │
│  ├── 创建 MusicMediaKitAudioHandler 基础结构                        │
│  ├── 实现 media_kit Player 封装                                     │
│  ├── 实现基础播放控制 (play/pause/stop/seek)                        │
│  └── 验证基础播放功能                                               │
│                                                                     │
│  阶段 2：audio_service 集成 (3-4 天)                                │
│  ├── 实现 BaseAudioHandler 所有方法                                 │
│  ├── 实现 playbackState 状态同步                                    │
│  ├── 实现 mediaItem 媒体信息同步                                    │
│  ├── 实现 queue 队列同步                                            │
│  ├── 测试 iOS 锁屏/灵动岛控制                                       │
│  └── 测试 Android 通知栏控制                                        │
│                                                                     │
│  阶段 3：音频直通 (2 天)                                            │
│  ├── 创建 MusicAudioPassthroughService                              │
│  ├── 实现能力检测逻辑                                               │
│  ├── 实现 MPV 直通配置                                              │
│  └── 添加直通设置 UI                                                │
│                                                                     │
│  阶段 4：功能迁移 (3-4 天)                                          │
│  ├── 修改 MusicPlayerNotifier 使用新 Handler                        │
│  ├── 迁移交叉淡化功能                                               │
│  ├── 迁移边下边播功能                                               │
│  ├── 迁移 NCM 解密播放                                              │
│  └── 迁移元数据提取                                                 │
│                                                                     │
│  阶段 5：测试与优化 (2-3 天)                                        │
│  ├── 各平台功能测试                                                 │
│  ├── 各格式播放测试                                                 │
│  ├── 音频直通测试（需外部设备）                                      │
│  ├── 性能测试与优化                                                 │
│  └── Bug 修复                                                       │
│                                                                     │
│  总计：12-16 天                                                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.2 详细任务清单

#### 阶段 1：基础框架

- [ ] 1.1 创建 `music_media_kit_handler.dart` 文件
- [ ] 1.2 实现构造函数和 `init()` 方法
- [ ] 1.3 实现 `dispose()` 方法
- [ ] 1.4 封装 media_kit Player 实例
- [ ] 1.5 实现 `play()` / `pause()` / `stop()`
- [ ] 1.6 实现 `seek()` 方法
- [ ] 1.7 实现 `setVolume()` 方法
- [ ] 1.8 实现 `setSpeed()` 方法
- [ ] 1.9 实现位置/时长/缓冲 Stream
- [ ] 1.10 编写单元测试验证基础功能

#### 阶段 2：audio_service 集成

- [ ] 2.1 继承 `BaseAudioHandler` 和 `SeekHandler`
- [ ] 2.2 实现 `_broadcastPlaybackState()` 方法
- [ ] 2.3 实现 `setCurrentMusic()` 更新 mediaItem
- [ ] 2.4 实现 `setQueue()` 同步队列
- [ ] 2.5 实现 `skipToNext()` / `skipToPrevious()`
- [ ] 2.6 实现 `skipToQueueItem()`
- [ ] 2.7 实现 `setRepeatMode()` / `setShuffleMode()`
- [ ] 2.8 实现封面图片处理和缓存
- [ ] 2.9 实现 App 生命周期监听
- [ ] 2.10 实现 audio_session 配置
- [ ] 2.11 iOS 锁屏控制测试
- [ ] 2.12 iOS 灵动岛测试
- [ ] 2.13 Android 通知栏测试
- [ ] 2.14 蓝牙控制测试

#### 阶段 3：音频直通

- [ ] 3.1 创建 `music_audio_passthrough_service.dart`
- [ ] 3.2 实现 `detectCapability()` 能力检测
- [ ] 3.3 实现 `applyToPlayer()` 配置应用
- [ ] 3.4 实现 `getMpvSpdifProperty()` 参数生成
- [ ] 3.5 创建 `music_audio_config.dart` 实体类
- [ ] 3.6 修改 `MusicSettings` 添加直通配置
- [ ] 3.7 创建直通设置 UI 组件
- [ ] 3.8 集成到音乐设置页面

#### 阶段 4：功能迁移

- [ ] 4.1 修改 `MusicPlayerNotifier` 引用新 Handler
- [ ] 4.2 修改 `main.dart` 初始化逻辑
- [ ] 4.3 迁移 `setAudioSource()` 逻辑
- [ ] 4.4 迁移交叉淡化 `_startCrossfade()`
- [ ] 4.5 迁移预加载 `_preloadNextTrack()`
- [ ] 4.6 验证边下边播功能
- [ ] 4.7 验证 NCM 解密播放
- [ ] 4.8 验证元数据提取
- [ ] 4.9 验证播放历史记录
- [ ] 4.10 验证状态持久化

#### 阶段 5：测试与优化

- [ ] 5.1 iOS 全功能测试
- [ ] 5.2 Android 全功能测试
- [ ] 5.3 macOS 全功能测试
- [ ] 5.4 Windows 全功能测试
- [ ] 5.5 MP3/FLAC/AAC 格式测试
- [ ] 5.6 AC3/EAC3 格式测试
- [ ] 5.7 DTS/DTS-HD 格式测试
- [ ] 5.8 NCM 格式测试
- [ ] 5.9 音频直通测试（需外部功放）
- [ ] 5.10 内存占用测试
- [ ] 5.11 后台播放稳定性测试
- [ ] 5.12 Bug 修复

---

## 8. 迁移策略

### 8.1 渐进式迁移

为降低风险，采用渐进式迁移策略：

```dart
/// 播放引擎切换配置
/// lib/features/music/presentation/providers/music_settings_provider.dart

class MusicSettings {
  // ...

  /// 是否使用 media_kit 引擎
  /// - true: 使用新的 MusicMediaKitAudioHandler
  /// - false: 使用旧的 MusicAudioHandler (just_audio)
  final bool useMediaKitEngine;
}
```

```dart
/// main.dart 中的条件初始化

Future<void> main() async {
  // ...

  // 根据设置选择播放引擎
  final settings = await loadMusicSettings();

  if (settings.useMediaKitEngine) {
    audioHandler = await initMediaKitAudioHandler();
  } else {
    audioHandler = await initJustAudioHandler();
  }

  // ...
}
```

### 8.2 兼容层设计

```dart
/// 播放器接口抽象
/// lib/features/music/data/services/music_audio_handler_interface.dart

abstract class IMusicAudioHandler extends BaseAudioHandler {
  /// 获取底层播放器（用于高级操作）
  dynamic get underlyingPlayer;

  /// 设置当前音乐
  Future<void> setCurrentMusic(MusicItem music, {Uint8List? artworkData});

  /// 设置音频源
  Future<Duration?> setAudioSource(String url, {Map<String, String>? headers});

  /// 更新封面
  Future<void> updateArtwork(Uint8List artworkData);

  /// 设置队列
  void setQueue(List<MusicItem> items, {int startIndex = 0});

  /// 准备切换歌曲
  Future<void> prepareForNewTrack();

  /// 设置音量
  Future<void> setVolume(double volume);

  // Streams
  Stream<Duration> get positionStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
}
```

### 8.3 回滚计划

如果新引擎出现严重问题，可以快速回滚：

1. 保留 `MusicAudioHandler` (just_audio) 完整代码
2. 设置中添加引擎切换开关（隐藏在开发者选项中）
3. 遇到问题时用户可以切换回旧引擎
4. 收集新引擎的问题反馈，逐步修复

---

## 9. 测试计划

### 9.1 单元测试

```dart
/// test/features/music/data/services/music_media_kit_handler_test.dart

void main() {
  group('MusicMediaKitAudioHandler', () {
    late MusicMediaKitAudioHandler handler;

    setUp(() async {
      handler = MusicMediaKitAudioHandler();
      await handler.init();
    });

    tearDown(() async {
      await handler.dispose();
    });

    test('play() should start playback', () async {
      await handler.setAudioSource('file:///test.mp3');
      await handler.play();
      expect(handler.playbackState.value.playing, isTrue);
    });

    test('pause() should pause playback', () async {
      await handler.setAudioSource('file:///test.mp3');
      await handler.play();
      await handler.pause();
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('seek() should update position', () async {
      await handler.setAudioSource('file:///test.mp3');
      await handler.seek(const Duration(seconds: 30));
      expect(handler.playbackState.value.position,
             equals(const Duration(seconds: 30)));
    });

    // ... 更多测试
  });
}
```

### 9.2 集成测试

```dart
/// integration_test/music_player_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Music player full workflow', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 1. 导航到音乐页面
    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pumpAndSettle();

    // 2. 选择一首歌曲播放
    await tester.tap(find.text('测试歌曲.mp3'));
    await tester.pumpAndSettle();

    // 3. 验证播放状态
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // 4. 测试暂停
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // 5. 测试进度条
    // ...
  });
}
```

### 9.3 格式兼容性测试

| 格式 | 测试文件 | 预期结果 |
|------|---------|---------|
| MP3 | test_mp3_320kbps.mp3 | ✅ 正常播放 |
| FLAC | test_flac_16bit.flac | ✅ 正常播放 |
| AAC | test_aac_256kbps.m4a | ✅ 正常播放 |
| WAV | test_wav_pcm.wav | ✅ 正常播放 |
| OGG | test_ogg_vorbis.ogg | ✅ 正常播放 |
| OPUS | test_opus.opus | ✅ 正常播放 |
| AC3 | test_dolby_ac3.ac3 | ✅ 正常播放 |
| EAC3 | test_dolby_eac3.eac3 | ✅ 正常播放 |
| TrueHD | test_dolby_truehd.thd | ✅ 正常播放 |
| DTS | test_dts_core.dts | ✅ 正常播放 |
| DTS-HD | test_dts_hd_ma.dtshd | ✅ 正常播放 |
| NCM | test_netease.ncm | ✅ 解密后播放 |
| MKA | test_audio.mka | ✅ 正常播放 |

### 9.4 平台兼容性测试

| 平台 | 测试项 | 预期结果 |
|------|-------|---------|
| iOS 15+ | 基础播放 | ✅ |
| iOS 15+ | 锁屏控制 | ✅ |
| iOS 16+ | 灵动岛 | ✅ |
| iOS 15+ | 蓝牙控制 | ✅ |
| iOS 15+ | CarPlay | ✅ |
| Android 10+ | 基础播放 | ✅ |
| Android 10+ | 通知栏控制 | ✅ |
| Android 10+ | 蓝牙控制 | ✅ |
| macOS 11+ | 基础播放 | ✅ |
| macOS 11+ | 媒体键 | ✅ |
| Windows 10+ | 基础播放 | ✅ |
| Windows 10+ | 媒体键 | ✅ |

---

## 10. 风险评估

### 10.1 技术风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|-------|------|---------|
| audio_service 集成问题 | 中 | 高 | 保留旧代码，可快速回滚 |
| iOS 灵动岛显示异常 | 中 | 中 | 复用现有的原生层修复代码 |
| 后台播放不稳定 | 低 | 高 | 充分测试，参考视频播放器实现 |
| 内存占用增加 | 中 | 低 | 监控内存，优化资源释放 |
| 交叉淡化实现复杂 | 中 | 中 | 分阶段实现，先保证基础功能 |

### 10.2 进度风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|-------|------|---------|
| 开发时间超出预期 | 中 | 中 | 优先实现核心功能，高级功能后续迭代 |
| 测试设备不足 | 低 | 中 | 优先测试主流设备 |
| 音频直通测试困难 | 高 | 低 | 先实现功能，测试可后续进行 |

### 10.3 兼容性风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|-------|------|---------|
| 旧设备不支持 | 低 | 低 | 设置最低系统版本要求 |
| 特定格式播放失败 | 中 | 中 | 建立格式支持列表，不支持的格式给出提示 |

---

## 附录

### A. 参考资料

- [media_kit 官方文档](https://github.com/media-kit/media-kit)
- [audio_service 官方文档](https://github.com/ryanheise/audio_service)
- [MPV 音频配置文档](https://mpv.io/manual/master/#audio)
- [Apple Now Playing 文档](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [Dolby Atmos 技术规范](https://www.dolby.com/technologies/dolby-atmos/)

### B. 术语表

| 术语 | 说明 |
|------|------|
| SPDIF | Sony/Philips Digital Interface，数字音频传输接口 |
| eARC | Enhanced Audio Return Channel，增强音频回传通道 |
| PCM | Pulse Code Modulation，脉冲编码调制 |
| Bitstream | 比特流，未解码的原始数字音频数据 |
| Passthrough | 直通，将原始比特流传输到外部设备解码 |
| Atmos | Dolby Atmos，杜比全景声空间音频技术 |
| DTS:X | DTS 的空间音频技术 |

### C. 更新记录

| 版本 | 日期 | 更新内容 |
|------|------|---------|
| 1.0 | 2024-12-30 | 初始版本 |
