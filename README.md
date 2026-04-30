# MyNAS

<p align="center">
  <img src="assets/icon.png" alt="MyNAS Logo" width="120" height="120">
</p>

<p align="center">
  <strong>一站式跨平台 NAS 媒体管理客户端</strong>
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#nas-适配">NAS 适配</a> •
  <a href="#媒体服务器">媒体服务器</a> •
  <a href="#下载器">下载器</a> •
  <a href="#支持平台">支持平台</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#文档">文档</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.x-blue?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## 简介

MyNAS 是一款跨平台的家用 NAS 媒体管理工具，把你常用的多种数据源（NAS 协议 / 媒体服务器 / 下载器 / PT 站 / 字幕站 / 媒体追踪服务）整合到一个客户端，让你能在 macOS、Windows、iOS、Android、Linux 上以统一、现代化的体验访问家里的所有媒体资源。

不绑定特定 NAS 品牌，**用户自带数据源**——你可以同时连接群晖 + Plex + qBittorrent + 任意 PT 站，并在视频详情页一键串联（找资源 → 下载 → 入库 → 播放）。

## 功能特性

### 🎬 视频
- 支持主流容器（MP4 / MKV / AVI / MOV / WMV / WebM / RMVB / TS / M2TS）和编码（H.264 / H.265 / VP9 / AV1）
- 字幕：SRT / ASS / SSA / VTT / SUB / PGS / 内嵌；支持样式自定义和**字幕延迟**调节
- 在线字幕搜索（OpenSubtitles，可使用自己的 API key）
- 倍速播放（0.5x–4x）、画中画、手势进度/亮度/音量
- 投屏：AirPlay / DLNA（含字幕扩展） / Chromecast
- 客户端转码（CPU / Android MediaCodec / Apple VideoToolbox）
- TMDB 元数据刮削、豆瓣评分整合、NFO 解析
- 系列 / 季 / 集组织、推荐 / 相似内容
- **TMDB 推荐 → PT 站搜索一键跳转**

