import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 歌词翻译目标语言（BCP-47）。primuse 那 9 种，按使用频率排序。
enum LyricsTranslationLang {
  zhHans('zh-CN', '简体中文'),
  zhHant('zh-TW', '繁体中文'),
  en('en', 'English'),
  ja('ja', '日本語'),
  ko('ko', '한국어'),
  fr('fr', 'Français'),
  de('de', 'Deutsch'),
  es('es', 'Español'),
  ru('ru', 'Русский');

  const LyricsTranslationLang(this.bcp47, this.displayName);

  final String bcp47;
  final String displayName;

  static LyricsTranslationLang fromBcp47(String code) {
    for (final v in values) {
      if (v.bcp47 == code) return v;
    }
    return LyricsTranslationLang.zhHans;
  }
}

/// 翻译 provider 抽象。新增 provider（DeepL / OpenAI / Gemini）实现这个接口即可。
abstract class TranslationProvider {
  String get id;
  String get displayName;

  /// 批量翻译。返回值数组与输入 [texts] 一一对应；失败的项返回 null。
  Future<List<String?>> translate({
    required List<String> texts,
    required String targetLangBcp47,
  });
}

/// 默认 provider：调用 Google Translate 公共 API（免费 / 无需 key）。
/// API 文档无官方地址，是社区常用反向工程端点；返回 JSON 数组。
/// 仅适合个人使用，请求量大时可能被 rate-limit。
class GoogleFreeTranslationProvider implements TranslationProvider {
  GoogleFreeTranslationProvider() : _dio = Dio();

  final Dio _dio;

  @override
  String get id => 'google_free';

  @override
  String get displayName => 'Google 翻译（免费）';

  @override
  Future<List<String?>> translate({
    required List<String> texts,
    required String targetLangBcp47,
  }) async {
    final out = <String?>[];
    for (final t in texts) {
      out.add(await _translateOne(t, targetLangBcp47));
    }
    return out;
  }

  Future<String?> _translateOne(String text, String tl) async {
    if (text.trim().isEmpty) return null;
    try {
      final resp = await _dio.get<dynamic>(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {
          'client': 'gtx',
          'sl': 'auto',
          'tl': tl,
          'dt': 't',
          'q': text,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final data = resp.data;
      // 返回结构：[[[translatedText, sourceText, ...], ...], null, ...]
      if (data is List && data.isNotEmpty && data.first is List) {
        final segments = (data.first as List).cast<dynamic>();
        final buf = StringBuffer();
        for (final seg in segments) {
          if (seg is List && seg.isNotEmpty && seg.first is String) {
            buf.write(seg.first as String);
          }
        }
        final translated = buf.toString().trim();
        return translated.isEmpty ? null : translated;
      }
    } on Exception catch (e) {
      logger.w('GoogleTranslate: 失败 "$text": $e');
    }
    return null;
  }
}

/// 歌词翻译服务：
/// - 多 provider 可选，目前默认 [GoogleFreeTranslationProvider]
/// - SHA256(targetLang+source) 作 cache key，5000 条 LRU
/// - 失败结果按 24h negative cache，避免反复失败请求
class LyricsTranslationService {
  LyricsTranslationService._();
  static final LyricsTranslationService instance =
      LyricsTranslationService._();

  static const int _maxEntries = 5000;
  static const Duration _negativeTtl = Duration(hours: 24);
  static const String _boxName = 'lyrics_translation_cache';

  final TranslationProvider _provider = GoogleFreeTranslationProvider();
  Box<dynamic>? _box;
  Timer? _saveDebounce;

  Future<void> _ensureBox() async {
    if (_box != null) return;
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  String _key(String targetLang, String source) {
    final h = sha256.convert(utf8.encode('$targetLang|$source')).toString();
    return h.substring(0, 16);
  }

  /// 批量翻译。命中 cache 的不发请求；未命中时调 provider，结果回填。
  Future<Map<String, String?>> translateBatch({
    required List<String> texts,
    required String targetLang,
  }) async {
    await _ensureBox();
    final results = <String, String?>{};
    final toFetch = <String>[];

    for (final text in texts) {
      if (text.trim().isEmpty) continue;
      final key = _key(targetLang, text);
      final cached = _box!.get(key);
      if (cached is Map) {
        final ts = (cached['ts'] as num?)?.toInt() ?? 0;
        final value = cached['v'] as String?;
        // negative cache: value == null 且未超 TTL → 直接给 null，不重试
        if (value == null) {
          final age = DateTime.now().millisecondsSinceEpoch - ts;
          if (age < _negativeTtl.inMilliseconds) {
            results[text] = null;
            continue;
          }
        } else {
          results[text] = value;
          continue;
        }
      }
      toFetch.add(text);
    }

    if (toFetch.isEmpty) return results;

    final translated = await AppError.guard(
      () => _provider.translate(texts: toFetch, targetLangBcp47: targetLang),
      action: 'lyricsTranslation.${_provider.id}',
      fallback: List<String?>.filled(toFetch.length, null),
    );
    final list = translated ?? List<String?>.filled(toFetch.length, null);

    for (var i = 0; i < toFetch.length; i++) {
      final src = toFetch[i];
      final value = i < list.length ? list[i] : null;
      results[src] = value;
      final key = _key(targetLang, src);
      await _box!.put(key, {
        'v': value,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
    _scheduleEvict();
    return results;
  }

  void _scheduleEvict() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 5), () {
      AppError.fireAndForget(_evict(), action: 'lyricsTranslation.evict');
    });
  }

  Future<void> _evict() async {
    await _ensureBox();
    if (_box!.length <= _maxEntries) return;
    // 简单 LRU 近似：按 timestamp 排序，淘汰最老的 20%
    final entries = <(dynamic, int)>[];
    for (final key in _box!.keys) {
      final v = _box!.get(key);
      if (v is Map) {
        entries.add((key, (v['ts'] as num?)?.toInt() ?? 0));
      }
    }
    entries.sort((a, b) => a.$2.compareTo(b.$2));
    final toRemove = (entries.length * 0.2).round();
    for (var i = 0; i < toRemove; i++) {
      await _box!.delete(entries[i].$1);
    }
  }

  Future<void> clearCache() async {
    await _ensureBox();
    await _box!.clear();
  }
}
