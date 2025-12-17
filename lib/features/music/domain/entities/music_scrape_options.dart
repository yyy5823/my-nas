/// 音乐刮削选项
class MusicScrapeOptions {
  const MusicScrapeOptions({
    this.downloadCover = true,
    this.downloadLyrics = true,
    this.updateMetadata = true,
    this.overwriteExisting = false,
    this.preferredLanguage = 'zh-CN',
    this.useFingerprint = true,
    this.saveCoverToFolder = true,
    this.coverFileName = 'folder',
  });

  factory MusicScrapeOptions.fromJson(Map<String, dynamic> json) =>
      MusicScrapeOptions(
        downloadCover: json['downloadCover'] as bool? ?? true,
        downloadLyrics: json['downloadLyrics'] as bool? ?? true,
        updateMetadata: json['updateMetadata'] as bool? ?? true,
        overwriteExisting: json['overwriteExisting'] as bool? ?? false,
        preferredLanguage: json['preferredLanguage'] as String? ?? 'zh-CN',
        useFingerprint: json['useFingerprint'] as bool? ?? true,
        saveCoverToFolder: json['saveCoverToFolder'] as bool? ?? true,
        coverFileName: json['coverFileName'] as String? ?? 'folder',
      );

  /// 是否下载封面
  final bool downloadCover;

  /// 是否下载歌词
  final bool downloadLyrics;

  /// 是否更新本地数据库元数据
  final bool updateMetadata;

  /// 是否覆盖已有数据
  final bool overwriteExisting;

  /// 首选语言（zh-CN, en, ja 等）
  final String preferredLanguage;

  /// 是否使用声纹识别
  final bool useFingerprint;

  /// 是否保存封面到文件夹（folder.jpg）
  /// false 则保存为 {filename}-cover.jpg
  final bool saveCoverToFolder;

  /// 封面文件名（不含扩展名）
  /// 默认为 'folder'，会保存为 folder.jpg
  final String coverFileName;

  MusicScrapeOptions copyWith({
    bool? downloadCover,
    bool? downloadLyrics,
    bool? updateMetadata,
    bool? overwriteExisting,
    String? preferredLanguage,
    bool? useFingerprint,
    bool? saveCoverToFolder,
    String? coverFileName,
  }) =>
      MusicScrapeOptions(
        downloadCover: downloadCover ?? this.downloadCover,
        downloadLyrics: downloadLyrics ?? this.downloadLyrics,
        updateMetadata: updateMetadata ?? this.updateMetadata,
        overwriteExisting: overwriteExisting ?? this.overwriteExisting,
        preferredLanguage: preferredLanguage ?? this.preferredLanguage,
        useFingerprint: useFingerprint ?? this.useFingerprint,
        saveCoverToFolder: saveCoverToFolder ?? this.saveCoverToFolder,
        coverFileName: coverFileName ?? this.coverFileName,
      );

  Map<String, dynamic> toJson() => {
        'downloadCover': downloadCover,
        'downloadLyrics': downloadLyrics,
        'updateMetadata': updateMetadata,
        'overwriteExisting': overwriteExisting,
        'preferredLanguage': preferredLanguage,
        'useFingerprint': useFingerprint,
        'saveCoverToFolder': saveCoverToFolder,
        'coverFileName': coverFileName,
      };
}

/// 刮削任务状态
enum MusicScrapeStatus {
  idle('空闲'),
  searching('搜索中'),
  fetchingDetail('获取详情'),
  downloadingCover('下载封面'),
  downloadingLyrics('下载歌词'),
  fingerprinting('识别声纹'),
  saving('保存中'),
  completed('已完成'),
  failed('失败');

  const MusicScrapeStatus(this.displayName);
  final String displayName;

  bool get isWorking => [
        MusicScrapeStatus.searching,
        MusicScrapeStatus.fetchingDetail,
        MusicScrapeStatus.downloadingCover,
        MusicScrapeStatus.downloadingLyrics,
        MusicScrapeStatus.fingerprinting,
        MusicScrapeStatus.saving,
      ].contains(this);
}

/// 刮削任务进度
class MusicScrapeProgress {
  const MusicScrapeProgress({
    this.status = MusicScrapeStatus.idle,
    this.message,
    this.progress = 0.0,
    this.currentStep = 0,
    this.totalSteps = 0,
  });

  /// 当前状态
  final MusicScrapeStatus status;

  /// 状态消息
  final String? message;

  /// 进度（0-1）
  final double progress;

  /// 当前步骤
  final int currentStep;

  /// 总步骤数
  final int totalSteps;

  /// 进度百分比文本
  String get progressPercent => '${(progress * 100).toStringAsFixed(0)}%';

  /// 步骤文本
  String get stepText =>
      totalSteps > 0 ? '$currentStep/$totalSteps' : '';

  MusicScrapeProgress copyWith({
    MusicScrapeStatus? status,
    String? message,
    double? progress,
    int? currentStep,
    int? totalSteps,
  }) =>
      MusicScrapeProgress(
        status: status ?? this.status,
        message: message ?? this.message,
        progress: progress ?? this.progress,
        currentStep: currentStep ?? this.currentStep,
        totalSteps: totalSteps ?? this.totalSteps,
      );
}
