import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:json_path/json_path.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// 规则解析器
///
/// 支持多种规则语法：
/// - JSONPath: `$.data.list`
/// - XPath: `//div[@class='content']`
/// - CSS选择器: `div.content@text` 或 `class.content`
/// - 正则表达式: `regex:pattern`
/// - 组合规则: 使用 `##` 或 `||` 分隔
class RuleParser {

  /// 解析单条规则，返回第一个匹配结果
  static String? parseRule(String? rule, dynamic source, {String? baseUrl}) {
    if (rule == null || rule.isEmpty) return null;
    if (source == null) return null;

    try {
      // 处理组合规则（使用 || 分隔，表示或关系）
      if (rule.contains('||')) {
        for (final subRule in rule.split('||')) {
          final result = _parseSingleRule(subRule.trim(), source, baseUrl: baseUrl);
          if (result != null && result.isNotEmpty) {
            return result;
          }
        }
        return null;
      }

      // 处理链式规则（使用 ## 分隔，表示顺序执行）
      if (rule.contains('##')) {
        dynamic currentSource = source;
        for (final subRule in rule.split('##')) {
          final result = _parseSingleRule(subRule.trim(), currentSource, baseUrl: baseUrl);
          if (result == null) return null;
          currentSource = result;
        }
        return currentSource?.toString();
      }

      return _parseSingleRule(rule, source, baseUrl: baseUrl);
    } catch (e, st) {
            logger.w('规则解析失败: $rule', e, st);
      return null;
    }
  }

  /// 解析规则，返回所有匹配结果列表
  static List<dynamic> parseRuleList(String? rule, dynamic source, {String? baseUrl}) {
    if (rule == null || rule.isEmpty) return [];
    if (source == null) return [];

    try {
      return _parseSingleRuleList(rule, source, baseUrl: baseUrl);
    } catch (e, st) {
            logger.w('规则列表解析失败: $rule', e, st);
      return [];
    }
  }

  /// 解析单条规则
  static String? _parseSingleRule(String rule, dynamic source, {String? baseUrl}) {
    var processedRule = rule.trim();
    String? attrName;
    
    // 1. 首先处理 Legado 格式的前缀规则
    // @css: 开头表示 CSS 选择器
    if (processedRule.startsWith('@css:')) {
      processedRule = processedRule.substring(5);
      // 检查是否有属性提取 (如 @css:div.title@text)
      if (processedRule.contains('@')) {
        final attrIndex = processedRule.lastIndexOf('@');
        attrName = processedRule.substring(attrIndex + 1);
        processedRule = processedRule.substring(0, attrIndex);
      }
      final result = _parseCssSelector(processedRule, source, attrName: attrName);
      return _processResult(result, attrName, baseUrl);
    }
    
    // @json: 开头表示 JSONPath
    if (processedRule.startsWith('@json:')) {
      processedRule = processedRule.substring(6);
      final result = _parseJsonPath(processedRule.startsWith(r'$') ? processedRule : '\$.$processedRule', source);
      return _processResult(result, null, baseUrl);
    }
    
    // @XPath: 开头表示 XPath
    if (processedRule.startsWith('@XPath:') || processedRule.startsWith('@xpath:')) {
      processedRule = processedRule.substring(7);
      final result = _parseXPath(processedRule, source);
      return _processResult(result, null, baseUrl);
    }
    
    // 2. 处理 JSOUP 默认语法中的 @ 属性提取
    // 只有非前缀规则才处理 @ 作为属性分隔符
    if (processedRule.contains('@') && !processedRule.startsWith('//') && !processedRule.startsWith('/')) {
      final attrIndex = processedRule.lastIndexOf('@');
      final potentialAttr = processedRule.substring(attrIndex + 1);
      // 确保 @ 后面是有效的属性名（如 text, href, src 等）
      if (_isValidAttributeName(potentialAttr)) {
        attrName = potentialAttr;
        processedRule = processedRule.substring(0, attrIndex);
      }
    }

    String? result;

    // JSONPath 规则
    if (processedRule.startsWith(r'$.') || processedRule.startsWith(r'$[')) {
      result = _parseJsonPath(processedRule, source);
    }
    // XPath 规则
    else if (processedRule.startsWith('//') || processedRule.startsWith('/')) {
      result = _parseXPath(processedRule, source, attrName: attrName);
      attrName = null; // 已在XPath中处理
    }
    // 正则表达式
    else if (processedRule.startsWith('regex:')) {
      result = _parseRegex(processedRule.substring(6), source.toString());
    }
    // 检测隐式正则表达式模式
    else if (_isLikelyRegexPattern(processedRule)) {
      result = source?.toString();
    }
    // CSS选择器 (包含 . # [ 或空格)
    else if (processedRule.contains('.') || processedRule.contains('#') || 
             processedRule.contains('[') || processedRule.contains(' ') ||
             processedRule.contains('>') || processedRule.contains(':')) {
      result = _parseCssSelector(processedRule, source, attrName: attrName);
      attrName = null;
    }
    // 简单字段名（用于JSON对象）- 如 "title", "author"
    else if (source is Map) {
      // 直接从Map中获取字段值
      final value = source[processedRule];
      result = value?.toString();
    }
    // 纯文本返回
    else {
      result = source?.toString();
    }

    // 处理属性提取
    if (attrName != null && result != null) {
      result = _extractAttr(result, attrName);
    }

    // 处理相对URL
    if (baseUrl != null && result != null && result.isNotEmpty) {
      result = _resolveUrl(result, baseUrl);
    }

    return result?.trim();
  }

