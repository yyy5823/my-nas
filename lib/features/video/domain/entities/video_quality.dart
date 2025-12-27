/// 视频清晰度等级
enum VideoQuality {
  /// 原画（不转码）
  original('原画', null, null),

  /// 4K (3840x2160)
  quality4K('4K', 3840, 2160),

  /// 1080P (1920x1080)
  quality1080p('1080P', 1920, 1080),

  /// 720P (1280x720)
  quality720p('720P', 1280, 720),

  /// 480P (854x480)
  quality480p('480P', 854, 480),

  /// 360P (640x360)
  quality360p('360P', 640, 360);

  const VideoQuality(this.label, this.maxWidth, this.maxHeight);

  /// 显示标签
  final String label;

  /// 最大宽度（像素），null 表示原画
  final int? maxWidth;

  /// 最大高度（像素），null 表示原画
  final int? maxHeight;

  /// 是否为原画
  bool get isOriginal => this == VideoQuality.original;

  /// 估算码率 (bps)
  /// 根据分辨率估算，实际码率取决于视频内容
  int? get estimatedBitrate => switch (this) {
        VideoQuality.original => null,
        VideoQuality.quality4K => 25000000, // 25 Mbps
        VideoQuality.quality1080p => 8000000, // 8 Mbps
        VideoQuality.quality720p => 3500000, // 3.5 Mbps
        VideoQuality.quality480p => 1500000, // 1.5 Mbps
        VideoQuality.quality360p => 800000, // 800 Kbps
      };

  /// 格式化的码率显示
  String? get bitrateLabel {
    final bitrate = estimatedBitrate;
    if (bitrate == null) return null;

    if (bitrate >= 1000000) {
      return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
    }
    return '${(bitrate / 1000).toStringAsFixed(0)} Kbps';
  }

  /// 根据视频分辨率获取可用的清晰度列表
  /// 只返回不超过原视频分辨率的清晰度选项
  static List<VideoQuality> getAvailableQualities({
    required int videoWidth,
    required int videoHeight,
  }) {
    final qualities = <VideoQuality>[VideoQuality.original];

    for (final quality in VideoQuality.values) {
      if (quality == VideoQuality.original) continue;

      // 只添加不超过原视频分辨率的清晰度
      if (quality.maxWidth != null &&
          quality.maxHeight != null &&
          quality.maxWidth! <= videoWidth &&
          quality.maxHeight! <= videoHeight) {
        qualities.add(quality);
      }
    }

    return qualities;
  }

  /// 根据码率建议清晰度
  /// [availableBandwidth] 可用带宽 (bps)
  static VideoQuality suggestQuality({
    required int availableBandwidth,
    required List<VideoQuality> availableQualities,
  }) {
    // 按码率从高到低排序
    final sorted = availableQualities
        .where((q) => q.estimatedBitrate != null)
        .toList()
      ..sort((a, b) => (b.estimatedBitrate ?? 0).compareTo(a.estimatedBitrate ?? 0));

    // 找到第一个码率低于可用带宽的清晰度
    for (final quality in sorted) {
      if (quality.estimatedBitrate != null && quality.estimatedBitrate! <= availableBandwidth) {
        return quality;
      }
    }

    // 如果都不满足，返回最低清晰度
    return sorted.isNotEmpty ? sorted.last : VideoQuality.quality360p;
  }
}

/// 清晰度信息（包含实际码率）
class QualityInfo {
  const QualityInfo({
    required this.quality,
    this.actualBitrate,
    this.isAvailable = true,
    this.unavailableReason,
  });

  /// 清晰度等级
  final VideoQuality quality;

  /// 实际码率（bps），由服务端提供
  final int? actualBitrate;

  /// 是否可用
  final bool isAvailable;

  /// 不可用原因
  final String? unavailableReason;

  /// 格式化的码率显示
  String? get bitrateLabel {
    final bitrate = actualBitrate ?? quality.estimatedBitrate;
    if (bitrate == null) return null;

    if (bitrate >= 1000000) {
      return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
    }
    return '${(bitrate / 1000).toStringAsFixed(0)} Kbps';
  }
}
