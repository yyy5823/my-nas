import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/quality/quality_monitor_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/transcoding_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';

/// 清晰度设置 Provider
final qualitySettingsProvider = StateProvider<QualitySettings>((ref) => const QualitySettings());

/// 清晰度状态 Provider
final qualityStateProvider = StateNotifierProvider.autoDispose<QualityNotifier, QualityState>(
  QualityNotifier.new,
);

/// 清晰度设置
class QualitySettings {
  const QualitySettings({
    this.defaultQuality = VideoQuality.original,
    this.enableAdaptiveSuggestion = true,
    this.bufferThresholdSeconds = 3,
    this.rememberPerVideo = true,
    this.showUnsupportedHint = true,
  });

  /// 默认清晰度
  final VideoQuality defaultQuality;

  /// 是否启用自适应建议
  final bool enableAdaptiveSuggestion;

  /// 缓冲阈值（秒）
  final int bufferThresholdSeconds;

  /// 记住每个视频的清晰度选择
  final bool rememberPerVideo;

  /// 不支持转码时显示提示
  final bool showUnsupportedHint;

  QualitySettings copyWith({
    VideoQuality? defaultQuality,
    bool? enableAdaptiveSuggestion,
    int? bufferThresholdSeconds,
    bool? rememberPerVideo,
    bool? showUnsupportedHint,
  }) =>
      QualitySettings(
        defaultQuality: defaultQuality ?? this.defaultQuality,
        enableAdaptiveSuggestion: enableAdaptiveSuggestion ?? this.enableAdaptiveSuggestion,
        bufferThresholdSeconds: bufferThresholdSeconds ?? this.bufferThresholdSeconds,
        rememberPerVideo: rememberPerVideo ?? this.rememberPerVideo,
        showUnsupportedHint: showUnsupportedHint ?? this.showUnsupportedHint,
      );
}

/// 清晰度状态
class QualityState {
  const QualityState({
    this.currentQuality = VideoQuality.original,
    this.availableQualities = const [VideoQuality.original],
    this.capability = TranscodingCapability.none,
    this.isLoading = false,
    this.showSuggestionDialog = false,
    this.suggestedQuality,
    this.errorMessage,
    this.videoPath,
  });

  /// 当前清晰度
  final VideoQuality currentQuality;

  /// 可用清晰度列表
  final List<VideoQuality> availableQualities;

  /// 转码能力
  final TranscodingCapability capability;

  /// 是否正在加载/切换中
  final bool isLoading;

  /// 是否显示切换建议弹窗
  final bool showSuggestionDialog;

  /// 建议的清晰度
  final VideoQuality? suggestedQuality;

  /// 错误信息
  final String? errorMessage;

  /// 当前视频路径
  final String? videoPath;

  /// 是否支持清晰度切换
  bool get canSwitchQuality => capability != TranscodingCapability.none;

  /// 是否使用服务端转码
  bool get isServerSideTranscoding => capability == TranscodingCapability.serverSide;

  /// 是否使用客户端转码
  bool get isClientSideTranscoding => capability == TranscodingCapability.clientSide;

  QualityState copyWith({
    VideoQuality? currentQuality,
    List<VideoQuality>? availableQualities,
    TranscodingCapability? capability,
    bool? isLoading,
    bool? showSuggestionDialog,
    VideoQuality? suggestedQuality,
    String? errorMessage,
    String? videoPath,
  }) =>
      QualityState(
        currentQuality: currentQuality ?? this.currentQuality,
        availableQualities: availableQualities ?? this.availableQualities,
        capability: capability ?? this.capability,
        isLoading: isLoading ?? this.isLoading,
        showSuggestionDialog: showSuggestionDialog ?? this.showSuggestionDialog,
        suggestedQuality: suggestedQuality ?? this.suggestedQuality,
        errorMessage: errorMessage,
        videoPath: videoPath ?? this.videoPath,
      );
}

/// 清晰度管理 Notifier
class QualityNotifier extends StateNotifier<QualityState> {
  QualityNotifier(this._ref) : super(const QualityState()) {
    _capabilityService = TranscodingCapabilityService();
    _monitorService = QualityMonitorService(
      bufferThresholdSeconds: _ref.read(qualitySettingsProvider).bufferThresholdSeconds,
    );

    // 设置监控回调
    _monitorService.onQualitySuggestion = _onQualitySuggestion;
    _monitorService.onQualityUnsupported = _onQualityUnsupported;
  }

