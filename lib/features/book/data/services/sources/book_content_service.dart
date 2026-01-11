import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/sources/rule_parser.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';

/// 书籍详情信息
class BookInfo {
  const BookInfo({
    required this.name,
    required this.author,
    required this.bookUrl,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
    this.tocUrl,
  });

  final String name;
  final String author;
  final String bookUrl;
  final String? coverUrl;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? wordCount;
  final String? tocUrl;
}

/// 书籍内容服务
///
/// 获取书籍详情、目录和章节内容
class BookContentService {
  BookContentService._();

  static final instance = BookContentService._();

  final _dio = Dio();
  final _random = Random();
  
  /// User-Agent 列表，模拟不同浏览器
  static const _userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  ];

  /// 获取书籍详情
  Future<BookInfo?> getBookInfo(OnlineBook book) async {
    try {
      final source = book.source;
      final rule = source.ruleBookInfo;

      // 发送请求
      final response = await _makeRequest(source, book.bookUrl);
      if (response == null) return null;

      // 如果没有详情规则，使用搜索结果的信息
      if (rule == null) {
        return BookInfo(
          name: book.name,
          author: book.author,
          bookUrl: book.bookUrl,
          coverUrl: book.coverUrl,
          intro: book.intro,
          kind: book.kind,
          lastChapter: book.lastChapter,
          wordCount: book.wordCount,
        );
      }

      // 解析详情
      return BookInfo(
        name: RuleParser.parseRule(rule.name, response, baseUrl: book.bookUrl) ?? book.name,
        author: RuleParser.parseRule(rule.author, response, baseUrl: book.bookUrl) ?? book.author,
        bookUrl: book.bookUrl,
        coverUrl: RuleParser.parseRule(rule.coverUrl, response, baseUrl: book.bookUrl) ?? book.coverUrl,
        intro: RuleParser.parseRule(rule.intro, response, baseUrl: book.bookUrl) ?? book.intro,
        kind: RuleParser.parseRule(rule.kind, response, baseUrl: book.bookUrl) ?? book.kind,
        lastChapter: RuleParser.parseRule(rule.lastChapter, response, baseUrl: book.bookUrl),
        wordCount: RuleParser.parseRule(rule.wordCount, response, baseUrl: book.bookUrl),
        tocUrl: RuleParser.parseRule(rule.tocUrl, response, baseUrl: book.bookUrl),
      );
    } catch (e, st) {
      AppError.handle(e, st, 'getBookInfo');
      return null;
    }
  }

  /// 获取章节目录
  Future<List<OnlineChapter>> getChapterList(
    BookSource source,
    String bookUrl, {
    String? tocUrl,
  }) async {
    try {
      final rule = source.ruleToc;
      if (rule == null) {
        logger.w('书源 ${source.displayName} 没有目录规则');
        return [];
      }

      // 确定目录URL
      final url = tocUrl ?? bookUrl;
      
      // 获取所有页的目录
      var allChapters = <OnlineChapter>[];
      var currentUrl = url;
      var pageCount = 0;
      const maxPages = 50; // 防止无限循环

      while (currentUrl.isNotEmpty && pageCount < maxPages) {
        final response = await _makeRequest(source, currentUrl);
        if (response == null) break;

        final chapters = _parseChapterList(source, response, currentUrl);
        if (chapters.isEmpty) break;

        // 添加章节，设置索引
        for (final chapter in chapters) {
          allChapters.add(OnlineChapter(
            name: chapter.name,
            url: chapter.url,
            isVolume: chapter.isVolume,
            updateTime: chapter.updateTime,
            index: allChapters.length,
          ));
        }

        // 检查是否有下一页
        final nextUrl = RuleParser.parseRule(rule.nextTocUrl, response, baseUrl: currentUrl);
        if (nextUrl == null || nextUrl.isEmpty || nextUrl == currentUrl) {
          break;
        }
        currentUrl = nextUrl;
        pageCount++;
      }

      logger.i('获取目录完成: ${allChapters.length} 章');
      return allChapters;
    } catch (e, st) {
      AppError.handle(e, st, 'getChapterList');
      return [];
    }
  }

  /// 常用的备用章节列表选择器
  /// 从最具体到最通用排列
  static const _fallbackChapterSelectors = [
    // 具体的章节列表选择器
    '.listmain dd a',        // 笔趣阁类站点
    '#list dd a',            // 笔趣阁变体
    '.chapter-list a',       // 通用章节列表
    '.chapter-list li a',
    '.catalog li a',         // 目录类
    '.mulu li a',            // 目录(中文)
    '#chapterList a',        // ID形式
    '#chapterlist a',
    'ul.chapter li a',
    '.volume dd a',          // 卷章结构
    '.box_con dd a',
    '#info dd a',
    '.zjlist dd a',          // 章节列表
    '.dirlist li a',         // 目录列表
    '.read-content-wrap li a',
    '.novel_list li a',
    // 更通用的选择器
    'dd a',                  // 直接dd里的链接
    'dl a',                  // dl里的链接
    '.content a',            // 内容区域链接
    '#content a',
    '.main a',               // 主体区域链接
    '#main a',
    '.article a',            // 文章区域
    'article a',
    '.body a',
    // 非常通用的选择器（最后尝试）
    'ul li a',               // 任何列表链接
    'ol li a',
  ];

  /// 解析章节列表
  List<OnlineChapter> _parseChapterList(
    BookSource source,
    dynamic responseData,
    String baseUrl,
  ) {
    final rule = source.ruleToc;
    if (rule == null) {
      logger.d('书源 ${source.displayName} 没有目录规则 (ruleToc is null)');
      // 尝试使用备用选择器
      return _parseChapterListWithFallback(responseData, baseUrl);
    }

    final chapterListRule = rule.chapterList;
    if (chapterListRule == null || chapterListRule.isEmpty) {
      logger.d('书源 ${source.displayName} 没有章节列表规则 (chapterList is empty)');
      return _parseChapterListWithFallback(responseData, baseUrl);
    }

    logger.d('解析章节列表, 规则: $chapterListRule');
    var chapterList = RuleParser.parseRuleList(chapterListRule, responseData, baseUrl: baseUrl);
    
    // 如果主规则解析失败，尝试备用选择器
    if (chapterList.isEmpty) {
      logger.d('章节列表解析结果为空, 响应数据类型: ${responseData.runtimeType}');
      logger.d('尝试使用备用选择器...');
      return _parseChapterListWithFallback(responseData, baseUrl, primaryRule: rule);
    }
    
    logger.d('解析到 ${chapterList.length} 个章节项');
    return _extractChaptersFromList(chapterList, rule, baseUrl);
  }

  /// 使用备用选择器解析章节列表
  List<OnlineChapter> _parseChapterListWithFallback(
    dynamic responseData,
    String baseUrl, {
    TocRule? primaryRule,
  }) {
    // 跟踪最佳结果
    List<OnlineChapter> bestChapters = [];
    String? bestSelector;
    
    for (final selector in _fallbackChapterSelectors) {
      final chapterList = RuleParser.parseRuleList(selector, responseData, baseUrl: baseUrl);
      if (chapterList.isEmpty) continue;
      
      logger.d('备用选择器 "$selector" 匹配到 ${chapterList.length} 个元素');
      
      // 使用通用规则提取章节信息
      final chapters = <OnlineChapter>[];
      for (var i = 0; i < chapterList.length; i++) {
        final item = chapterList[i];
        try {
          // 尝试从HTML元素中提取信息
          final name = RuleParser.parseRule('@css:a@text', item, baseUrl: baseUrl) ??
                       RuleParser.parseRule('text', item, baseUrl: baseUrl);
          final url = RuleParser.parseRule('@css:a@href', item, baseUrl: baseUrl) ??
                      RuleParser.parseRule('href', item, baseUrl: baseUrl);
          
          if (name != null && name.isNotEmpty && url != null && url.isNotEmpty) {
            // 过滤非章节链接
            if (_isLikelyChapterUrl(url, name)) {
              chapters.add(OnlineChapter(
                name: name.trim(),
                url: url,
                isVolume: false,
              ));
            }
          }
        } catch (e) {
          // 忽略单个章节解析失败
        }
      }
      
      // 如果解析出足够多的章节（高置信度），立即返回
      if (chapters.length >= 10) {
        logger.i('备用选择器成功: "$selector", 解析出 ${chapters.length} 个章节 (高置信度)');
        return chapters;
      }
      
      // 记录最佳结果
      if (chapters.length > bestChapters.length) {
        bestChapters = chapters;
        bestSelector = selector;
        logger.d('选择器 "$selector" 解析出 ${chapters.length} 个章节 (当前最佳)');
      }
    }
    
    // 如果最佳结果包含至少3个章节，使用它
    if (bestChapters.length >= 3) {
      logger.i('使用最佳备用选择器: "$bestSelector", 解析出 ${bestChapters.length} 个章节');
      return bestChapters;
    }
    
    // 所有选择器都失败，输出HTML结构帮助调试
    if (responseData is String && responseData.length > 100) {
      // 提取 body 部分
      final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*)', caseSensitive: false)
          .firstMatch(responseData);
      if (bodyMatch != null) {
        final bodyContent = bodyMatch.group(1) ?? '';
        // 显示更多内容用于调试
        final preview = bodyContent.length > 2000 
            ? '${bodyContent.substring(0, 2000)}...' 
            : bodyContent;
        logger.w('所有选择器失败，HTML body 预览:\n$preview');
        
        // 额外分析：查找所有 <a> 标签
        final linkPattern = RegExp(r'<a[^>]+href="([^"]+)"[^>]*>([^<]*)</a>', caseSensitive: false);
        final allLinks = linkPattern.allMatches(responseData).toList();
        if (allLinks.isNotEmpty) {
          logger.w('HTML中包含 ${allLinks.length} 个链接，示例:');
          var count = 0;
          for (final match in allLinks) {
            if (count >= 10) break;
            final href = match.group(1);
            final text = match.group(2);
            logger.w('  链接: $text -> $href');
            count++;
          }
        }
      }
    }
    
    logger.w('所有备用选择器均未能解析章节列表');
    return [];
  }

  /// 判断URL是否可能是章节链接
  bool _isLikelyChapterUrl(String url, String name) {
    final lowerUrl = url.toLowerCase();
    final lowerName = name.toLowerCase();
    
    // 排除明显的非章节链接
    final excludePatterns = [
      'javascript:', 'mailto:', '#', 
      'login', 'register', 'search', 
      'index', 'home', 'about', 'contact',
      'category', 'tag', 'author',
    ];
    for (final pattern in excludePatterns) {
      if (lowerUrl.contains(pattern)) return false;
    }
    
    // 章节链接通常包含这些特征
    final chapterPatterns = [
      r'\d+\.html?$',           // 以数字.html结尾
      r'/\d+/?$',               // 以数字结尾
      r'chapter',               // 包含chapter
      r'chap',
      r'zhang',                 // 中文拼音
      r'/\d{1,6}/',             // URL路径中有数字
    ];
    
    for (final pattern in chapterPatterns) {
      if (RegExp(pattern).hasMatch(lowerUrl)) return true;
    }
    
    // 章节名称通常包含这些特征
    final chapterNamePatterns = [
      r'第.+章',                // 第X章
      r'第.+节',                // 第X节
      r'chapter\s*\d',          // Chapter N
      r'^\d+[\.\s]',            // 以数字开头
      r'第\d+',                 // 第N
    ];
    
    for (final pattern in chapterNamePatterns) {
      if (RegExp(pattern).hasMatch(lowerName)) return true;
    }
    
    // 如果名称看起来像正常的中文章节名（2-50字符，非纯符号）
    if (name.length >= 2 && name.length <= 50) {
      final hasChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(name);
      if (hasChinese) return true;
    }
    
    return false;
  }

  /// 从解析结果列表中提取章节信息
  List<OnlineChapter> _extractChaptersFromList(
    List<dynamic> chapterList,
    TocRule rule,
    String baseUrl,
  ) {
    final chapters = <OnlineChapter>[];

    for (var i = 0; i < chapterList.length; i++) {
      final item = chapterList[i];
      try {
        final name = RuleParser.parseRule(rule.chapterName, item, baseUrl: baseUrl);
        final url = RuleParser.parseRule(rule.chapterUrl, item, baseUrl: baseUrl);

        if (name == null || name.isEmpty || url == null || url.isEmpty) {
          if (i < 3) {  // 只记录前几个失败的
            logger.d('章节项[$i] 解析失败: name=$name, url=$url');
          }
          continue;
        }

        final isVolumeStr = RuleParser.parseRule(rule.isVolume, item, baseUrl: baseUrl);
        final isVolume = isVolumeStr == 'true' || isVolumeStr == '1';

        chapters.add(OnlineChapter(
          name: name,
          url: url,
          isVolume: isVolume,
          updateTime: RuleParser.parseRule(rule.updateTime, item, baseUrl: baseUrl),
        ));
      } catch (e, st) {
        AppError.ignore(e, st, '解析章节项失败');
      }
    }

    logger.d('成功解析 ${chapters.length} 个章节');
    return chapters;
  }

  /// 获取章节内容
  Future<String?> getChapterContent(
    BookSource source,
    OnlineChapter chapter,
  ) async {
    try {
      final rule = source.ruleContent;
      if (rule == null) {
        logger.w('书源 ${source.displayName} 没有正文规则');
        return null;
      }

      // 获取所有页的内容
      final allContent = StringBuffer();
      var currentUrl = chapter.url;
      var pageCount = 0;
      const maxPages = 20; // 防止无限循环

      while (currentUrl.isNotEmpty && pageCount < maxPages) {
        final response = await _makeRequest(source, currentUrl);
        if (response == null) break;

        // 解析正文
        var content = RuleParser.parseRule(rule.content, response, baseUrl: currentUrl);
        if (content == null || content.isEmpty) break;

        // 应用净化规则
        content = RuleParser.applyReplaceRules(content, rule.replaceRegex);

        allContent.write(content);

        // 检查是否有下一页
        final nextUrl = RuleParser.parseRule(rule.nextContentUrl, response, baseUrl: currentUrl);
        if (nextUrl == null || nextUrl.isEmpty || nextUrl == currentUrl) {
          break;
        }
        currentUrl = nextUrl;
        pageCount++;

        // 添加分页分隔
        allContent.write('\n\n');
      }

      final result = allContent.toString().trim();
      if (result.isEmpty) {
        logger.w('获取章节内容为空: ${chapter.name}');
        return null;
      }

      logger.d('获取章节内容成功: ${chapter.name}, 长度: ${result.length}');
      return result;
    } catch (e, st) {
      AppError.handle(e, st, 'getChapterContent');
      return null;
    }
  }

  /// 发送HTTP请求（带重试机制）
  Future<dynamic> _makeRequest(BookSource source, String url, {int maxRetries = 3}) async {
    Exception? lastError;
    
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final options = Options(
          headers: _buildHeaders(source, url),
          responseType: ResponseType.plain,
        );

        final response = await _dio.get<String>(
          url,
          options: options,
        );

        if (response.statusCode != 200) {
          logger.w('请求失败: $url, 状态码: ${response.statusCode}');
          return null;
        }

        final data = response.data;
        if (data == null) return null;

        // 尝试解析为JSON
        try {
          return jsonDecode(data);
        } catch (_) {
          // 不是JSON，返回HTML
          return data;
        }
      } on DioException catch (e) {
        lastError = e;
        if (attempt < maxRetries) {
          // 指数退避延迟: 500ms, 1000ms, 2000ms
          final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
          logger.d('请求失败，${delay.inMilliseconds}ms 后重试 ($attempt/$maxRetries): $url');
          await Future<void>.delayed(delay);
        }
      } catch (e, st) {
        AppError.ignore(e, st, '请求失败: $url');
        return null;
      }
    }
    
    if (lastError != null) {
      AppError.ignore(lastError, StackTrace.current, '请求失败(重试$maxRetries次后): $url');
    }
    return null;
  }

  /// 构建请求头（带随机 User-Agent）
  Map<String, String> _buildHeaders(BookSource source, String url) {
    // 从 URL 提取 Referer
    String referer;
    try {
      final uri = Uri.parse(url);
      referer = '${uri.scheme}://${uri.host}/';
    } catch (_) {
      referer = source.bookSourceUrl;
    }
    
    final headers = <String, String>{
      'User-Agent': _userAgents[_random.nextInt(_userAgents.length)],
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-US;q=0.7',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Referer': referer,
      'Cache-Control': 'max-age=0',
    };

    // 解析书源中的自定义请求头
    if (source.header != null && source.header!.isNotEmpty) {
      try {
        final customHeaders = jsonDecode(source.header!) as Map<String, dynamic>;
        for (final entry in customHeaders.entries) {
          headers[entry.key] = entry.value.toString();
        }
      } catch (_) {
        // 可能是 key=value 格式
        for (final line in source.header!.split('\n')) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            headers[parts[0].trim()] = parts.sublist(1).join(':').trim();
          }
        }
      }
    }

    return headers;
  }
}