  /// 解析规则并返回列表
  static List<dynamic> _parseSingleRuleList(String rule, dynamic source, {String? baseUrl}) {
    final trimmedRule = rule.trim();
    
    // @css: CSS选择器
    if (trimmedRule.startsWith('@css:')) {
      var selector = trimmedRule.substring(5);
      // 移除属性提取部分（列表模式不需要）
      if (selector.contains('@')) {
        selector = selector.substring(0, selector.lastIndexOf('@'));
      }
      return _parseCssSelectorList(selector, source);
    }
    
    // @json: JSONPath
    if (trimmedRule.startsWith('@json:')) {
      var path = trimmedRule.substring(6);
      if (!path.startsWith(r'$')) {
        path = '\$.$path';
      }
      return _parseJsonPathList(path, source);
    }
    
    // @XPath: XPath
    if (trimmedRule.startsWith('@XPath:') || trimmedRule.startsWith('@xpath:')) {
      return _parseXPathList(trimmedRule.substring(7), source);
    }
    
    // JSONPath 规则
    if (trimmedRule.startsWith(r'$.') || trimmedRule.startsWith(r'$[')) {
      return _parseJsonPathList(trimmedRule, source);
    }
    
    // XPath 规则
    if (trimmedRule.startsWith('//') || trimmedRule.startsWith('/')) {
      return _parseXPathList(trimmedRule, source);
    }
    
    // CSS选择器
    if (trimmedRule.contains('.') || trimmedRule.contains('#') || 
        trimmedRule.contains('[') || trimmedRule.contains(' ') ||
        trimmedRule.contains('>') || trimmedRule.contains(':')) {
      return _parseCssSelectorList(trimmedRule, source);
    }

    // 默认返回单个结果
    final result = _parseSingleRule(rule, source, baseUrl: baseUrl);
    return result != null ? [result] : [];
  }

  /// 检测是否可能是正则表达式模式
  /// 
  /// 正则表达式通常包含特殊元字符，与 CSS 选择器区分开
  static bool _isLikelyRegexPattern(String pattern) {
    // 包含明显的正则元字符组合
    // *、+、? 前有字符（如 .*, \w+, \d?）
    // 或者包含 |、^、$ 等
    // 或者类似 <.*?> 的 HTML 标签匹配模式
    if (pattern.contains('.*') || 
        pattern.contains('.+') ||
        pattern.contains('.?') ||
        pattern.contains('\\') ||  // 转义字符
        pattern.contains('^') ||   // 行首
        pattern.contains(r'$') ||  // 行尾
        pattern.contains('|') ||   // 或
        (pattern.contains('<') && pattern.contains('>')) // HTML标签模式
    ) {
      return true;
    }
    return false;
  }

