import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/sources/book_source_manager_service.dart';
import 'package:my_nas/features/book/data/services/sources/rule_parser.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';

/// 在线书籍搜索服务
///
/// 支持多书源并行搜索，返回聚合结果
class BookSearchService {
  BookSearchService._();

  static final instance = BookSearchService._();

  final _dio = Dio();

  /// 搜索书籍（多书源并行）
  ///
  /// 返回一个 Stream，每当有书源返回结果时就 yield
  Stream<OnlineBook> search(String keyword, {int page = 1}) async* {
    logger.d('📚 BookSearchService.search() 开始搜索: keyword="$keyword", page=$page');
    
    final sources = await BookSourceManagerService.instance.getEnabledSources();
    logger.d('📚 已启用的书源数量: ${sources.length}');

    if (sources.isEmpty) {
      logger.w('📚 没有可用的书源（请在书源管理中启用至少一个书源）');
      return;
    }

    // 并行搜索所有书源
    final searchableSources = sources
        .where((s) => s.searchUrl != null && s.searchUrl!.isNotEmpty)
        .toList();
    
    logger.d('📚 有搜索URL的书源数量: ${searchableSources.length}');
    
    if (searchableSources.isEmpty) {
      logger.w('📚 没有配置搜索URL的书源');
      return;
    }
    
    final futures = searchableSources.map((source) => _searchSource(source, keyword, page));

    // 使用 Stream.fromFutures 处理并行结果
    await for (final results in Stream.fromFutures(futures)) {
      for (final book in results) {
        yield book;
      }
    }
    
    logger.d('📚 BookSearchService.search() 搜索完成');
  }

  /// 搜索单个书源
  Future<List<OnlineBook>> _searchSource(
    BookSource source,
    String keyword,
    int page,
  ) async {
    try {
      // 构建搜索URL
      final searchUrl = _buildSearchUrl(source, keyword, page);
      if (searchUrl == null) return [];

      logger.d('搜索书源: ${source.displayName}, URL: $searchUrl');

      // 发送请求
      final response = await _makeRequest(source, searchUrl);
      if (response == null) return [];

      // 解析结果
      return _parseSearchResults(source, response, searchUrl);
    } catch (e, st) {
      AppError.ignore(e, st, '书源搜索失败: ${source.displayName}');
      return [];
    }
  }

