/// 一个可同步的模块自我描述。
///
/// 每个模块（音乐播放列表、视频播放进度、阅读进度等）实现该接口后注册到
/// [CloudSyncRegistry]，[CloudSyncService] 会按 enabled 列表逐个同步。
abstract class SyncableModule {
  /// 全局唯一 key，用作 manifest.json 字段名 + WebDAV 文件名（`<key>.json`）
  String get key;

  /// 用户可见名称（设置页显示）
  String get displayName;

  /// 该模块本地最后变更时间。用于判断本地 / 远端谁更新。
  Future<DateTime?> getLocalUpdatedAt();

  /// 序列化整个模块的同步数据。结构由模块自己定。
  Future<Map<String, dynamic>> exportData();

  /// 导入远端数据。该方法负责合并到本地存储；最简单实现可整体覆盖。
  Future<void> importData(Map<String, dynamic> data);
}

/// 注册中心：统一收集所有 SyncableModule
class CloudSyncRegistry {
  CloudSyncRegistry._();
  static final CloudSyncRegistry instance = CloudSyncRegistry._();

  final List<SyncableModule> _modules = [];

  void register(SyncableModule module) {
    if (_modules.any((m) => m.key == module.key)) return;
    _modules.add(module);
  }

  List<SyncableModule> get modules => List.unmodifiable(_modules);

  SyncableModule? byKey(String key) {
    for (final m in _modules) {
      if (m.key == key) return m;
    }
    return null;
  }
}
