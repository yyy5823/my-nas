import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/video/data/services/audio_track_service.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';

/// 语言类型
enum LanguageType {
  audio,
  subtitle,
  metadata,
}

/// 语言偏好设置
/// 用于配置音频、字幕、元数据的语言显示优先级
class LanguagePreference {
  const LanguagePreference({
    this.audioLanguages = const [LanguageOption.auto],
    this.subtitleLanguages = const [LanguageOption.auto],
    this.metadataLanguages = const [LanguageOption.auto],
  });

  factory LanguagePreference.fromJson(Map<String, dynamic> json) {
    // 向后兼容：支持旧的单选格式
    if (json.containsKey('audioLanguage')) {
      return LanguagePreference(
        audioLanguages: [LanguageOption.fromCode(json['audioLanguage'] as String?)],
        subtitleLanguages: [LanguageOption.fromCode(json['subtitleLanguage'] as String?)],
        metadataLanguages: [LanguageOption.fromCode(json['metadataLanguage'] as String?)],
      );
    }

    return LanguagePreference(
      audioLanguages: _parseLanguageList(json['audioLanguages']),
      subtitleLanguages: _parseLanguageList(json['subtitleLanguages']),
      metadataLanguages: _parseLanguageList(json['metadataLanguages']),
    );
  }

  /// 音频语言优先级列表
  final List<LanguageOption> audioLanguages;

  /// 字幕语言优先级列表
  final List<LanguageOption> subtitleLanguages;

  /// 元数据语言优先级列表
  final List<LanguageOption> metadataLanguages;

  static List<LanguageOption> _parseLanguageList(dynamic value) {
    if (value == null) return [LanguageOption.auto];
    if (value is String) {
      // 格式: "zh-CN,en,ja"
      if (value.isEmpty) return [LanguageOption.auto];
      return value
          .split(',')
          .map(LanguageOption.fromCode)
          .toList();
    }
    return [LanguageOption.auto];
  }

  LanguagePreference copyWith({
    List<LanguageOption>? audioLanguages,
    List<LanguageOption>? subtitleLanguages,
    List<LanguageOption>? metadataLanguages,
  }) =>
      LanguagePreference(
        audioLanguages: audioLanguages ?? this.audioLanguages,
        subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
        metadataLanguages: metadataLanguages ?? this.metadataLanguages,
      );

  /// 获取指定类型的语言列表
  List<LanguageOption> getLanguagesForType(LanguageType type) => switch (type) {
        LanguageType.audio => audioLanguages,
        LanguageType.subtitle => subtitleLanguages,
        LanguageType.metadata => metadataLanguages,
      };

  /// 获取首选语言（优先级最高的）
  LanguageOption getPreferredLanguage(LanguageType type) {
    final languages = getLanguagesForType(type);
    return languages.isNotEmpty ? languages.first : LanguageOption.auto;
  }