  /// 构建搜索URL
  String? _buildSearchUrl(BookSource source, String keyword, int page) {
    var url = source.searchUrl;
    if (url == null || url.isEmpty) return null;

    // 替换关键词变量
    url = url
        .replaceAll('{{key}}', Uri.encodeComponent(keyword))
        .replaceAll('{{page}}', page.toString())
        .replaceAll(r'${key}', Uri.encodeComponent(keyword))
        .replaceAll(r'${page}', page.toString());

    // 处理相对URL
    if (!url.startsWith('http')) {
      url = '${source.bookSourceUrl}$url';
    }

    return url;
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

  /// 解析搜索结果
  List<OnlineBook> _parseSearchResults(
    BookSource source,
    dynamic responseData,
    String baseUrl,
  ) {
    final rule = source.ruleSearch;
    if (rule == null) return [];

    // 获取书籍列表
    final bookListRule = rule.bookList;
    if (bookListRule == null || bookListRule.isEmpty) return [];

    final bookList = RuleParser.parseRuleList(bookListRule, responseData, baseUrl: baseUrl);
    if (bookList.isEmpty) return [];

    final books = <OnlineBook>[];

    for (final item in bookList) {
      try {
        var name = RuleParser.parseRule(rule.name, item, baseUrl: baseUrl);
        final bookUrl = RuleParser.parseRule(rule.bookUrl, item, baseUrl: baseUrl);

        // 书名和URL是必须的
        if (name == null || name.isEmpty || bookUrl == null || bookUrl.isEmpty) {
          continue;
        }

        // 智能处理书名 - 如果书名看起来像URL，尝试提取真实书名
        name = _sanitizeBookName(name, bookUrl);
        
        // 跳过无法提取有效书名的结果
        if (name.isEmpty || name == bookUrl) {
          continue;
        }

        books.add(OnlineBook(
          name: name,
          author: _sanitizeText(RuleParser.parseRule(rule.author, item, baseUrl: baseUrl)),
          bookUrl: bookUrl,
          coverUrl: RuleParser.parseRule(rule.coverUrl, item, baseUrl: baseUrl),
          intro: _sanitizeText(RuleParser.parseRule(rule.intro, item, baseUrl: baseUrl)),
          kind: _sanitizeText(RuleParser.parseRule(rule.kind, item, baseUrl: baseUrl)),
          lastChapter: _sanitizeText(RuleParser.parseRule(rule.lastChapter, item, baseUrl: baseUrl)),
          wordCount: _sanitizeText(RuleParser.parseRule(rule.wordCount, item, baseUrl: baseUrl)),
          source: source,
        ));
      } catch (e, st) {
        AppError.ignore(e, st, '解析搜索结果项失败');
      }
    }

    logger.i('书源 ${source.displayName} 搜索到 ${books.length} 本书');
    return books;
  }

  /// 智能处理书名
  /// 
  /// 如果书名看起来像URL，尝试从URL路径中提取真实书名
  String _sanitizeBookName(String name, String bookUrl) {
    // 如果书名不像URL，直接返回
    if (!name.startsWith('http://') && !name.startsWith('https://')) {
      // 尝试URL解码（处理 %XX 编码的中文）
      try {
        final decoded = Uri.decodeComponent(name);
        if (decoded != name && !decoded.contains('%')) {
          return decoded.trim();
        }
      } catch (_) {}
      return name.trim();
    }
    
    // 书名看起来像URL，尝试从URL路径中提取书名
    try {
      final uri = Uri.parse(name);
      final path = uri.path;
      
      // 移除常见的路径前缀和后缀
      var extractedName = path
          .replaceAll(RegExp(r'^/+'), '')  // 移除开头的斜杠
          .replaceAll(RegExp(r'\.(html?|php|aspx?|jsp)$', caseSensitive: false), '')  // 移除文件扩展名
          .replaceAll(RegExp(r'/+$'), '');  // 移除结尾的斜杠
      
      // URL解码
      extractedName = Uri.decodeComponent(extractedName);
      
      // 如果提取到的是一堆数字或太短，则无效
      if (extractedName.isEmpty || 
          RegExp(r'^\d+$').hasMatch(extractedName) ||
          extractedName.length < 2) {
        return '';  // 返回空表示无效
      }
      
      // 取路径最后一部分作为书名
      final parts = extractedName.split('/');
      return parts.last.trim();
    } catch (_) {
      return '';
    }
  }
  
  /// 清理文本字段
  /// 
  /// 移除URL前缀，URL解码中文字符
  String _sanitizeText(String? text) {
    if (text == null || text.isEmpty) return '';
    
    var result = text;
    
    // 如果文本是URL，返回空（这些字段不应该是URL）
    if (result.startsWith('http://') || result.startsWith('https://')) {
      return '';
    }
    
    // 尝试URL解码
    try {
      final decoded = Uri.decodeComponent(result);
      if (decoded != result && !decoded.contains('%')) {
        result = decoded;
      }
    } catch (_) {}
    
    // 清理HTML标签
    result = result.replaceAll(RegExp(r'<[^>]*>'), '');
    
    return result.trim();
  }

  /// 搜索书籍（返回聚合列表）
  ///
  /// 等待所有书源搜索完成后返回去重结果
  Future<List<OnlineBook>> searchAll(String keyword, {int page = 1}) async {
    final books = <OnlineBook>[];
    final seen = <String>{};

    await for (final book in search(keyword, page: page)) {
      // 根据书名+作者去重
      final key = book.uniqueKey;
      if (!seen.contains(key)) {
        seen.add(key);
        books.add(book);
      }
    }

    return books;
  }
}
