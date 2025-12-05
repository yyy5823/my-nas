import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadFromStorage();
  }

  static const _boxName = 'settings';
  static const _key = 'theme_mode';

  Future<void> _loadFromStorage() async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      final value = box.get(_key);
      if (value != null) {
        state = _parseThemeMode(value);
        logger.d('ThemeModeNotifier: 已加载主题模式 => $state');
      }
    } on Exception catch (e) {
      logger.w('ThemeModeNotifier: 加载主题模式失败', e);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _saveToStorage(mode);
  }

  Future<void> _saveToStorage(ThemeMode mode) async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      await box.put(_key, mode.name);
      logger.d('ThemeModeNotifier: 已保存主题模式 => $mode');
    } on Exception catch (e) {
      logger.w('ThemeModeNotifier: 保存主题模式失败', e);
    }
  }

  void toggleTheme() {
    final newMode = switch (state) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    setThemeMode(newMode);
  }

  ThemeMode _parseThemeMode(String value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
