/// 歌词行数据
class LyricLineData {
  const LyricLineData({
    required this.text,
    this.translation,
    required this.startTime,
    this.endTime,
  });

  /// 原文歌词
  final String text;

  /// 翻译歌词（可选）
  final String? translation;

  /// 开始时间
  final Duration startTime;

  /// 结束时间（下一行开始时间）
  final Duration? endTime;

  bool get hasTranslation => translation != null && translation!.isNotEmpty;
}
