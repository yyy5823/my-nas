import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/video_category_settings_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';

/// 视频分类设置 Provider
final videoCategorySettingsProvider =
    StateNotifierProvider<VideoCategorySettingsNotifier, VideoCategorySettings>(
  (ref) => VideoCategorySettingsNotifier(),
);

/// 视频分类设置 Notifier
class VideoCategorySettingsNotifier extends StateNotifier<VideoCategorySettings> {
  VideoCategorySettingsNotifier() : super(VideoCategorySettings.defaults()) {
    _init();
  }

  final _service = VideoCategorySettingsService();
  StreamSubscription<VideoCategorySettings>? _subscription;

  Future<void> _init() async {
    await _service.init();
    state = _service.settings;

    // 监听设置变化
    _subscription = _service.settingsStream.listen((settings) {
      state = settings;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// 切换分类可见性
  Future<void> toggleVisibility(String uniqueKey) async {
    await _service.toggleVisibility(uniqueKey);
  }

  /// 重新排序分类
  Future<void> reorder(int oldIndex, int newIndex) async {
    // 处理 Flutter ReorderableListView 的索引行为
    var actualNewIndex = newIndex;
    if (newIndex > oldIndex) {
      actualNewIndex -= 1;
    }
    await _service.reorder(oldIndex, actualNewIndex);
  }

  /// 添加类型分类
  Future<void> addGenre(String genre) async {
    await _service.addGenre(genre);
  }

  /// 移除类型分类
  Future<void> removeGenre(String genre) async {
    await _service.removeGenre(genre);
  }

  /// 重置为默认
  Future<void> resetToDefaults() async {
    await _service.resetToDefaults();
  }
}
