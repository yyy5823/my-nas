# Legado 功能分析与集成方案

## 1. 项目概述

[Legado (阅读)](https://github.com/gedoor/legado) 是一款功能强大的开源 Android 电子书阅读器，支持自定义书源、订阅源和各种阅读增强功能。

---

## 2. Legado 核心功能分析

### 2.1 功能模块

| 功能 | 描述 | 集成优先级 |
|-----|-----|----------|
| **书源系统** | 自定义规则解析网络内容 | ⭐⭐⭐⭐⭐ |
| **订阅源 (RSS)** | 自定义 RSS/网页订阅 | ⭐⭐⭐ |
| **本地书籍** | EPUB/TXT/MOBI 等格式 | ✅ 已有 |
| **在线 TTS** | 调用在线语音合成 API | ⭐⭐⭐⭐ |
| **替换规则** | 内容净化、广告过滤 | ⭐⭐⭐⭐ |
| **目录规则** | 本地 TXT 智能分章 | ⭐⭐⭐ |
| **主题定制** | 阅读界面主题 | ✅ 已有 |
| **Web 服务** | 远程书架管理 API | ⭐⭐⭐ |
| **书籍同步** | WebDAV 同步进度 | ⭐⭐⭐⭐ |
| **听书功能** | 本地+在线 TTS 朗读 | ⭐⭐⭐⭐ |

### 2.2 书源系统详解

书源是 Legado 的核心，使用 JSON 规则定义如何从网站抓取内容：

```json
{
  "bookSourceUrl": "https://example.com",
  "bookSourceName": "示例书源",
  "bookSourceGroup": "网络小说",
  "bookSourceType": 0,
  "enabled": true,
  "searchUrl": "/search?keyword={{key}}&page={{page}}",
  
  "ruleSearch": {
    "bookList": "$.data.list",
    "name": "$.name",
    "author": "$.author",
    "bookUrl": "$.url",
    "coverUrl": "$.cover",
    "intro": "$.desc"
  },
  
  "ruleBookInfo": {
    "name": "//h1/text()",
    "author": "//span[@class='author']/text()",
    "coverUrl": "//img[@class='cover']/@src",
    "intro": "//div[@class='intro']/text()",
    "tocUrl": "//a[@class='read']/@href"
  },
  
  "ruleToc": {
    "chapterList": "//ul[@class='chapter-list']/li",
    "chapterName": "./a/text()",
    "chapterUrl": "./a/@href"
  },
  
  "ruleContent": {
    "content": "//div[@id='content']",
    "replaceRegex": "广告文字",
    "nextContentUrl": "//a[@class='next']/@href"
  }
}
```

### 2.3 规则类型

| 规则类型 | 语法 | 用途 |
|---------|-----|-----|
| **XPath** | `//div[@class='x']` | HTML 解析 |
| **JSONPath** | `$.data.list` | JSON 解析 |
| **CSS 选择器** | `div.content` | HTML 解析 |
| **正则表达式** | `regex:pattern` | 文本提取 |
| **JavaScript** | `<js>code</js>` | 复杂逻辑 |

---

## 3. 集成方案

### 3.1 架构设计

```
lib/features/book/
├── data/
│   ├── sources/
│   │   ├── source_models.dart      # 书源数据模型
│   │   ├── source_parser.dart      # 规则解析引擎
│   │   ├── source_manager.dart     # 书源管理
│   │   └── source_importer.dart    # 导入 legado 书源
│   ├── parsers/
│   │   ├── xpath_parser.dart       # XPath 解析
│   │   ├── jsonpath_parser.dart    # JSONPath 解析
│   │   ├── css_parser.dart         # CSS 选择器
│   │   └── js_engine.dart          # JavaScript 引擎
│   └── services/
│       ├── book_search_service.dart
│       ├── chapter_service.dart
│       └── content_service.dart
└── presentation/
    ├── sources/
    │   ├── source_list_page.dart
    │   ├── source_edit_page.dart
    │   └── source_import_page.dart
    └── search/
        └── online_search_page.dart
```

### 3.2 核心依赖

```yaml
dependencies:
  # HTML/XML 解析
  html: ^0.15.4
  xml: ^6.3.0
  
  # XPath 解析
  xpath_selector: ^3.0.1
  
  # JSONPath 解析
  json_path: ^0.6.3
  
  # JavaScript 执行 (可选)
  flutter_js: ^0.8.0
  
  # HTTP 请求
  dio: ^5.4.0
```

### 3.3 书源模型 (兼容 Legado)

```dart
class BookSource {
  final String bookSourceUrl;
  final String bookSourceName;
  final String? bookSourceGroup;
  final int bookSourceType;  // 0: 文字, 1: 音频
  final bool enabled;
  
  // 搜索配置
  final String? searchUrl;
  final SearchRule? ruleSearch;
  
  // 详情规则
  final BookInfoRule? ruleBookInfo;
  
  // 目录规则
  final TocRule? ruleToc;
  
  // 正文规则
  final ContentRule? ruleContent;
  
  // 请求头
  final Map<String, String>? header;
}

class SearchRule {
  final String? bookList;
  final String? name;
  final String? author;
  final String? bookUrl;
  final String? coverUrl;
  final String? intro;
}

class ContentRule {
  final String? content;
  final String? replaceRegex;
  final String? nextContentUrl;
}
```

### 3.4 规则解析引擎

```dart
class RuleParser {
  /// 解析单条规则
  static String? parseRule(String? rule, dynamic source) {
    if (rule == null || rule.isEmpty) return null;
    
    // JSONPath 规则
    if (rule.startsWith('\$.') || rule.startsWith('\$[')) {
      return _parseJsonPath(rule, source);
    }
    
    // XPath 规则
    if (rule.startsWith('//') || rule.startsWith('/')) {
      return _parseXPath(rule, source as String);
    }
    
    // CSS 选择器 (class@开头)
    if (rule.contains('@')) {
      return _parseCssSelector(rule, source as String);
    }
    
    // 正则表达式
    if (rule.startsWith('regex:')) {
      return _parseRegex(rule.substring(6), source as String);
    }
    
    return source?.toString();
  }
  
  static String? _parseJsonPath(String path, dynamic json) {
    try {
      final jsonPath = JsonPath(path);
      return jsonPath.read(json).firstOrNull?.value?.toString();
    } catch (_) {
      return null;
    }
  }
  
  static String? _parseXPath(String xpath, String html) {
    try {
      final document = parse(html);
      final result = document.queryXPath(xpath);
      return result.nodes.firstOrNull?.text;
    } catch (_) {
      return null;
    }
  }
}
```

---

## 4. 关键功能实现

### 4.1 书源导入

```dart
class SourceImporter {
  /// 从 Legado 格式导入书源
  static List<BookSource> importFromJson(String json) {
    final data = jsonDecode(json);
    
    if (data is List) {
      return data.map((e) => BookSource.fromJson(e)).toList();
    } else if (data is Map) {
      return [BookSource.fromJson(data as Map<String, dynamic>)];
    }
    
    return [];
  }
  
  /// 从 URL 导入
  static Future<List<BookSource>> importFromUrl(String url) async {
    final response = await Dio().get(url);
    return importFromJson(response.data);
  }
}
```

### 4.2 在线搜索

```dart
class OnlineBookSearch {
  final List<BookSource> sources;
  
  Stream<SearchResult> search(String keyword) async* {
    for (final source in sources.where((s) => s.enabled)) {
      try {
        final results = await _searchSource(source, keyword);
        for (final result in results) {
          yield result;
        }
      } catch (e) {
        AppError.ignore(e, StackTrace.current, '书源搜索失败: ${source.bookSourceName}');
      }
    }
  }
  
  Future<List<SearchResult>> _searchSource(BookSource source, String keyword) async {
    final url = source.searchUrl?.replaceAll('{{key}}', Uri.encodeComponent(keyword));
    final response = await Dio().get(url!, options: Options(headers: source.header));
    
    final rule = source.ruleSearch!;
    final list = RuleParser.parseRule(rule.bookList, response.data);
    
    return (list as List).map((item) {
      return SearchResult(
        name: RuleParser.parseRule(rule.name, item) ?? '',
        author: RuleParser.parseRule(rule.author, item),
        bookUrl: RuleParser.parseRule(rule.bookUrl, item) ?? '',
        coverUrl: RuleParser.parseRule(rule.coverUrl, item),
        source: source,
      );
    }).toList();
  }
}
```

### 4.3 Web API 集成

Legado 提供 Web 服务 API，可远程管理书架：

| API | 方法 | 描述 |
|-----|-----|-----|
| `/getBookshelf` | GET | 获取书架 |
| `/getChapterList?url=x` | GET | 获取章节 |
| `/getBookContent?url=x&index=n` | GET | 获取正文 |
| `/saveBookSources` | POST | 导入书源 |
| `/getBookSources` | GET | 获取书源 |

```dart
class LegadoApiClient {
  final String baseUrl;  // e.g., http://192.168.1.100:1234
  
  Future<List<Book>> getBookshelf() async {
    final response = await Dio().get('$baseUrl/getBookshelf');
    return (response.data as List).map((e) => Book.fromJson(e)).toList();
  }
  
  Future<String> getBookContent(String bookUrl, int index) async {
    final response = await Dio().get(
      '$baseUrl/getBookContent',
      queryParameters: {'url': bookUrl, 'index': index},
    );
    return response.data;
  }
}
```

---

## 5. 跨平台适配

### 5.1 JavaScript 引擎

| 平台 | 方案 | 限制 |
|-----|-----|-----|
| **Android** | flutter_js (QuickJS) | 完整支持 |
| **iOS** | flutter_js (QuickJS) | 完整支持 |
| **macOS** | flutter_js | 完整支持 |
| **Windows** | flutter_js | 完整支持 |
| **Web** | dart:js_interop | 原生 JS |

### 5.2 网络请求

- 某些书源需要特殊请求头 (User-Agent, Referer)
- 需处理 Cookie 和 Session
- 可能需要代理支持

---

## 6. 开发计划

| 阶段 | 内容 | 周期 |
|-----|------|-----|
| 1 | 书源模型 + 规则解析器 | 2 周 |
| 2 | 书源导入/管理界面 | 1 周 |
| 3 | 在线搜索功能 | 1 周 |
| 4 | 目录/正文获取 | 1 周 |
| 5 | 内容缓存/离线 | 1 周 |

---

## 7. 注意事项

> [!WARNING]
> **版权声明**: 书源系统仅提供技术框架，不内置任何书源。用户自行添加书源需遵守当地法律法规。

> [!IMPORTANT]
> **数据安全**: 书源可能包含 JavaScript 代码，需在沙箱环境执行，防止恶意代码。

---

## 8. 参考资源

- [Legado GitHub](https://github.com/gedoor/legado)
- [书源规则文档](https://mgz0227.github.io/The-tutorial-of-Legado/)
- [Legado API 文档](https://github.com/gedoor/legado/blob/master/api.md)
- [Legado 帮助文档](https://www.yuque.com/legado/wiki)
