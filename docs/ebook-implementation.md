# 图书模块电子书功能实现分析

## 1. 概述

本文档分析在 My-NAS 图书模块中添加完整电子书功能所需实现的内容，包括技术选型、跨平台差异和关键考量点。

---

## 2. 需要实现的核心功能

### 2.1 电子书格式支持

| 格式 | 当前状态 | 需要实现 |
|-----|---------|---------|
| EPUB | ✅ 已支持 | 优化解析性能 |
| MOBI | ✅ 已支持 | 完善图片提取 |
| TXT | ✅ 已支持 | 智能章节识别 |
| PDF | ✅ 已支持 | 优化渲染性能 |
| AZW3 | ❌ 未支持 | 新增解析器 |
| CBZ/CBR | ❌ 未支持 | 漫画格式支持 |

### 2.2 阅读体验功能

- **排版设置**: 字体大小/行距/边距/对齐方式
- **主题切换**: 日间/夜间/护眼/自定义主题
- **阅读进度**: 进度保存/同步/跨设备恢复
- **书签管理**: 添加/删除/跳转书签
- **目录导航**: 目录解析/章节跳转
- **搜索功能**: 全文搜索/关键词高亮
- **批注功能**: 划线/笔记/导出

### 2.3 在线书籍功能 (参考 legado)

- **书源系统**: 自定义书源规则
- **在线搜索**: 聚合多书源搜索
- **内容缓存**: 离线阅读支持
- **自动更新**: 书籍章节更新检测

---

## 3. 技术实现方案

### 3.1 Flutter 电子书库选型对比

| 库名称 | 平台支持 | 优点 | 缺点 | 推荐度 |
|-------|---------|-----|------|-------|
| `flutter_epub_viewer` | Android/iOS/Web | 功能丰富、高亮/搜索/CFI进度 | 依赖 InAppWebView | ⭐⭐⭐⭐⭐ |
| `epub_view` | Android/iOS/macOS/Web | 轻量级、基于 dart-epub | 功能较少 | ⭐⭐⭐⭐ |
| `vocsy_epub_viewer` | Android/iOS | 封装 FolioReader、UI 美观 | 不够灵活 | ⭐⭐⭐ |
| `cosmos_epub` | 全平台 | RTL 支持、主题丰富 | 维护频率低 | ⭐⭐⭐ |
| 自研方案 | 全平台 | 完全可控 | 工作量大 | 视情况 |

### 3.2 推荐技术栈

```yaml
# pubspec.yaml 依赖建议
dependencies:
  # EPUB 解析
  epubx: ^latest          # EPUB 文件解析
  flutter_epub_viewer: ^latest  # EPUB 渲染
  
  # PDF 支持
  syncfusion_flutter_pdfviewer: ^latest
  
  # 文本渲染
  flutter_html: ^latest   # HTML 内容渲染
  
  # 存储
  isar: ^latest          # 本地数据库 (当前已使用)
  
  # 网络书源
  dio: ^latest           # HTTP 请求
  html: ^latest          # HTML 解析
  json_path: ^latest     # JSON 路径提取
```

### 3.3 核心模块架构

```
lib/features/book/
├── data/
│   ├── parsers/
│   │   ├── epub_parser.dart       # EPUB 解析
│   │   ├── mobi_parser.dart       # MOBI 解析 (已有)
│   │   ├── azw3_parser.dart       # AZW3 解析 (新增)
│   │   └── txt_parser.dart        # TXT 智能分章
│   ├── sources/
│   │   ├── book_source.dart       # 书源模型
│   │   ├── source_parser.dart     # 书源规则解析
│   │   └── source_manager.dart    # 书源管理
│   └── services/
│       ├── reading_progress_service.dart  # 进度管理
│       ├── bookmark_service.dart          # 书签管理
│       └── annotation_service.dart        # 批注管理
├── domain/
│   ├── entities/
│   │   ├── book.dart
│   │   ├── chapter.dart
│   │   └── book_source.dart
│   └── repositories/
│       └── book_repository.dart
└── presentation/
    ├── readers/
    │   ├── epub_reader/
    │   ├── pdf_reader/
    │   └── txt_reader/
    └── widgets/
        ├── reading_settings_panel.dart
        ├── toc_drawer.dart
        └── annotation_toolbar.dart
```

---

## 4. 跨平台技术差异

### 4.1 渲染引擎差异

