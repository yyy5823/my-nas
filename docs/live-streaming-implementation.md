# 直播流播放功能实现方案

## 1. 概述

在视频模块中添加直播流播放功能，包括直播源配置管理、视频首页直播区域、频道列表和播放器集成。

---

## 2. 支持的直播协议

| 协议 | 格式 | 说明 |
|-----|-----|-----|
| **HLS** | `.m3u8` | 最广泛支持 |
| **RTMP** | `rtmp://` | 实时流 |
| **RTSP** | `rtsp://` | 实时流 |
| **HTTP-FLV** | `.flv` | HTTP 传输 |

---

## 3. 数据模型

```dart
/// 直播源配置
class LiveStreamSource {
  final String id;
  final String name;
  final String playlistUrl;  // M3U 播放列表 URL
  final List<LiveChannel> channels;
  final int sortOrder;
  final bool isEnabled;
}

/// 直播频道
class LiveChannel {
  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String? category;  // 分类: 新闻、体育、电影等
  final Map<String, String>? headers;
}
```

### M3U 解析器

```dart
class M3UParser {
  static List<LiveChannel> parse(String content) {
    final channels = <LiveChannel>[];
    final lines = content.split('\n');
    
    String? currentName;
    String? currentLogo;
    String? currentCategory;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      if (line.startsWith('#EXTINF:')) {
        // 格式: #EXTINF:-1 tvg-logo="xxx" group-title="xxx",频道名
        currentName = _extractChannelName(line);
        currentLogo = _extractAttribute(line, 'tvg-logo');
        currentCategory = _extractAttribute(line, 'group-title');
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        if (currentName != null) {
          channels.add(LiveChannel(
            id: _generateId(line),
            name: currentName,
            streamUrl: line,
            logoUrl: currentLogo,
            category: currentCategory,
          ));
        }
        currentName = null;
      }
    }
    return channels;
  }
}
```

---

## 4. 设置 - 直播源管理

### 界面设计

```
┌─────────────────────────────────────┐
│  直播源管理                    ＋    │
├─────────────────────────────────────┤
│  ≡  IPTV 源 1                 ✓    │
│     32 个频道                  ✏️ 🗑 │
├─────────────────────────────────────┤
│  ≡  央视直播                  ✓    │
│     15 个频道                  ✏️ 🗑 │
└─────────────────────────────────────┘
拖拽 ≡ 图标可调整顺序
```

### 实现要点

```dart
class LiveStreamSettingsPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(liveStreamSourcesProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('直播源管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddSourceDialog(context),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        itemCount: sources.length,
        onReorder: (old, new_) => ref.read(liveStreamSourcesProvider.notifier).reorder(old, new_),
        itemBuilder: (context, index) => _buildSourceTile(sources[index]),
      ),
    );
  }
}
```

---

## 5. 视频首页直播区域

```
┌─────────────────────────────────────┐
│  🔴 直播                      更多 > │
├─────────────────────────────────────┤
│  ┌─────┐  ┌─────┐  ┌─────┐         │
│  │ 📺  │  │ 📺  │  │ 📺  │  ...    │
│  │CCTV1│  │湖南台│  │体育 │         │
│  └─────┘  └─────┘  └─────┘         │
└─────────────────────────────────────┘
```

```dart
class LiveStreamSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(enabledLiveSourcesProvider);
    final featuredChannels = sources.expand((s) => s.channels).take(10).toList();
    
    return Column(
      children: [
        // 标题栏
        Row(children: [
          Icon(Icons.circle, color: Colors.red, size: 8),
          Text('直播'),
          Spacer(),
          TextButton(child: Text('更多 >'), onPressed: () => _navigateToLiveList(context)),
        ]),
        // 频道横向列表
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: featuredChannels.length,
            itemBuilder: (ctx, i) => _buildChannelCard(featuredChannels[i]),
          ),
        ),
      ],
    );
  }
}
```

---

## 6. 频道列表页面

```
┌─────────────────────────────────────┐
│  ← 直播频道                   🔍    │
├─────────────────────────────────────┤
│  全部 | 央视 | 卫视 | 体育 | 电影   │
├─────────────────────────────────────┤
│  📺 CCTV-1 综合                 ▶  │
│  📺 CCTV-5 体育                 ▶  │
│  📺 湖南卫视                    ▶  │
└─────────────────────────────────────┘
```

支持分类筛选和搜索功能。

---

## 7. 播放器技术选型

| 库 | 支持协议 | 推荐度 |
|---|---------|-------|
| `media_kit` | HLS/RTMP/RTSP | ⭐⭐⭐⭐⭐ |
| `flutter_vlc_player` | HLS/RTMP/RTSP | ⭐⭐⭐⭐⭐ |
| `better_player` | HLS | ⭐⭐⭐⭐ |

### 推荐: media_kit

```yaml
dependencies:
  media_kit: ^1.1.10
  media_kit_video: ^1.2.4
  media_kit_libs_video: ^1.0.4
```

```dart
class LivePlayerPage extends StatefulWidget {
  final LiveChannel channel;
  
  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  
  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.channel.streamUrl));
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Video(controller: _controller),
    );
  }
}
```

---

## 8. 首页区域顺序调整

```dart
enum HomeSection { continueWatching, live, recentlyAdded, favorites }

class HomeSectionConfig {
  final HomeSection section;
  final bool isEnabled;
  final int sortOrder;
}
```

在设置中提供 ReorderableListView 让用户调整各区域顺序。

---

## 9. 开发计划

| 阶段 | 内容 | 周期 |
|-----|------|-----|
| 1 | 数据模型 + M3U 解析器 | 1 周 |
| 2 | 设置页面 (直播源管理) | 1 周 |
| 3 | 频道展示 (首页区域 + 列表) | 1 周 |
| 4 | 播放器集成 | 1 周 |

---

## 10. 参考资源

- [media_kit](https://pub.dev/packages/media_kit)
- [M3U 格式规范](https://en.wikipedia.org/wiki/M3U)
