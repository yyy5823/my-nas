import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';

/// 视频本地化工具
///
/// 提供便捷的方法来根据用户语言偏好获取本地化的标题和简介
class VideoLocalization {
  VideoLocalization._();

  /// 获取默认的语言代码列表
  static List<String> get defaultLanguageCodes => const ['zh-CN', 'en'];

  /// 根据语言偏好获取视频标题
  ///
  /// [metadata] 视频元数据
  /// [preference] 用户语言偏好设置
  /// [systemLocale] 系统语言环境
  static String getTitle(
    VideoMetadata metadata, {
    LanguagePreference? preference,
    Locale? systemLocale,
  }) {
    final codes = preference?.getMetadataLanguageCodes(
          systemLocale ?? const Locale('zh', 'CN'),
        ) ??
        defaultLanguageCodes;
    return metadata.getLocalizedTitle(codes);
  }

  /// 根据语言偏好获取视频简介
  ///
  /// [metadata] 视频元数据
  /// [preference] 用户语言偏好设置
  /// [systemLocale] 系统语言环境
  static String? getOverview(
    VideoMetadata metadata, {
    LanguagePreference? preference,
    Locale? systemLocale,
  }) {
    final codes = preference?.getMetadataLanguageCodes(
          systemLocale ?? const Locale('zh', 'CN'),
        ) ??
        defaultLanguageCodes;
    return metadata.getLocalizedOverview(codes);
  }
}

/// VideoMetadata 扩展：便于获取本地化标题
extension VideoMetadataLocalizationX on VideoMetadata {
  /// 根据用户偏好获取本地化标题
  ///
  /// 使用示例:
  /// ```dart
  /// final pref = ref.watch(languagePreferenceProvider);
  /// final title = metadata.localizedTitle(pref);
  /// ```
  String localizedTitle(LanguagePreference preference, {Locale? systemLocale}) =>
      VideoLocalization.getTitle(
        this,
        preference: preference,
        systemLocale: systemLocale,
      );

  /// 根据用户偏好获取本地化简介
  String? localizedOverview(LanguagePreference preference, {Locale? systemLocale}) =>
      VideoLocalization.getOverview(
        this,
        preference: preference,
        systemLocale: systemLocale,
      );
}

/// Riverpod Provider：提供当前系统语言环境
final systemLocaleProvider = Provider<Locale>((ref) {
  // 使用 PlatformDispatcher 获取系统语言
  final locale = PlatformDispatcher.instance.locale;
  return locale;
});

/// Riverpod Provider：提供当前元数据语言代码列表
final metadataLanguageCodesProvider = Provider<List<String>>((ref) {
  final preference = ref.watch(languagePreferenceProvider);
  final locale = ref.watch(systemLocaleProvider);
  return preference.getMetadataLanguageCodes(locale);
});

/// 便捷的标题获取 Provider
///
/// 使用示例:
/// ```dart
/// Widget build(BuildContext context, WidgetRef ref) {
///   final titleGetter = ref.watch(videoTitleGetterProvider);
///   return Text(titleGetter(metadata));
/// }
/// ```
final videoTitleGetterProvider = Provider<String Function(VideoMetadata)>((ref) {
  final codes = ref.watch(metadataLanguageCodesProvider);
  return (metadata) => metadata.getLocalizedTitle(codes);
});

/// 便捷的简介获取 Provider
final videoOverviewGetterProvider = Provider<String? Function(VideoMetadata)>((ref) {
  final codes = ref.watch(metadataLanguageCodesProvider);
  return (metadata) => metadata.getLocalizedOverview(codes);
});
