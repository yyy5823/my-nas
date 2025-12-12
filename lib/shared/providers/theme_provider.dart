import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';

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
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载主题模式失败，使用默认值');
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
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存主题模式失败');
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