  final Ref _ref;
  late final TranscodingCapabilityService _capabilityService;
  late final QualityMonitorService _monitorService;

  /// 初始化（设置源类型和播放器）
  void init({
    required SourceType sourceType,
    required Player player,
    required String videoPath,
    int? videoWidth,
    int? videoHeight,
  }) {
    // 检测转码能力
    final capability = _capabilityService.getCapability(sourceType);

    // 计算可用清晰度
    List<VideoQuality> availableQualities;
    if (capability == TranscodingCapability.none) {
      availableQualities = [VideoQuality.original];
    } else if (videoWidth != null && videoHeight != null) {
      availableQualities = VideoQuality.getAvailableQualities(
        videoWidth: videoWidth,
        videoHeight: videoHeight,
      );
    } else {
      // 没有视频尺寸信息，提供全部选项
      availableQualities = VideoQuality.values.toList();
    }

    // 获取默认清晰度
    final settings = _ref.read(qualitySettingsProvider);
    var defaultQuality = settings.defaultQuality;

    // 如果默认清晰度不在可用列表中，使用原画
    if (!availableQualities.contains(defaultQuality)) {
      defaultQuality = VideoQuality.original;
    }

    state = state.copyWith(
      currentQuality: defaultQuality,
      availableQualities: availableQualities,
      capability: capability,
      videoPath: videoPath,
    );

    // 初始化质量监控（仅在启用自适应建议时）
    if (settings.enableAdaptiveSuggestion && capability != TranscodingCapability.none) {
      _monitorService.init(
        player: player,
        availableQualities: availableQualities,
        currentQuality: defaultQuality,
      );
    }

    logger.i('清晰度初始化: 能力=$capability, 当前=${defaultQuality.label}, '
        '可用=${availableQualities.map((q) => q.label).join(",")}');
  }

  /// 切换清晰度
  Future<void> switchQuality(VideoQuality quality) async {
    if (!state.availableQualities.contains(quality)) {
      logger.w('清晰度 ${quality.label} 不可用');
      return;
    }

    if (state.currentQuality == quality) {
      logger.i('已经是 ${quality.label}');
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      // TODO: 实际切换逻辑（Phase 4 实现）
      // 对于服务端转码：请求新的转码流URL
      // 对于客户端转码：启动本地转码
      await Future<void>.delayed(const Duration(milliseconds: 500)); // 模拟切换

      state = state.copyWith(
        currentQuality: quality,
        isLoading: false,
        showSuggestionDialog: false,
        suggestedQuality: null,
      );

      // 更新监控服务
      _monitorService.setCurrentQuality(quality);

      logger.i('清晰度已切换到 ${quality.label}');
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '切换清晰度失败: $e',
      );
      logger.w('切换清晰度失败: $e');
    }
  }

  /// 处理质量建议回调
  void _onQualitySuggestion(VideoQuality current, VideoQuality suggested) {
    state = state.copyWith(
      showSuggestionDialog: true,
      suggestedQuality: suggested,
    );
  }

  /// 处理不支持转码回调
  void _onQualityUnsupported() {
    final settings = _ref.read(qualitySettingsProvider);
    if (settings.showUnsupportedHint) {
      state = state.copyWith(
        errorMessage: '当前源不支持清晰度切换',
      );
    }
  }

  /// 接受建议切换
  Future<void> acceptSuggestion() async {
    final suggested = state.suggestedQuality;
    if (suggested == null) return;

    await switchQuality(suggested);
  }

  /// 拒绝建议切换
  void rejectSuggestion({bool dontAskAgain = false}) {
    final suggested = state.suggestedQuality;
    if (suggested != null) {
      _monitorService.rejectSuggestion(suggested);
    }

    if (dontAskAgain) {
      _monitorService.optOut();
    }

    state = state.copyWith(
      showSuggestionDialog: false,
      suggestedQuality: null,
    );
  }

  /// 清除错误信息
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  /// 隐藏建议弹窗
  void hideSuggestionDialog() {
    state = state.copyWith(
      showSuggestionDialog: false,
    );
  }

  @override
  void dispose() {
    _monitorService.dispose();
    super.dispose();
  }
}