  /// 检查是否是有效的属性名
  static bool _isValidAttributeName(String name) {
    const validAttrs = {
      'text', 'textNodes', 'ownText', 'html', 'innerHTML', 'outerHtml',
      'href', 'src', 'alt', 'title', 'value', 'data-', 'id', 'class',
      'content', 'name', 'type', 'action', 'method', 'target',
    };
    final lowerName = name.toLowerCase();
    return validAttrs.any((attr) => lowerName == attr || lowerName.startsWith(attr));
  }

  /// 处理结果（属性提取和URL解析）
  static String? _processResult(String? result, String? attrName, String? baseUrl) {
    if (result == null) return null;
    
    // 处理属性提取
    if (attrName != null && result.isNotEmpty) {
      result = _extractAttr(result, attrName);
    }
    
    // 处理相对URL
    if (baseUrl != null && result != null && result.isNotEmpty) {
      result = _resolveUrl(result, baseUrl);
    }
    
    return result?.trim();
  }

  /// 解析 JSONPath
  static String? _parseJsonPath(String path, dynamic json) {
    try {
      dynamic data = json;
      if (json is String) {
        // 如果是字符串，尝试解析为JSON
        // 注意：这里不做JSON解析，假设调用者已经提供了正确的数据类型
        return null;
      }
      
      final jsonPath = JsonPath(path);
      final matches = jsonPath.read(data);
      if (matches.isEmpty) return null;
      
      final value = matches.first.value;
      return value?.toString();
    } catch (e) {
            logger.d('JSONPath解析失败: $path - $e');
      return null;
    }
  }

  /// 解析 JSONPath 返回列表
  static List<dynamic> _parseJsonPathList(String path, dynamic json) {
    try {
      final jsonPath = JsonPath(path);
      final matches = jsonPath.read(json);
      
      if (matches.isEmpty) return [];
      
      final firstMatch = matches.first.value;
      if (firstMatch is List) {
        return firstMatch;
      }
      
      return matches.map((m) => m.value).toList();
    } catch (e) {
            logger.d('JSONPath列表解析失败: $path - $e');
      return [];
    }
  }

  /// 解析 XPath
  static String? _parseXPath(String xpath, dynamic source, {String? attrName}) {
    try {
      String htmlContent;
      if (source is String) {
        htmlContent = source;
      } else if (source is html_dom.Element) {
        htmlContent = source.outerHtml;
      } else if (source is html_dom.Document) {
        htmlContent = source.outerHtml;
      } else {
        return null;
      }

      final document = html_parser.parse(htmlContent);
      final htmlXPath = HtmlXPath.html(document.outerHtml);
      final result = htmlXPath.query(xpath);
      
      if (result.nodes.isEmpty) return null;
      
      final node = result.nodes.first;
      
      // 如果指定了属性名
      if (attrName != null) {
        if (attrName == 'text') {
          return node.text?.trim();
        } else if (attrName == 'html' || attrName == 'outerHtml') {
          return node.toString();
        } else if (node is html_dom.Element) {
          return node.attributes[attrName];
        }
      }
      
      return node.text?.trim();
    } catch (e) {
            logger.d('XPath解析失败: $xpath - $e');
      return null;
    }
  }

  /// 解析 XPath 返回列表
  static List<dynamic> _parseXPathList(String xpath, dynamic source) {
    try {
      String htmlContent;
      if (source is String) {
        htmlContent = source;
      } else if (source is html_dom.Element) {
        htmlContent = source.outerHtml;
      } else if (source is html_dom.Document) {
        htmlContent = source.outerHtml;
      } else {
        return [];
      }

      final document = html_parser.parse(htmlContent);
      final htmlXPath = HtmlXPath.html(document.outerHtml);
      final result = htmlXPath.query(xpath);
      
      // 返回节点的HTML内容，供后续规则解析
      return result.nodes.map((node) => node.toString()).toList();
    } catch (e) {
            logger.d('XPath列表解析失败: $xpath - $e');
      return [];
    }
  }

