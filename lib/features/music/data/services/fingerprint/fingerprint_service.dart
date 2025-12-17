import 'dart:io';

/// 音频指纹服务接口
///
/// 用于生成音频指纹（使用 Chromaprint 算法）
abstract class FingerprintService {
  /// 是否可用（检查原生库是否加载成功）
  bool get isAvailable;

  /// 从文件生成指纹
  ///
  /// [filePath] 音频文件路径
  /// [maxDuration] 最大分析时长（秒），默认 120 秒
  ///
  /// 返回 [FingerprintData] 包含指纹字符串和时长
  Future<FingerprintData> generateFingerprint(
    String filePath, {
    int maxDuration = 120,
  });

  /// 从音频流生成指纹
  ///
  /// [audioStream] 原始 PCM 音频数据流
  /// [sampleRate] 采样率（Hz）
  /// [channels] 声道数
  ///
  /// 返回 [FingerprintData] 包含指纹字符串和时长
  Future<FingerprintData> generateFingerprintFromStream(
    Stream<List<int>> audioStream, {
    required int sampleRate,
    required int channels,
  });

  /// 释放资源
  void dispose();

  /// 获取平台特定的服务实例
  static FingerprintService? getInstance() {
    // 根据平台返回对应实现
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return _getDesktopInstance();
    } else if (Platform.isAndroid || Platform.isIOS) {
      return _getMobileInstance();
    }
    return null;
  }

  static FingerprintService? _desktopInstance;
  static FingerprintService? _mobileInstance;

  static FingerprintService? _getDesktopInstance() {
    // 延迟初始化，在首次调用时创建实例
    // 实际实现将在 fingerprint_service_desktop.dart 中
    return _desktopInstance;
  }

  static FingerprintService? _getMobileInstance() {
    // 延迟初始化，在首次调用时创建实例
    // 实际实现将在 fingerprint_service_mobile.dart 中
    return _mobileInstance;
  }

  /// 注册桌面端实现
  static void registerDesktopInstance(FingerprintService instance) {
    _desktopInstance = instance;
  }

  /// 注册移动端实现
  static void registerMobileInstance(FingerprintService instance) {
    _mobileInstance = instance;
  }
}

/// 指纹数据
class FingerprintData {
  const FingerprintData({
    required this.fingerprint,
    required this.duration,
  });

  /// 指纹字符串（Base64 编码的压缩指纹）
  final String fingerprint;

  /// 音频时长（秒）
  final int duration;

  @override
  String toString() => 'FingerprintData(duration: ${duration}s, fingerprint: ${fingerprint.substring(0, 20)}...)';
}

/// 指纹服务异常
class FingerprintException implements Exception {
  const FingerprintException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'FingerprintException: $message${cause != null ? ' ($cause)' : ''}';
}

/// 指纹服务不可用异常
class FingerprintUnavailableException extends FingerprintException {
  const FingerprintUnavailableException([String message = '指纹服务不可用'])
      : super(message);
}

/// 指纹生成失败异常
class FingerprintGenerationException extends FingerprintException {
  const FingerprintGenerationException(super.message, {super.cause});
}
