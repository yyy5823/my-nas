import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 笔记布局偏好设置服务
/// 用于持久化保存用户的笔记界面布局设置
class NoteLayoutService {
  NoteLayoutService._();

  static NoteLayoutService? _instance;
  static NoteLayoutService get instance => _instance ??= NoteLayoutService._();

  static const String _boxName = 'note_layout_prefs';
  static const String _keySidebarCollapsed = 'sidebar_collapsed';
  static const String _keySidebarWidth = 'sidebar_width';

  Box<dynamic>? _box;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
      logger.i('NoteLayoutService: 初始化完成');
    } on Exception catch (e) {
      logger.e('NoteLayoutService: 初始化失败', e);
      // 尝试删除并重建
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName);
    }
  }

  /// 获取侧边栏是否收起
  bool get isSidebarCollapsed => _box?.get(_keySidebarCollapsed, defaultValue: false) as bool? ?? false;

  /// 设置侧边栏是否收起
  Future<void> setSidebarCollapsed(bool collapsed) async {
    await _box?.put(_keySidebarCollapsed, collapsed);
  }

  /// 获取侧边栏宽度
  double get sidebarWidth => (_box?.get(_keySidebarWidth, defaultValue: 280.0) as num?)?.toDouble() ?? 280.0;

  /// 设置侧边栏宽度
  Future<void> setSidebarWidth(double width) async {
    await _box?.put(_keySidebarWidth, width);
  }
}