  Map<String, dynamic> toJson() => {
        'audioLanguages': audioLanguages.map((e) => e.code).join(','),
        'subtitleLanguages': subtitleLanguages.map((e) => e.code).join(','),
        'metadataLanguages': metadataLanguages.map((e) => e.code).join(','),
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

  /// 获取所有可选语言（排除特殊选项）
  static List<LanguageOption> get selectableLanguages =>
      LanguageOption.values.where((e) => e != LanguageOption.auto).toList();

  /// 获取元数据可选语言（包含原产地语言）
  static List<LanguageOption> get metadataLanguages => LanguageOption.values;

  /// 获取音频/字幕可选语言（不包含原产地语言）
  static List<LanguageOption> get audioSubtitleLanguages =>
      LanguageOption.values.where((e) => e != LanguageOption.original).toList();

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
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载语言偏好失败，使用默认值');
    }
  }

  Map<String, dynamic>? _parseJson(String jsonStr) {
    try {
      // 简单解析 JSON 字符串
      final result = <String, dynamic>{};
      final content = jsonStr.replaceAll('{', '').replaceAll('}', '');
      for (final pair in content.split(',')) {
        // 处理语言列表中的逗号（使用 : 分割 key 和 value）
        final colonIndex = pair.indexOf(':');
        if (colonIndex == -1) continue;

        final key = pair.substring(0, colonIndex).trim().replaceAll('"', '');
        final value = pair.substring(colonIndex + 1).trim().replaceAll('"', '');
        result[key] = value;
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

      // 同步更新相关服务的语言偏好
      TmdbService().setLanguagePreference(state);
      SubtitleService().setLanguagePreference(state);
      AudioTrackService().setLanguagePreference(state);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存语言偏好失败');
    }
  }

  /// 设置音频语言列表
  Future<void> setAudioLanguages(List<LanguageOption> languages) async {
    if (languages.isEmpty) return;
    state = state.copyWith(audioLanguages: languages);
    await _saveToStorage();
  }

  /// 设置字幕语言列表
  Future<void> setSubtitleLanguages(List<LanguageOption> languages) async {
    if (languages.isEmpty) return;
    state = state.copyWith(subtitleLanguages: languages);
    await _saveToStorage();
  }

  /// 设置元数据语言列表
  Future<void> setMetadataLanguages(List<LanguageOption> languages) async {
    if (languages.isEmpty) return;
    state = state.copyWith(metadataLanguages: languages);
    await _saveToStorage();
  }

  /// 设置指定类型的语言列表
  Future<void> setLanguages(LanguageType type, List<LanguageOption> languages) async {
    if (languages.isEmpty) return;
    switch (type) {
      case LanguageType.audio:
        await setAudioLanguages(languages);
      case LanguageType.subtitle:
        await setSubtitleLanguages(languages);
      case LanguageType.metadata:
        await setMetadataLanguages(languages);
    }
  }

  /// 添加语言到指定类型
  Future<void> addLanguage(LanguageType type, LanguageOption language) async {
    final current = state.getLanguagesForType(type);
    if (current.contains(language)) return;

    // 如果添加非自动选项，移除自动
    var newList = [...current];
    if (language != LanguageOption.auto && newList.contains(LanguageOption.auto)) {
      newList.remove(LanguageOption.auto);
    }
    // 如果添加自动，清除其他选项
    if (language == LanguageOption.auto) {
      newList = [LanguageOption.auto];
    } else {
      newList.add(language);
    }

    await setLanguages(type, newList);
  }

  /// 移除语言
  Future<void> removeLanguage(LanguageType type, LanguageOption language) async {
    final current = state.getLanguagesForType(type);
    if (current.length <= 1) return; // 至少保留一个
    if (!current.contains(language)) return;

    final newList = current.where((e) => e != language).toList();
    await setLanguages(type, newList);
  }

  /// 重新排序语言
  Future<void> reorderLanguages(LanguageType type, int oldIndex, int newIndex) async {
    final current = state.getLanguagesForType(type);
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex < 0 || newIndex >= current.length) return;

    final newList = [...current];
    final item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);

    await setLanguages(type, newList);
  }

  /// 重置为默认值
  Future<void> reset() async {
    state = const LanguagePreference();
    await _saveToStorage();
  }

  // ============ 向后兼容的方法 ============

  /// 设置音频语言偏好（向后兼容）
  @Deprecated('Use setAudioLanguages instead')
  Future<void> setAudioLanguage(LanguageOption language) async {
    await setAudioLanguages([language]);
  }

  /// 设置字幕语言偏好（向后兼容）
  @Deprecated('Use setSubtitleLanguages instead')
  Future<void> setSubtitleLanguage(LanguageOption language) async {
    await setSubtitleLanguages([language]);
  }

  /// 设置元数据语言偏好（向后兼容）
  @Deprecated('Use setMetadataLanguages instead')
  Future<void> setMetadataLanguage(LanguageOption language) async {
    await setMetadataLanguages([language]);
  }
}
