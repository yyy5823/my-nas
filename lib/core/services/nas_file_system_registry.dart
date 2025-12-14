import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// NAS 文件系统注册表
///
/// 全局单例，管理 sourceId -> NasFileSystem 的映射。
/// 当连接建立时注册，断开时注销。
/// 任何地方都可以通过 sourceId 获取对应的 fileSystem。
///
/// 使用场景：
/// - 视频海报/背景图需要通过 sourceId 获取 fileSystem 进行流式加载
/// - 无需在组件树中层层传递 fileSystem
///
/// 示例：
/// ```dart
/// // 注册（在连接成功后）
/// NasFileSystemRegistry.instance.register(sourceId, fileSystem);
///
/// // 获取（在需要加载图片时）
/// final fs = NasFileSystemRegistry.instance.get(sourceId);
/// if (fs != null) {
///   final stream = await fs.getFileStream(path);
/// }
///
/// // 注销（在断开连接时）
/// NasFileSystemRegistry.instance.unregister(sourceId);
/// ```
class NasFileSystemRegistry {
  NasFileSystemRegistry._();

  /// 单例实例
  static final NasFileSystemRegistry instance = NasFileSystemRegistry._();

  /// sourceId -> NasFileSystem 映射
  final _registry = <String, NasFileSystem>{};

  /// 注册 fileSystem
  ///
  /// 在连接建立成功后调用
  void register(String sourceId, NasFileSystem fileSystem) {
    _registry[sourceId] = fileSystem;
    logger.d('NasFileSystemRegistry: 注册 fileSystem for $sourceId');
  }

  /// 注销 fileSystem
  ///
  /// 在连接断开时调用
  void unregister(String sourceId) {
    _registry.remove(sourceId);
    logger.d('NasFileSystemRegistry: 注销 fileSystem for $sourceId');
  }

  /// 获取 fileSystem
  ///
  /// 如果 sourceId 未注册，返回 null
  NasFileSystem? get(String? sourceId) {
    if (sourceId == null) return null;
    return _registry[sourceId];
  }

  /// 检查是否已注册
  bool isRegistered(String sourceId) => _registry.containsKey(sourceId);

  /// 获取所有已注册的 sourceId
  List<String> get registeredSourceIds => _registry.keys.toList();

  /// 清空所有注册
  void clear() {
    _registry.clear();
    logger.d('NasFileSystemRegistry: 已清空所有注册');
  }
}
