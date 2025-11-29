# MyNAS

<p align="center">
  <img src="assets/icon.png" alt="MyNAS Logo" width="120" height="120">
</p>

<p align="center">
  <strong>一站式家用 NAS 连接与媒体管理工具</strong>
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#支持平台">支持平台</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#文档">文档</a> •
  <a href="#贡献">贡献</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.x-blue?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## 简介

MyNAS 是一款跨平台的家用 NAS 连接工具，让你能够在任何设备上便捷地访问和管理 NAS 中的媒体资源。无论是观看视频、聆听音乐、阅读漫画书籍，还是记录笔记、管理下载任务，MyNAS 都能提供统一、美观、流畅的体验。

## 功能特性

### 🎬 视频播放
- 支持主流视频格式 (MP4, MKV, AVI, MOV 等)
- 字幕加载与样式自定义
- 倍速播放、画中画
- 投屏支持 (AirPlay, DLNA)
- 观看进度多端同步

### 🎵 音乐播放
- 支持有损/无损音频格式 (MP3, FLAC, APE 等)
- 歌词显示
- 均衡器
- 后台播放
- 播放队列管理

### 📚 漫画阅读
- 支持图片与压缩包格式 (CBZ, CBR, ZIP, RAR)
- 多种阅读模式 (单页、双页、长条)
- 手势翻页与缩放
- 阅读进度记忆

### 📖 书籍阅读
- 支持 EPUB, PDF, TXT 等格式
- 自定义字体、主题
- 书签与笔记
- 目录导航与全文搜索

### 📝 笔记记录
- Markdown 编辑器
- 笔记分类与标签
- 云端同步 (存储在 NAS)
- 离线编辑

### 🔧 下载工具管理
- NASTools 集成
- qBittorrent 管理
- 任务监控与通知

## NAS 适配

| NAS 系统 | 状态 | 连接方式 |
|----------|------|----------|
| 群晖 Synology | 🟢 计划中 | WebAPI / QuickConnect |
| 绿联 UGREEN | 🟢 计划中 | API / WebDAV |
| WebDAV | 🟢 计划中 | 通用协议 |
| SMB/CIFS | 🟡 规划中 | 通用协议 |
| 威联通 QNAP | 🔴 待定 | - |

## 支持平台

| 平台 | 最低版本 | 状态 |
|------|----------|------|
| macOS | 10.14+ | 🟢 支持 |
| Windows | 10+ | 🟢 支持 |
| iOS | 12.0+ | 🟢 支持 |
| Android | 6.0+ | 🟢 支持 |

## 技术栈

- **框架**: Flutter 3.x
- **语言**: Dart 3.x
- **状态管理**: Riverpod
- **网络**: Dio
- **本地存储**: Hive + SQLite
- **视频播放**: media_kit
- **音频播放**: just_audio

## 快速开始

### 环境要求

- Flutter SDK >= 3.16.0
- Dart SDK >= 3.2.0
- Xcode >= 15.0 (macOS/iOS)
- Android Studio >= 2023.1

### 克隆项目

```bash
git clone git@github.com:chenqi92/my-nas.git
cd my-nas
```

### 安装依赖

```bash
flutter pub get
```

### 运行项目

```bash
# macOS
flutter run -d macos

# Windows
flutter run -d windows

# iOS
flutter run -d ios

# Android
flutter run -d android
```

### 构建发布版本

```bash
# macOS
flutter build macos --release

# Windows
flutter build windows --release

# iOS
flutter build ios --release

# Android
flutter build apk --release
```

## 项目结构

```
my-nas/
├── lib/
│   ├── app/                 # 应用入口与配置
│   ├── core/                # 核心基础设施
│   ├── features/            # 功能模块
│   │   ├── connection/      # NAS 连接管理
│   │   ├── video/           # 视频模块
│   │   ├── music/           # 音乐模块
│   │   ├── comic/           # 漫画模块
│   │   ├── book/            # 书籍模块
│   │   ├── note/            # 笔记模块
│   │   └── tools/           # 下载工具管理
│   ├── shared/              # 共享组件
│   └── nas_adapters/        # NAS 适配器
├── docs/                    # 项目文档
│   ├── ANALYSIS.md          # 需求分析
│   ├── ARCHITECTURE.md      # 架构设计
│   └── TASKS.md             # 任务规划
├── assets/                  # 静态资源
└── test/                    # 测试文件
```

## 文档

- [需求分析](docs/ANALYSIS.md)
- [架构设计](docs/ARCHITECTURE.md)
- [开发任务](docs/TASKS.md)

## 路线图

- [x] 项目初始化
- [ ] 基础架构搭建
- [ ] 群晖适配器开发
- [ ] 视频播放功能
- [ ] 音乐播放功能
- [ ] 漫画阅读功能
- [ ] 书籍阅读功能
- [ ] 笔记功能
- [ ] 下载工具管理
- [ ] 多平台发布

## 贡献

欢迎贡献代码、提交 Issue 或提出建议！

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 提交 Pull Request

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 联系方式

- GitHub Issues: [提交问题](https://github.com/chenqi92/my-nas/issues)

---

<p align="center">
  Made with ❤️ by MyNAS Team
</p>
