import 'package:hive_ce_flutter/hive_flutter.dart';

/// Hive 工具类
/// 提供统一的 box 访问方法，避免类型冲突
class HiveUtils {
  HiveUtils._();

  /// 获取 settings box（统一使用 `Box<dynamic>`）
  /// 如果 box 已打开则直接返回，否则打开它
  static Future<Box<dynamic>> getSettingsBox() async {
    const boxName = 'settings';
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<dynamic>(boxName);
    }
    return Hive.openBox<dynamic>(boxName);
  }

  /// 同步获取 settings box（仅在确定 box 已打开时使用）
  static Box<dynamic> get settingsBox => Hive.box<dynamic>('settings');
}
