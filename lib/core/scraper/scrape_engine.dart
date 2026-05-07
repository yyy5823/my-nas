import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:json_path/json_path.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/scraper/scrape_source.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// 用户导入的声明式刮削源执行引擎。
///
/// 设计要点：
/// - **不内嵌任何源**：本引擎只在用户导入的 [JsScrapeSource] 上运行。
/// - **不执行用户脚本**：避免 eval 沙箱风险，仅按声明式规则解析。
/// - **支持 4 种 selector 前缀**：xpath / json / regex / css（默认）。
class ScrapeEngine {
  ScrapeEngine._();
  static final ScrapeEngine instance = ScrapeEngine._();

  Dio? _dio;
  Dio get _http => _dio ??= Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Accept': '*/*',
          },
        ),
      );

  /// 按 source 配置搜索关键词，返回结构化条目数组。
  Future<List<ScrapeItem>> search(
    JsScrapeSource source,
    String keyword,
  ) async {
    final req = source.searchRequest;
    final itemRule = source.searchItemRule;
    if (req == null || itemRule == null) return const [];
    try {
      final body = await _execute(req, source.headers, vars: {'query': keyword});
      if (body == null) return const [];
      return _extractList(
        body,
        responseType: req.responseType,
        listSelector: source.searchListSelector,
        itemRule: itemRule,
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'scrape.search', {
        'source': source.id,
        'keyword': keyword,
      });
      return const [];
    }
  }

  /// 拉取详情并按 detailRule 解析为字段。
  Future<Map<String, String>> getDetail(
    JsScrapeSource source,
    String link,
  ) async {
    final req = source.detailRequest;
    final rule = source.detailRule;
    if (req == null || rule == null) return const {};
    try {
      final body = await _execute(req, source.headers, vars: {'link': link});
      if (body == null) return const {};
      return _extractFields(
        body,
        responseType: req.responseType,
        rule: rule,
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'scrape.detail', {
        'source': source.id,
        'link': link,
      });
      return const {};
    }
  }

  /// 根据 lyricRequest 抓取歌词文本。
  Future<String?> getLyric(
    JsScrapeSource source, {
    required String title,
    String? artist,
  }) async {
    final req = source.lyricRequest;
    final selector = source.lyricContentSelector;
    if (req == null || selector == null || selector.isEmpty) return null;
    try {
      final body = await _execute(req, source.headers, vars: {
        'title': title,
        if (artist != null) 'artist': artist,
      });
      if (body == null) return null;
      return _selectSingle(body, req.responseType, selector);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'scrape.lyric', {'source': source.id});
      return null;
    }
  }

  // ============ 私有：执行 ============

  Future<String?> _execute(
    ScrapeRequest req,
    Map<String, String>? headers, {
    required Map<String, String> vars,
  }) async {
    final url = _interpolate(req.url, vars);
    final body = req.body == null ? null : _interpolate(req.body!, vars);

    final options = Options(
      method: req.method,
      headers: headers,
      contentType: req.bodyType == 'json'
          ? 'application/json'
          : (req.bodyType == 'form'
              ? 'application/x-www-form-urlencoded'
              : null),
      responseType: ResponseType.plain,
    );

    final resp = await _http.requestUri<String>(
      Uri.parse(url),
      data: body,
      options: options,
    );
    if (resp.statusCode == null || resp.statusCode! >= 400) {
      logger.w('scrape: ${resp.statusCode} $url');
      return null;
    }
    return resp.data;
  }

  String _interpolate(String template, Map<String, String> vars) {
    var out = template;
    vars.forEach((k, v) {
      out = out.replaceAll('{$k}', Uri.encodeQueryComponent(v));
      out = out.replaceAll('{${k}_raw}', v);
    });
    return out;
  }

  // ============ 私有：解析 ============

  /// 提取列表节点 → 对每个节点用 [itemRule] 解析字段。
  List<ScrapeItem> _extractList(
    String body, {
    required String responseType,
    required String listSelector,
    required ScrapeFieldsRule itemRule,
  }) {
    if (responseType == 'json') {
      final root = jsonDecode(body);
      final nodes = JsonPath(_normalizeJsonPath(listSelector))
          .read(root)
          .map((m) => m.value)
          .toList();
      return [
        for (final n in nodes)
          ScrapeItem(_extractFieldsFromJson(n, itemRule)),
      ];
    }
    // HTML
    final doc = html_parser.parse(body);
    final selector = _SelectorParser.parse(listSelector);
    final fragments = selector.selectFragmentsFromDoc(doc);
    return [
      for (final frag in fragments)
        ScrapeItem(_extractFieldsFromHtml(html_parser.parse(frag), itemRule)),
    ];
  }

  Map<String, String> _extractFields(
    String body, {
    required String responseType,
    required ScrapeFieldsRule rule,
  }) {
    if (responseType == 'json') {
      final root = jsonDecode(body);
      return _extractFieldsFromJson(root, rule);
    }
    final doc = html_parser.parse(body);
    return _extractFieldsFromHtml(doc, rule);
  }

  Map<String, String> _extractFieldsFromHtml(
    dom.Node root,
    ScrapeFieldsRule rule,
  ) {
    final out = <String, String>{};
    rule.fields.forEach((k, sel) {
      final v = _selectSingleFromNode(root, sel);
      if (v != null && v.isNotEmpty) out[k] = v;
    });
    return out;
  }

  Map<String, String> _extractFieldsFromJson(
    dynamic root,
    ScrapeFieldsRule rule,
  ) {
    final out = <String, String>{};
    rule.fields.forEach((k, sel) {
      final v = _readJsonSelector(root, sel);
      if (v != null && v.isNotEmpty) out[k] = v;
    });
    return out;
  }

  String? _selectSingle(String body, String responseType, String selector) {
    if (responseType == 'json') {
      final root = jsonDecode(body);
      return _readJsonSelector(root, selector);
    }
    final doc = html_parser.parse(body);
    return _selectSingleFromNode(doc, selector);
  }

  String? _selectSingleFromNode(dom.Node root, String selector) {
    final s = _SelectorParser.parse(selector);
    return s.selectOne(root);
  }

  String? _readJsonSelector(dynamic root, String selector) {
    final raw = selector.startsWith('json::') ? selector.substring(6) : selector;
    final path = _normalizeJsonPath(raw);
    final values = JsonPath(path).read(root).toList();
    if (values.isEmpty) return null;
    final first = values.first.value;
    return first?.toString();
  }

  String _normalizeJsonPath(String raw) {
    var s = raw.trim();
    if (s.startsWith('json::')) s = s.substring(6);
    if (!s.startsWith(r'$')) s = r'$.' + s;
    return s;
  }
}

/// 解析 selector 字符串，返回一个可执行的策略。
class _SelectorParser {
  _SelectorParser._({
    required this.kind,
    required this.expr,
    this.attr,
  });

  factory _SelectorParser.parse(String raw) {
    var s = raw.trim();
    String? attr;
    final atIdx = s.lastIndexOf('@');
    // 仅识别尾部 `@something`（避免误吞 css 中的 :not 等）
    if (atIdx > 0 && !s.substring(atIdx).contains('/')) {
      attr = s.substring(atIdx + 1).trim();
      s = s.substring(0, atIdx);
    }

    String kind;
    String expr;
    if (s.startsWith('xpath::')) {
      kind = 'xpath';
      expr = s.substring(7);
    } else if (s.startsWith('json::')) {
      kind = 'json';
      expr = s.substring(6);
    } else if (s.startsWith('regex::')) {
      kind = 'regex';
      expr = s.substring(7);
    } else if (s.startsWith('css::')) {
      kind = 'css';
      expr = s.substring(5);
    } else {
      // 默认 css
      kind = 'css';
      expr = s;
    }
    return _SelectorParser._(kind: kind, expr: expr, attr: attr);
  }

  final String kind; // css / xpath / regex / json
  final String expr;
  final String? attr; // text / html / src / href / 任意属性

  /// 抽取列表项；返回每项的 outerHtml 字符串（便于上层重新 parse 后再做子查询，
  /// 避开 xpath_selector 的 XPathNode / dom.Element 类型差异）。
  List<String> selectFragmentsFromDoc(dom.Document doc) {
    if (kind == 'xpath') {
      final result = HtmlXPath.html(doc.outerHtml).query(expr);
      return [for (final n in result.nodes) n.toString()];
    }
    if (kind == 'css') {
      return [for (final el in doc.querySelectorAll(expr)) el.outerHtml];
    }
    return const [];
  }

  String? selectOne(dom.Node root) {
    if (kind == 'css') {
      final el = root is dom.Document
          ? root.querySelector(expr)
          : (root is dom.Element ? root.querySelector(expr) : null);
      if (el == null) return null;
      return _readAttr(el);
    }
    if (kind == 'xpath') {
      // root 可能是 Document 或 Element；通过 outerHtml 包一层再查
      final outer = root is dom.Document
          ? root.outerHtml
          : (root is dom.Element ? root.outerHtml : null);
      if (outer == null) return null;
      final result = HtmlXPath.html(outer).query(expr);
      if (result.nodes.isEmpty) return null;
      // XPathNode 的 .text 由库提供；属性查询通过 toString 走 _readAttrFromHtml
      final first = result.nodes.first;
      final a = attr;
      if (a == null || a == 'text') return first.text?.trim();
      if (a == 'html' || a == 'outerHtml') return first.toString();
      // 其它属性：把节点 toString → 重新 parse 取
      return _readAttrFromHtml(first.toString(), a);
    }
    if (kind == 'regex') {
      final source = root is dom.Element
          ? root.outerHtml
          : (root is dom.Document ? root.outerHtml : root.text ?? '');
      final m = RegExp(expr).firstMatch(source);
      if (m == null) return null;
      return m.groupCount >= 1 ? m.group(1) : m.group(0);
    }
    return null;
  }

  String? _readAttr(dom.Element el) {
    final a = attr;
    if (a == null || a == 'text') return el.text.trim();
    if (a == 'html') return el.innerHtml;
    if (a == 'outerHtml') return el.outerHtml;
    return el.attributes[a];
  }

  String? _readAttrFromHtml(String fragment, String attrName) {
    final doc = html_parser.parse(fragment);
    final root = doc.documentElement ?? doc.body;
    if (root == null) return null;
    return root.attributes[attrName] ?? root.querySelector('*')?.attributes[attrName];
  }
}
