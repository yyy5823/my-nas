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

MyNAS 是一款跨平台的家用 NAS 连接工具，让你能够在任何设备上便捷地访问和管理 NAS 中的媒体资源。无论是观看视频、聆听音乐、阅读漫画书籍、浏览照片，还是记录笔记、管理文件，MyNAS 都能提供统一、美观、流畅的体验。

## 功能特性

### 🎬 视频播放
- 支持主流视频格式 (MP4, MKV, AVI, MOV, WMV 等)
- 字幕加载与样式自定义 (SRT, ASS, SSA)
- 倍速播放、画中画模式
- TMDB 元数据刮削与海报墙展示
- 剧集管理与续播功能
- 投屏支持 (AirPlay, DLNA)

### 🎵 音乐播放
- 支持有损/无损音频格式 (MP3, FLAC, APE, WAV, AAC 等)
- 歌词显示 (内嵌歌词 / LRC 文件 / 在线搜索)
- 专辑封面自动获取
- 后台播放与锁屏控制
- 播放队列与播放模式管理

### 📚 漫画阅读
- 支持图片与压缩包格式 (CBZ, CBR, ZIP, RAR, 7Z)
- 多种阅读模式 (单页、双页、长条滚动)
- 手势翻页与缩放
- 阅读进度记忆

### 📖 书籍阅读
- 支持 EPUB, PDF, TXT 等格式
- 自定义字体、主题、行距
- 书签与目录导航

### 🖼️ 照片浏览
- 图片格式支持 (JPG, PNG, GIF, WebP, HEIC 等)
- 时间线与相册视图
- 图片缩放与手势操作
- 照片保存到本地

### 📝 笔记记录
- Markdown 编辑器
- 笔记分类管理
- 云端同步 (存储在 NAS)

### 📁 文件浏览器
- 文件与文件夹浏览
- 文件搜索
- 文件下载与分享

## NAS 适配

| NAS 系统 | 状态 | 连接方式 |
|----------|------|----------|
| 群晖 Synology | ✅ 已支持 | DSM WebAPI |
| 绿联 UGREEN (UGOS) | ✅ 已支持 | UGOS API |
| 飞牛 fnOS | ✅ 已支持 | fnOS API |
| 威联通 QNAP | ✅ 已支持 | QTS API |
| WebDAV | ✅ 已支持 | 通用协议 |
| SMB/CIFS | ✅ 已支持 | 通用协议 |
| 本地存储 | ✅ 已支持 | 本地文件系统 |

## 支持平台

| 平台 | 最低版本 | 状态 |
|------|----------|------|
| macOS | 11.0+ | ✅ 支持 |
| Windows | 10+ | ✅ 支持 |
| iOS | 12.0+ | ✅ 支持 |
| Android | 6.0+ | ✅ 支持 |

## 技术栈

- **框架**: Flutter 3.x
- **语言**: Dart 3.x
- **状态管理**: Riverpod
- **依赖注入**: GetIt + Injectable
- **网络**: Dio
- **本地存储**: Hive + SQLite
- **视频播放**: media_kit
- **音频播放**: just_audio + media_kit
- **路由**: go_router

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

### 生成代码

```bash
dart run build_runner build --delete-conflicting-outputs
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
│   │   ├── router/          # 路由配置
│   │   └── theme/           # 主题配置
│   ├── core/                # 核心基础设施
│   │   ├── di/              # 依赖注入
│   │   └── utils/           # 工具类
│   ├── features/            # 功能模块
│   │   ├── book/            # 书籍阅读
│   │   ├── comic/           # 漫画阅读
│   │   ├── connection/      # 连接管理 (旧版)
│   │   ├── download/        # 下载管理
│   │   ├── file_browser/    # 文件浏览器
│   │   ├── mine/            # 个人中心
│   │   ├── music/           # 音乐播放
│   │   ├── note/            # 笔记
│   │   ├── photo/           # 照片浏览
│   │   ├── settings/        # 设置
│   │   ├── sources/         # 源管理
│   │   ├── startup/         # 启动页
│   │   └── video/           # 视频播放
│   ├── shared/              # 共享组件
│   │   ├── providers/       # 全局 Provider
│   │   ├── services/        # 共享服务
│   │   └── widgets/         # 通用组件
│   └── nas_adapters/        # NAS 适配器
│       ├── base/            # 基础抽象
│       ├── synology/        # 群晖适配器
│       ├── ugreen/          # 绿联适配器
│       ├── fnos/            # 飞牛适配器
│       ├── qnap/            # 威联通适配器
│       ├── webdav/          # WebDAV 适配器
│       ├── smb/             # SMB 适配器
│       └── local/           # 本地存储适配器
├── assets/                  # 静态资源
└── test/                    # 测试文件
```

## 路线图

- [x] 项目初始化与基础架构
- [x] 多 NAS 适配器框架
- [x] 群晖 Synology 适配
- [x] 绿联 UGREEN 适配
- [x] 飞牛 fnOS 适配
- [x] 威联通 QNAP 适配
- [x] WebDAV / SMB 支持
- [x] 视频播放功能
- [x] 音乐播放功能
- [x] 照片浏览功能
- [x] 漫画阅读功能
- [x] 书籍阅读功能
- [x] 笔记功能
- [x] 文件浏览器
- [x] 多平台支持 (macOS/Windows/iOS/Android)
- [ ] 应用内更新
- [ ] 更多 NAS 系统支持

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
