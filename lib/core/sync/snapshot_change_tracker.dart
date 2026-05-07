import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';

/// 帮助没有自带 updatedAt 的模块（例如设置项）在云同步框架下表达
/// 「我什么时候被改过」。
///
/// 工作方式：
/// 1. 调用方传入当前快照 snapshot；
/// 2. 计算 sha256；
/// 3. 与上次记录的 hash 比较；
/// 4. 不同 → 当下时间作为新的 updatedAt 持久化；
/// 5. 相同 → 返回上次记录的 updatedAt（首次为 null）。
///
/// 元数据存放在统一的 `sync_meta` box，key = 调用方提供的 moduleKey。
class SnapshotChangeTracker {
  SnapshotChangeTracker(this.moduleKey);

  static const String _boxName = 'sync_meta';

  final String moduleKey;
  Box<Map<dynamic, dynamic>>? _box;

  Future<Box<Map<dynamic, dynamic>>> _open() async {
    if (_box != null) return _box!;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<Map<dynamic, dynamic>>(_boxName);
    } else {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
    }
    return _box!;
  }

  /// 比较 snapshot 与上次的 hash，按需更新 updatedAt 并返回当前值。
  ///
  /// 当 snapshot 完全为空 / 默认状态时调用方可以传 `null` 表示「无本地数据」，
  /// 此时本方法会返回 null（也不会污染 hash 记录）。
  Future<DateTime?> getUpdatedAt(Object? snapshot) async {
    if (snapshot == null) return null;
    final box = await _open();
    final hash = _hash(snapshot);
    final entry = box.get(moduleKey);
    final prevHash = entry?['hash'] as String?;
    final prevAt = entry?['updatedAt'] as int?;

    if (prevHash == hash && prevAt != null) {
      return DateTime.fromMillisecondsSinceEpoch(prevAt);
    }

    final now = DateTime.now();
    await box.put(moduleKey, {
      'hash': hash,
      'updatedAt': now.millisecondsSinceEpoch,
    });
    return now;
  }

  /// 远端数据被合并到本地之后，调用此方法把追踪器对齐到给定时间，
  /// 避免下一轮同步把刚拉下来的数据又当成本地变更推回去。
  Future<void> recordImported(Object snapshot, DateTime at) async {
    final box = await _open();
    await box.put(moduleKey, {
      'hash': _hash(snapshot),
      'updatedAt': at.millisecondsSinceEpoch,
    });
  }

  String _hash(Object snapshot) {
    final bytes = utf8.encode(jsonEncode(snapshot));
    return sha256.convert(bytes).toString();
  }
}
