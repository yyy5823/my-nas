import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 语言偏好设置
/// 用于配置音频、字幕、元数据的语言显示
class LanguagePreference {
  const LanguagePreference({
    this.audioLanguage = LanguageOption.auto,
    this.subtitleLanguage = LanguageOption.auto,
    this.metadataLanguage = LanguageOption.auto,
  });

  factory LanguagePreference.fromJson(Map<String, dynamic> json) => LanguagePreference(
      audioLanguage: LanguageOption.fromCode(json['audioLanguage'] as String?),
      subtitleLanguage: LanguageOption.fromCode(json['subtitleLanguage'] as String?),
      metadataLanguage: LanguageOption.fromCode(json['metadataLanguage'] as String?),
    );

  /// 音频语言偏好
  final LanguageOption audioLanguage;

  /// 字幕语言偏好
  final LanguageOption subtitleLanguage;

  /// 元数据语言偏好（影片标题、简介等）
  final LanguageOption metadataLanguage;

  LanguagePreference copyWith({
    LanguageOption? audioLanguage,
    LanguageOption? subtitleLanguage,
    LanguageOption? metadataLanguage,
  }) =>
      LanguagePreference(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        metadataLanguage: metadataLanguage ?? this.metadataLanguage,
      );

  Map<String, dynamic> toJson() => {
        'audioLanguage': audioLanguage.code,
        'subtitleLanguage': subtitleLanguage.code,
        'metadataLanguage': metadataLanguage.code,
      };
}

/// 语言选项枚举
enum LanguageOption {
  /// 自动（跟随系统语言）
  auto('auto', '自动', '跟随系统语言'),

  /// 原产地语言（影片原始语言）
  original('original', '原产地语言', '使用影片原始语言'),

  /// 中文（简体）
  zhCN('zh-CN', '简体中文', '中文（简体）'),

  /// 中文（繁体）
  zhTW('zh-TW', '繁体中文', '中文（繁体）'),

  /// 英语
  en('en', '英语', 'English'),

  /// 日语
  ja('ja', '日语', '日本語'),

  /// 韩语
  ko('ko', '韩语', '한국어'),

  /// 法语
  fr('fr', '法语', 'Français'),

  /// 德语
  de('de', '德语', 'Deutsch'),

  /// 西班牙语
  es('es', '西班牙语', 'Español'),

  /// 葡萄牙语
  pt('pt', '葡萄牙语', 'Português'),

  /// 俄语
  ru('ru', '俄语', 'Русский'),

  /// 意大利语
  it('it', '意大利语', 'Italiano'),

  /// 泰语
  th('th', '泰语', 'ไทย'),

  /// 越南语
  vi('vi', '越南语', 'Tiếng Việt');

  const LanguageOption(this.code, this.displayName, this.nativeName);

  /// 语言代码
  final String code;

  /// 中文显示名称
  final String displayName;

  /// 原生名称
  final String nativeName;

  /// 从代码解析语言选项
  static LanguageOption fromCode(String? code) {
    if (code == null || code.isEmpty) return LanguageOption.auto;
    return LanguageOption.values.firstWhere(
      (e) => e.code == code,
      orElse: () => LanguageOption.auto,
    );
  }

  /// 获取实际的 ISO 语言代码（用于 TMDB API 等）
  String getActualCode(Locale systemLocale) {
    if (this == LanguageOption.auto) {
      // 根据系统语言返回对应代码
      final langCode = systemLocale.languageCode;
      final countryCode = systemLocale.countryCode;

      if (langCode == 'zh') {
        // 中文需要区分简繁体
        if (countryCode == 'TW' || countryCode == 'HK') {
          return 'zh-TW';
        }
        return 'zh-CN';
      }
      return langCode;
    }

    if (this == LanguageOption.original) {
      // 原产地语言需要从影片元数据获取，返回空表示使用原始
      return '';
    }

    return code;
  }
}

/// 语言偏好设置 Provider
final languagePreferenceProvider =
    StateNotifierProvider<LanguagePreferenceNotifier, LanguagePreference>(
  (ref) => LanguagePreferenceNotifier(),
);

class LanguagePreferenceNotifier extends StateNotifier<LanguagePreference> {
  LanguagePreferenceNotifier() : super(const LanguagePreference()) {
    _loadFromStorage();
  }

  static const _boxName = 'settings';
  static const _key = 'language_preference';

  Future<void> _loadFromStorage() async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      final jsonStr = box.get(_key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final json = _parseJson(jsonStr);
        if (json != null) {
          state = LanguagePreference.fromJson(json);
          logger.d('LanguagePreferenceNotifier: 已加载语言偏好 => $state');
        }
      }
    } on Exception catch (e) {
      logger.w('LanguagePreferenceNotifier: 加载语言偏好失败', e);
    }
  }

  Map<String, dynamic>? _parseJson(String jsonStr) {
    try {
      // 简单解析 JSON 字符串
      final result = <String, dynamic>{};
      final content = jsonStr.replaceAll('{', '').replaceAll('}', '');
      for (final pair in content.split(',')) {
        final kv = pair.split(':');
        if (kv.length == 2) {
          final key = kv[0].trim().replaceAll('"', '');
          final value = kv[1].trim().replaceAll('"', '');
          result[key] = value;
        }
      }
      return result.isNotEmpty ? result : null;
    } on Exception catch (_) {
      return null;
    }
  }

  String _toJsonString(Map<String, dynamic> json) {
    final pairs = json.entries.map((e) => '"${e.key}":"${e.value}"');
    return '{${pairs.join(',')}}';
  }

  Future<void> _saveToStorage() async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      final jsonStr = _toJsonString(state.toJson());
      await box.put(_key, jsonStr);
      logger.d('LanguagePreferenceNotifier: 已保存语言偏好');
    } on Exception catch (e) {
      logger.w('LanguagePreferenceNotifier: 保存语言偏好失败', e);
    }
  }

  /// 设置音频语言偏好
  Future<void> setAudioLanguage(LanguageOption language) async {
    state = state.copyWith(audioLanguage: language);
    await _saveToStorage();
  }

  /// 设置字幕语言偏好
  Future<void> setSubtitleLanguage(LanguageOption language) async {
    state = state.copyWith(subtitleLanguage: language);
    await _saveToStorage();
  }

  /// 设置元数据语言偏好
  Future<void> setMetadataLanguage(LanguageOption language) async {
    state = state.copyWith(metadataLanguage: language);
    await _saveToStorage();
  }

  /// 重置为默认值
  Future<void> reset() async {
    state = const LanguagePreference();
    await _saveToStorage();
  }
}