![](https://nas.allbs.cn:8888/cloudpic/2026/04/067b17d8152f8b514bdc979853b5ff55.png)

### 🎵 音乐
- 有损 / 无损（FLAC / APE / WAV / AIFF / ALAC / DSD / MP3 / AAC 等）
- 后台播放、锁屏控制、媒体键、iOS Now Playing、Android 灵动岛、macOS Media Widget
- **桌面歌词**（Windows / macOS / Linux 原生悬浮窗）
- 元数据写入（audiotags + ffmpeg + tone 三引擎，覆盖 DSD 等无损）
- NCM 加密格式解密
- 自动刮削（封面 / 歌词 / 标签）

![](https://nas.allbs.cn:8888/cloudpic/2026/04/7183e33fb6af7f88f2d9793a890d1a3e.png)

### 📚 漫画 & 📖 书籍
- 漫画：CBZ / CBR / ZIP / RAR / 7Z / PDF；单页 / 双页 / 长条；左右翻页
- 书籍：EPUB / PDF / MOBI / AZW3 / TXT / HTML
- 自定义字体 / 字号 / 主题（日 / 夜 / 护眼 / 纯黑）
- 书签、目录导航、TTS 朗读
- **在线书源**（兼容 Legado JSON / XPath / JSONPath / CSS / 正则规则；用户自行导入，应用不内置任何书源）
  ![](https://nas.allbs.cn:8888/cloudpic/2026/04/2509128918beb534c06f1f971074fa53.jpg)


### 🖼️ 照片
- 相册浏览、时间线、EXIF 元数据
- **人脸识别 + 人物聚合**（点击人物头像跳转该人物所有照片）待实现

![](https://nas.allbs.cn:8888/cloudpic/2026/04/602eb0553cb0a73cd1182f21edcb592c.jpg)

### 📝 笔记
- Markdown 渲染（含任务列表 / 代码块 / 表格 / 图片）
- 树形目录浏览、笔记搜索

### 📁 文件浏览器
- 列表 / 网格视图、面包屑导航
- 排序 / 筛选 / 搜索（服务端优先，客户端 BFS fallback）
- 复制 / 移动 / 重命名 / 删除 / 上传 / 下载
- **分享**（远端文件流式下载到本地后调用系统分享）
- **目录选择器**（树形浏览 + 在线新建文件夹）

### 🔍 PT 站点
- 通用 PT 站爬虫（cookie + 站点规则）
- 种子搜索 / 列表 / 推广标识
- **视频详情页 → PT 搜索一键跳转**（带年份）
- **PT 搜索 → 一键发送下载器**

### 📡 媒体追踪
- Trakt.tv OAuth 同步（待看 / 在看 / 已看 / 评分）

![](https://nas.allbs.cn:8888/cloudpic/2026/04/269b8b60c7661ab033aa061c7a86056b.jpg)

## NAS 适配

| NAS / 协议 | 状态 | 说明 |
|---|---|---|
| 群晖 Synology | ✅ | DSM 6/7、File/Video/Audio/Photos Station、QuickConnect、二次验证 |
| 绿联 UGREEN (UGOS) | ✅ | RSA 加密登录 + 服务端 API + 客户端 fallback |
| 飞牛 fnOS | ✅ | 服务端 copy/upload/search + 客户端 fallback |
| 威联通 QNAP | ✅ | QTS API |
| WebDAV | ✅ | 通用协议 |
| SMB / CIFS | ✅ | 含连接池 / 心跳 / 客户端 fallback（copy/search/url-stream） |
| 本地存储 | ✅ | 本地文件系统 |
| 移动端虚拟 fs | ✅ | 手机本地音乐 / 相册 / 文件 |

## 媒体服务器

| 服务器 | 状态 | 认证方式 | 备注 |
|---|---|---|---|
| Jellyfin (10.8+) | ✅ | 用户名密码 / API Key / Quick Connect | WebSocket 实时同步（14 种事件） |
| Emby (4.6+) | ✅ | 用户名密码 / API Key | WebSocket 实时同步（18 种事件）、deviceId 持久化 |
| Plex | ✅ | PIN 授权 | getNextUp 含 viewOffset 优先 |

进度同步、标记已看、收藏、推荐、继续观看、下一集等功能完整。

## 下载器

| 下载器 | 状态 | 备注 |
|---|---|---|
| qBittorrent | ✅ | Web API |
| Transmission | ✅ | RPC（自定义 rpcPath） |
| Aria2 | ✅ | JSON-RPC + token + pause/dir 选项 |
| MoviePilot | ✅ | 订阅 / 任务 / 媒体管理 |
| NASTool | ✅ | 订阅 / 任务 / 搜索 |

种子卡片一键发送，支持暂停后添加、自定义下载目录。

![](https://nas.allbs.cn:8888/cloudpic/2026/04/ce0f3b75b935111238661939939abf10.png)

## 支持平台

| 平台 | 最低版本 | 状态 |
|---|---|---|
| macOS | 11.0+ | ✅ 含 Mac App Store 上架适配（沙盒 / entitlements） |
| Windows | 10+ | ✅ |
| iOS | 12.0+ | ✅ 含麦克风 / 相机权限、应用签名 |
| Android | 6.0+ | ✅ 含媒体通知、应用 ID 规范 |
| Linux | - | 🚧 编译通过，部分依赖支持有限（如 share_plus） |

## 技术栈

- **框架**：Flutter 3.x + Dart 3.x（启用 sealed classes / records / pattern matching）
- **状态管理**：Riverpod 2.x
- **路由**：go_router 15.x（含 deep link 处理）
- **网络**：Dio 5.x（自签证书可选信任）
- **本地存储**：Hive CE + SQLite + AES Cipher Box
- **凭证存储**：FlutterSecureStorage + Keychain 失败时降级到 Hive AES
- **视频播放**：media_kit (libmpv)
- **音频播放**：just_audio + audio_service + media_kit（macOS/Linux）
- **PDF 阅读**：pdfrx
- **EPUB**：epubx + flutter_html / WebView 双模式
- **MOBI/AZW3**：自研 parser
- **加密**：crypto + pointycastle（sha256 / RSA / AES）

## 快速开始

### 环境要求

- Flutter SDK >= 3.16.0
- Dart SDK >= 3.2.0
- Xcode >= 15.0（macOS / iOS 构建）
- Android Studio >= 2023.1（Android 构建）

### 克隆与依赖

```bash
git clone git@github.com:chenqi92/my-nas.git
cd my-nas
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 运行

```bash
flutter run -d windows    # Windows
flutter run -d macos      # macOS
flutter run -d ios        # iOS（真机或模拟器）
flutter run -d android    # Android
```

### 构建发布

```bash
flutter build windows --release
flutter build macos --release
flutter build ios --release
flutter build apk --release            # Android APK
flutter build appbundle --release      # Android AAB（Play 上架）
```

## 项目结构

```
my-nas/
├── lib/
│   ├── app/                       # 应用入口、路由（go_router）、主题
│   ├── core/                      # 核心基础设施
│   │   ├── errors/                # AppError 统一错误处理工具
│   │   ├── network/               # DioClient、自签证书
│   │   ├── storage/               # 凭证存储（含 Keychain 降级）
│   │   └── utils/                 # logger / hive_utils / platform_capabilities ...
│   ├── features/                  # 功能模块（按业务垂直划分）
│   │   ├── video/                 # 视频列表 / 详情 / 播放 / 转码 / 字幕 / 刮削
│   │   ├── music/                 # 音乐 / 播放器 / 元数据写入 / 灵动岛
│   │   ├── photo/                 # 相册 / 人脸识别
│   │   ├── comic/                 # 漫画
│   │   ├── book/                  # 电子书 + 在线书源（Legado 兼容）
│   │   ├── note/                  # 笔记
│   │   ├── reading/               # 阅读进度 + 书签统一服务
│   │   ├── pt_sites/              # PT 站爬取 / 搜索 / 发送下载器
│   │   ├── nastool/               # NASTool 集成
│   │   ├── media_tracking/        # Trakt 等
│   │   ├── transfer/              # 上传 / 下载 / 共享缓存
│   │   ├── sources/               # 源管理（NAS / 媒体服务器 / 下载器统一抽象）
│   │   ├── file_browser/          # 文件浏览器
│   │   └── ...
│   ├── shared/                    # 跨 feature 共享组件 / providers / services
│   ├── nas_adapters/              # NAS 协议适配（SMB / WebDAV / 群晖 / 飞牛 / 绿联 / QNAP / 本地 / mobile）
│   ├── media_server_adapters/     # 媒体服务器适配（Jellyfin / Emby / Plex）
│   └── service_adapters/          # 服务适配（qBittorrent / Transmission / Aria2 / MoviePilot ...）
├── assets/                        # 静态资源（图标 / 动画 / ML 模型）
├── docs/                          # 设计文档（ANALYSIS / ARCHITECTURE / TASKS 等）
└── test/                          # 测试
```

## 文档

详细的设计与开发文档在 [`docs/`](docs/) 目录：

- [`docs/ANALYSIS.md`](docs/ANALYSIS.md) — 项目需求分析与功能清单
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 架构设计、核心抽象、关键决策
- [`docs/TASKS.md`](docs/TASKS.md) — 开发进度与里程碑
- [`docs/legado-integration.md`](docs/legado-integration.md) — Legado 书源集成
- [`docs/ebook-implementation.md`](docs/ebook-implementation.md) — 电子书实现
- [`docs/ios26-liquid-glass-*`](docs/) — iOS 26 Liquid Glass 设计与实现
- 其他专题（灵动岛 / 桌面歌词 / TTS / 直播等）

## 路线图

### 已完成
- [x] 跨 5 平台基础架构（iOS/Android/macOS/Windows/Linux）
- [x] 多 NAS 适配（Synology / UGOS / fnOS / QNAP / WebDAV / SMB / 本地）
- [x] 媒体服务器适配（Jellyfin / Emby / Plex）
- [x] 下载器集成（qBittorrent / Transmission / Aria2 / MoviePilot / NASTool）
- [x] PT 站点框架 + 视频/推荐 → PT 搜索串联
- [x] 视频 / 音乐 / 漫画 / 书籍 / 照片 / 笔记 全模块
- [x] 客户端转码（多平台硬解码）
- [x] TMDB 刮削 + 豆瓣 + NFO + Trakt
- [x] 在线字幕搜索（OpenSubtitles）
- [x] 桌面歌词（多平台原生窗口）
- [x] iOS 灵动岛 + macOS / Windows 媒体小组件
- [x] 人脸识别 + 人物聚合
- [x] iOS 26 Liquid Glass UI
- [x] Mac App Store 上架适配
- [x] Keychain 降级方案

### 进行中
- [ ] 国际化覆盖率（中文已完成，英文部分完成）
- [ ] 应用商店上架（macOS / iOS / Android / Microsoft Store）
- [ ] 完整无障碍支持
- [ ] 应用锁（PIN / 生物识别）

### Backlog
- [ ] 更多 NAS（铁威马、海康等）
- [ ] AI 字幕翻译 / 元数据补全
- [ ] 智能推荐（基于本地观看历史）
- [ ] 插件系统

## 贡献

欢迎贡献代码、提交 Issue 或提出建议！

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/amazing-feature`）
3. 提交更改（`git commit -m 'Add amazing feature'`）
4. 推送到分支（`git push origin feature/amazing-feature`)
5. 提交 Pull Request

提交前请确保：
- `flutter analyze` 在 `lib/` 下零 errors
- 涉及功能改动时，已在某个平台手动验证 UI（README 当前未要求自动化 UI 测试）
- 遵循 [`CLAUDE.md`](CLAUDE.md) 中的错误处理规范（所有 catch 块用 `AppError`）

## 许可证

本项目采用 MIT 许可证 — 详见 [LICENSE](LICENSE) 文件

## 联系方式

- GitHub Issues: [提交问题](https://github.com/chenqi92/my-nas/issues)

---

<p align="center">
  Made with ❤️ by MyNAS Team
</p>