  /// 解析 CSS 选择器
  static String? _parseCssSelector(String selector, dynamic source, {String? attrName}) {
    try {
      html_dom.Document document;
      if (source is String) {
        document = html_parser.parse(source);
      } else if (source is html_dom.Element) {
        document = html_parser.parse(source.outerHtml);
      } else if (source is html_dom.Document) {
        document = source;
      } else {
        return null;
      }

      final element = document.querySelector(selector);
      if (element == null) return null;

      if (attrName != null) {
        if (attrName == 'text') {
          return element.text.trim();
        } else if (attrName == 'html' || attrName == 'innerHTML') {
          return element.innerHtml;
        } else if (attrName == 'outerHtml') {
          return element.outerHtml;
        } else {
          return element.attributes[attrName];
        }
      }

      return element.text.trim();
    } catch (e) {
            logger.d('CSS选择器解析失败: $selector - $e');
      return null;
    }
  }

  /// 解析 CSS 选择器返回列表
  static List<dynamic> _parseCssSelectorList(String selector, dynamic source) {
    try {
      // 处理 @ 属性
      var processedSelector = selector;
      if (selector.contains('@')) {
        final attrIndex = selector.lastIndexOf('@');
        processedSelector = selector.substring(0, attrIndex);
      }

      html_dom.Document document;
      if (source is String) {
        document = html_parser.parse(source);
      } else if (source is html_dom.Element) {
        document = html_parser.parse(source.outerHtml);
      } else if (source is html_dom.Document) {
        document = source;
      } else {
        return [];
      }

      final elements = document.querySelectorAll(processedSelector);
      return elements.map((e) => e.outerHtml).toList();
    } catch (e) {
            logger.d('CSS选择器列表解析失败: $selector - $e');
      return [];
    }
  }

  /// 解析正则表达式
  static String? _parseRegex(String pattern, String source) {
    try {
      final regex = RegExp(pattern);
      final match = regex.firstMatch(source);
      if (match == null) return null;
      
      // 如果有分组，返回第一个分组，否则返回整个匹配
      if (match.groupCount > 0) {
        return match.group(1);
      }
      return match.group(0);
    } catch (e) {
            logger.d('正则表达式解析失败: $pattern - $e');
      return null;
    }
  }

  /// 提取属性
  static String? _extractAttr(String htmlOrText, String attrName) {
    if (attrName == 'text') {
      // 去除HTML标签
      return htmlOrText.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    }
    
    // 尝试解析为HTML并提取属性
    try {
      final document = html_parser.parse(htmlOrText);
      final element = document.body?.children.firstOrNull;
      if (element != null) {
        return element.attributes[attrName];
      }
    } catch (_) {}
    
    return null;
  }

  /// 解析相对URL为绝对URL
  static String _resolveUrl(String url, String baseUrl) {
    if (url.isEmpty) return url;
    
    // 已经是绝对URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // 协议相对URL
    if (url.startsWith('//')) {
      final baseUri = Uri.tryParse(baseUrl);
      return '${baseUri?.scheme ?? 'https'}:$url';
    }
    
    // 相对URL
    try {
      final baseUri = Uri.parse(baseUrl);
      final resolvedUri = baseUri.resolve(url);
      return resolvedUri.toString();
    } catch (_) {
      return url;
    }
  }

  /// 应用替换规则净化内容
  static String applyReplaceRules(String content, String? replaceRegex) {
    if (replaceRegex == null || replaceRegex.isEmpty) return content;
    
    var result = content;
    
    // 支持多个替换规则，用 && 分隔
    for (final rule in replaceRegex.split('&&')) {
      final trimmedRule = rule.trim();
      if (trimmedRule.isEmpty) continue;
      
      // 格式: pattern##replacement 或 pattern（删除匹配内容）
      final parts = trimmedRule.split('##');
      final pattern = parts[0];
      final replacement = parts.length > 1 ? parts[1] : '';
      
      try {
        final regex = RegExp(pattern);
        result = result.replaceAll(regex, replacement);
      } catch (e) {
        logger.d('替换规则执行失败: $trimmedRule - $e');
      }
    }
    
    return result;
  }
}
