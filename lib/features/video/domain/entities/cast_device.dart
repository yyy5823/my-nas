/// 投屏协议类型
enum CastProtocol {
  /// DLNA/UPnP
  dlna('DLNA'),

  /// Apple AirPlay
  airplay('AirPlay');

  const CastProtocol(this.label);
  final String label;
}

/// 投屏设备实体
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    this.modelName,
    this.manufacturer,
    this.iconUrl,
  });

  /// 唯一标识符
  final String id;

  /// 设备名称
  final String name;

  /// 投屏协议
  final CastProtocol protocol;

  /// 设备地址（IP）
  final String address;

  /// 端口
  final int port;

  /// 设备型号名称
  final String? modelName;

  /// 制造商
  final String? manufacturer;

  /// 设备图标 URL
  final String? iconUrl;

  /// 获取设备的完整地址
  String get fullAddress => '$address:$port';

  /// 获取设备描述
  String get description {
    final parts = <String>[];
    if (manufacturer != null) parts.add(manufacturer!);
    if (modelName != null) parts.add(modelName!);
    if (parts.isEmpty) return protocol.label;
    return parts.join(' · ');
  }

  CastDevice copyWith({
    String? id,
    String? name,
    CastProtocol? protocol,
    String? address,
    int? port,
    String? modelName,
    String? manufacturer,
    String? iconUrl,
  }) =>
      CastDevice(
        id: id ?? this.id,
        name: name ?? this.name,
        protocol: protocol ?? this.protocol,
        address: address ?? this.address,
        port: port ?? this.port,
        modelName: modelName ?? this.modelName,
        manufacturer: manufacturer ?? this.manufacturer,
        iconUrl: iconUrl ?? this.iconUrl,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CastDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CastDevice($name, $protocol, $fullAddress)';
}

/// 投屏播放状态
enum CastPlaybackState {
  /// 空闲
  idle,

  /// 加载中
  loading,

  /// 播放中
  playing,

  /// 暂停
  paused,

  /// 停止
  stopped,

  /// 错误
  error,
}

/// 投屏会话实体
class CastSession {
  CastSession({
    required this.device,
    required this.videoTitle,
    required this.videoPath,
    this.playbackState = CastPlaybackState.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.errorMessage,
  });

  /// 投屏设备
  final CastDevice device;

  /// 视频标题
  final String videoTitle;

  /// 视频路径
  final String videoPath;

  /// 播放状态
  final CastPlaybackState playbackState;

  /// 当前播放位置
  final Duration position;

  /// 视频总时长
  final Duration duration;

  /// 音量 (0.0 - 1.0)
  final double volume;

  /// 错误信息
  final String? errorMessage;

  /// 播放进度 (0.0 - 1.0)
  double get progress => duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0;

  /// 是否正在播放
  bool get isPlaying => playbackState == CastPlaybackState.playing;

  /// 是否暂停
  bool get isPaused => playbackState == CastPlaybackState.paused;

  /// 是否有错误
  bool get hasError => playbackState == CastPlaybackState.error;

  /// 是否正在加载
  bool get isLoading => playbackState == CastPlaybackState.loading;

  CastSession copyWith({
    CastDevice? device,
    String? videoTitle,
    String? videoPath,
    CastPlaybackState? playbackState,
    Duration? position,
    Duration? duration,
    double? volume,
    String? errorMessage,
  }) =>
      CastSession(
        device: device ?? this.device,
        videoTitle: videoTitle ?? this.videoTitle,
        videoPath: videoPath ?? this.videoPath,
        playbackState: playbackState ?? this.playbackState,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        errorMessage: errorMessage,
      );

  @override
  String toString() => 'CastSession(${device.name}, $videoTitle, $playbackState)';
}
