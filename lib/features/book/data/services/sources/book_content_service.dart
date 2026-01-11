import 'dart:convert';

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

  /// 解析章节列表
  List<OnlineChapter> _parseChapterList(
    BookSource source,
    dynamic responseData,
    String baseUrl,
  ) {
    final rule = source.ruleToc;
    if (rule == null) {
      logger.d('书源 ${source.displayName} 没有目录规则 (ruleToc is null)');
      return [];
    }

    final chapterListRule = rule.chapterList;
    if (chapterListRule == null || chapterListRule.isEmpty) {
      logger.d('书源 ${source.displayName} 没有章节列表规则 (chapterList is empty)');
      return [];
    }

    logger.d('解析章节列表, 规则: $chapterListRule');
    final chapterList = RuleParser.parseRuleList(chapterListRule, responseData, baseUrl: baseUrl);
    if (chapterList.isEmpty) {
      logger.d('章节列表解析结果为空, 响应数据类型: ${responseData.runtimeType}');
      return [];
    }
    
    logger.d('解析到 ${chapterList.length} 个章节项');

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

  /// 发送HTTP请求
  Future<dynamic> _makeRequest(BookSource source, String url) async {
    try {
      final options = Options(
        headers: _buildHeaders(source),
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
    } catch (e, st) {
      AppError.ignore(e, st, '请求失败: $url');
      return null;
    }
  }

  /// 构建请求头
  Map<String, String> _buildHeaders(BookSource source) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
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
