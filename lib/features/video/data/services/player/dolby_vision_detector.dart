import 'dart:io';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// 杜比视界检测工具
///
/// 用于检测视频是否为杜比视界格式，以决定是否使用原生 AVPlayer
class DolbyVisionDetector {
  DolbyVisionDetector._();

  /// 杜比视界文件名匹配模式
  ///
  /// 支持以下格式：
  /// - Dolby Vision, Dolby-Vision, Dolby_Vision
  /// - DV, DoVi
  /// - DV HDR (杜比视界+HDR混合)
  static final _dolbyVisionPattern = RegExp(
    r'(Dolby[\s._-]*Vision|DoVi|\.DV\.|[\.\s_-]DV[\.\s_-]|DV[\s_-]?HDR)',
    caseSensitive: false,
  );

  /// 检查是否应该使用原生播放器
  ///
  /// 只在以下条件同时满足时返回 true：
  /// 1. 当前平台是 iOS 或 macOS
  /// 2. 视频被检测为杜比视界格式
  ///
  /// [video] 视频项目
  /// [metadata] 视频元数据（可选，如果有则优先使用元数据中的 HDR 信息）
  static bool shouldUseNativePlayer({
    required VideoItem video,
    VideoMetadata? metadata,
  }) {
    // 只在 Apple 平台上使用原生播放器
    if (!Platform.isIOS && !Platform.isMacOS) {
      return false;
    }

    final isDV = isDolbyVision(video: video, metadata: metadata);

    if (isDV) {
      logger.i('DolbyVisionDetector: 检测到杜比视界内容，将使用原生 AVPlayer');
    }

    return isDV;
  }

  /// 检查视频是否为杜比视界格式
  ///
  /// 检测优先级：
  /// 1. 从 VideoMetadata.hdrFormat 检测
  /// 2. 从 VideoFileNameParser 解析的文件名信息检测
  /// 3. 直接从文件名正则匹配
  static bool isDolbyVision({
    required VideoItem video,
    VideoMetadata? metadata,
  }) {
    // 1. 优先从元数据检测
    if (metadata != null) {
      final hdrFormat = metadata.hdrFormat;
      if (hdrFormat != null && _isDolbyVisionFormat(hdrFormat)) {
        logger.d('DolbyVisionDetector: 从元数据检测到杜比视界 (hdrFormat: $hdrFormat)');
        return true;
      }
    }

    // 2. 使用 VideoFileNameParser 解析
    final fileInfo = VideoFileNameParser.parse(video.name);
    if (fileInfo.isDolbyVision) {
      logger.d('DolbyVisionDetector: 从 VideoFileNameParser 检测到杜比视界');
      return true;
    }

    // 3. 直接从文件名正则匹配（作为后备方案）
    if (_dolbyVisionPattern.hasMatch(video.name)) {
      logger.d('DolbyVisionDetector: 从文件名正则匹配检测到杜比视界');
      return true;
    }

    // 4. 从完整路径检测（某些情况下信息在目录名中）
    if (_dolbyVisionPattern.hasMatch(video.path)) {
      logger.d('DolbyVisionDetector: 从路径正则匹配检测到杜比视界');
      return true;
    }

    return false;
  }

  /// 检查 HDR 格式字符串是否表示杜比视界
  static bool _isDolbyVisionFormat(String hdrFormat) {
    final upper = hdrFormat.toUpperCase();
    return upper.contains('DOLBY') ||
        upper == 'DV' ||
        upper == 'DOVI' ||
        upper.contains('DOLBY VISION');
  }

  /// 获取杜比视界 Profile 信息（如果可以从文件名检测）
  ///
  /// 返回值示例：
  /// - 'Profile 5' (单层，兼容性最好)
  /// - 'Profile 7' (双层，需要特殊支持)
  /// - 'Profile 8' (双层 + HDR10 兼容层)
  /// - null (无法检测)
  ///
  /// 注意：Profile 5 和 Profile 8 在原生 AVPlayer 上支持较好
  static String? detectDolbyVisionProfile(String fileName) {
    // Profile 5: .dv.p5. 或 DV.P5
    if (RegExp(r'[\.\s_-]DV[\.\s_-]?P5[\.\s_-]', caseSensitive: false)
        .hasMatch(fileName)) {
      return 'Profile 5';
    }

    // Profile 7: .dv.p7. 或 DV.P7
    if (RegExp(r'[\.\s_-]DV[\.\s_-]?P7[\.\s_-]', caseSensitive: false)
        .hasMatch(fileName)) {
      return 'Profile 7';
    }

    // Profile 8: .dv.p8. 或 DV.P8 或 DV HDR (通常是 P8)
    if (RegExp(r'[\.\s_-]DV[\.\s_-]?P8[\.\s_-]|DV[\s_-]?HDR',
            caseSensitive: false)
        .hasMatch(fileName)) {
      return 'Profile 8';
    }

    return null;
  }

  /// 检查当前平台是否支持原生杜比视界播放
  static bool get isPlatformSupported => Platform.isIOS || Platform.isMacOS;
}