| 平台 | 推荐渲染方案 | 原因 |
|-----|------------|-----|
| **Android** | WebView (InAppWebView) | ExoPlayer 支持、性能好 |
| **iOS** | WKWebView / Native Text | 系统限制、需原生优化 |
| **macOS** | WebView / Flutter Widget | 屏幕大、需适配键盘导航 |
| **Windows** | WebView2 / Flutter Widget | Edge WebView2 支持 |
| **Linux** | Flutter Widget | WebView 支持有限 |
| **Web** | 原生 HTML/CSS | 直接渲染 |

### 4.2 文件访问差异

| 平台 | 本地文件访问 | 云端文件访问 |
|-----|------------|------------|
| **Android** | Storage Access Framework | 通过 NAS Adapter |
| **iOS** | App Sandbox + Files | 通过 NAS Adapter |
| **macOS** | 完整文件系统访问 | 通过 NAS Adapter |
| **Windows** | 完整文件系统访问 | 通过 NAS Adapter |

### 4.3 TTS 引擎差异

| 平台 | 原生 TTS 引擎 | 特点 |
|-----|-------------|-----|
| **Android** | Google TTS | 支持多语言、可下载离线包 |
| **iOS** | AVSpeechSynthesizer | 系统内置、Siri 音色 |
| **macOS** | NSSpeechSynthesizer | 系统内置 |
| **Windows** | SAPI 5 / OneCore | 系统内置 |

---

## 5. 关键考量点

### 5.1 性能优化

> [!IMPORTANT]
> 大文件处理是关键挑战，需要分块加载和虚拟化渲染。

- **分页策略**: 使用虚拟滚动，只渲染可见区域
- **内容分块**: 按章节加载，延迟解析
- **图片处理**: 懒加载 + 缓存 + 压缩
- **内存管理**: 及时释放非活跃章节资源

```dart
// 示例: 分块内容加载
class ChunkedContentLoader {
  static const int chunkSize = 50000; // 50KB per chunk
  
  Future<String> loadChapter(int chapterIndex) async {
    // 仅加载当前章节
    // 预加载相邻章节
    // 释放远离的章节
  }
}
```

### 5.2 数据存储

```dart
// 使用 SQLite/Isar 存储元数据
class BookDatabase {
  // 书籍信息
  // 阅读进度 (精确到字符位置)
  // 书签列表
  // 批注内容
  // 阅读历史
}
```

### 5.3 同步策略

- **本地优先**: 所有数据先存本地
- **增量同步**: 仅同步变更数据
- **冲突处理**: 以最新时间戳为准
- **离线支持**: 完整离线阅读能力

### 5.4 书源规则 (参考 legado)

```json
{
  "bookSourceUrl": "https://example.com",
  "bookSourceName": "示例书源",
  "bookSourceGroup": "网络小说",
  "searchUrl": "/search?keyword={{key}}",
  "ruleSearch": {
    "bookList": "$.data.list",
    "name": "$.name",
    "author": "$.author",
    "bookUrl": "$.url"
  },
  "ruleBookInfo": {
    "name": "//h1/text()",
    "author": "//span[@class='author']/text()",
    "coverUrl": "//img[@class='cover']/@src"
  },
  "ruleToc": {
    "chapterList": "//ul[@class='chapter-list']/li",
    "chapterName": "./a/text()",
    "chapterUrl": "./a/@href"
  },
  "ruleContent": {
    "content": "//div[@id='content']"
  }
}
```

### 5.5 安全性考虑

- **书源校验**: 防止恶意书源
- **内容过滤**: XSS 防护
- **版权提示**: 用户自行添加书源的免责声明

---

## 6. 开发优先级

### 第一阶段: 核心阅读体验 (2-3 周)
- [ ] 完善 EPUB/TXT 阅读器
- [ ] 实现阅读设置面板
- [ ] 添加书签功能
- [ ] 优化目录导航

### 第二阶段: 进度与同步 (1-2 周)
- [ ] 精确进度保存
- [ ] 跨设备同步
- [ ] 阅读历史记录

### 第三阶段: 书源系统 (2-3 周)
- [ ] 书源规则解析器
- [ ] 书源管理界面
- [ ] 在线搜索功能
- [ ] 内容缓存机制

### 第四阶段: 高级功能 (2 周)
- [ ] 批注功能
- [ ] 全文搜索
- [ ] 更多格式支持

---

## 7. 参考资源

- [legado 开源阅读](https://github.com/gedoor/legado) - 书源规则参考
- [flutter_epub_viewer](https://pub.dev/packages/flutter_epub_viewer) - EPUB 渲染库
- [epubx](https://pub.dev/packages/epubx) - EPUB 解析库
