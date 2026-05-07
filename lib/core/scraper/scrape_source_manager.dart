import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/scraper/scrape_source.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 用户导入的刮削源管理。
///
/// **本应用不内嵌任何 scrape 源**。启动时只读 Hive 中用户主动导入的源，
/// assets/ 不放任何 *.json scrape 模板。导入页面必须显示免责声明。
class ScrapeSourceManager {
  ScrapeSourceManager._();
  static final ScrapeSourceManager instance = ScrapeSourceManager._();

  static const _boxName = 'js_scrape_sources';

  Box<String>? _box;
  bool _initialized = false;
  List<JsScrapeSource>? _cache;

  final _events = StreamController<void>.broadcast();
  Stream<void> get events => _events.stream;

  Future<void> init() async {
    if (_initialized) return;
    _box = Hive.isBoxOpen(_boxName)
        ? Hive.box<String>(_boxName)
        : await Hive.openBox<String>(_boxName);
    await _reload();
    _initialized = true;
    logger.i('ScrapeSourceManager: init ${_cache?.length ?? 0} sources');
  }

  Future<void> _reload() async {
    final list = <JsScrapeSource>[];
    for (final key in _box!.keys) {
      final raw = _box!.get(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        list.add(JsScrapeSource.fromJson(json));
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'scrapeSource.parse', {'key': key});
      }
    }
    list.sort((a, b) => a.customOrder.compareTo(b.customOrder));
    _cache = list;
  }

  Future<List<JsScrapeSource>> getAll() async {
    if (!_initialized) await init();
    return List.unmodifiable(_cache ?? const []);
  }

  Future<List<JsScrapeSource>> getByType(ScrapeSourceType type) async {
    final all = await getAll();
    return all.where((s) => s.type == type && s.enabled).toList();
  }

  Future<JsScrapeSource?> getById(String id) async {
    final all = await getAll();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> addOrUpdate(JsScrapeSource source) async {
    if (!_initialized) await init();
    final updated = source.copyWith(
      lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _box!.put(updated.id, jsonEncode(updated.toJson()));
    await _reload();
    _events.add(null);
  }

  Future<int> addMany(List<JsScrapeSource> sources) async {
    if (!_initialized) await init();
    var added = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    var nextOrder = _cache?.fold<int>(
          0,
          (m, s) => s.customOrder > m ? s.customOrder : m,
        ) ??
        0;
    for (final s in sources) {
      try {
        nextOrder++;
        final entry = s.copyWith(
          customOrder: nextOrder,
          lastUpdateTime: now,
        );
        await _box!.put(entry.id, jsonEncode(entry.toJson()));
        added++;
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'scrapeSource.addMany', {'name': s.name});
      }
    }
    if (added > 0) {
      await _reload();
      _events.add(null);
    }
    return added;
  }

  Future<void> remove(String id) async {
    if (!_initialized) await init();
    await _box!.delete(id);
    await _reload();
    _events.add(null);
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    final s = await getById(id);
    if (s == null) return;
    await addOrUpdate(s.copyWith(enabled: enabled));
  }

  /// 远端拉取并解析 JSON。响应可以是单对象或数组。
  /// 不在此方法内入库；调用方收到列表后再 [addMany]。
  static Future<List<JsScrapeSource>> fetchFromUrl(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json, text/plain, */*'},
    ));
    final resp = await dio.getUri<String>(
      Uri.parse(url),
      options: Options(responseType: ResponseType.plain),
    );
    final body = resp.data ?? '';
    if (body.isEmpty) return const [];
    return parseImport(body);
  }

  /// 解析用户粘贴的 JSON 文本。支持单对象或数组两种形式。
  static List<JsScrapeSource> parseImport(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return [
        for (final e in decoded)
          if (e is Map)
            JsScrapeSource.fromJson(Map<String, dynamic>.from(e)),
      ];
    }
    if (decoded is Map) {
      return [JsScrapeSource.fromJson(Map<String, dynamic>.from(decoded))];
    }
    return const [];
  }

  /// 整体导出（便于备份与跨设备迁移）。
  String exportAll(List<JsScrapeSource> sources) =>
      jsonEncode(sources.map((s) => s.toJson()).toList());
}
