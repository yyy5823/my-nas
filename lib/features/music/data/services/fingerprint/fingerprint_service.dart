import 'dart:io';

import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service_desktop.dart';
import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service_mobile.dart';

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
  ///
  /// 自动根据当前平台返回对应实现：
  /// - 桌面端 (Windows/macOS/Linux): 使用 fpcalc 命令行工具
  /// - 移动端 (Android/iOS): 使用原生库通过 MethodChannel 调用
  static FingerprintService? getInstance() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return FingerprintServiceDesktop.instance;
    } else if (Platform.isAndroid || Platform.isIOS) {
      return FingerprintServiceMobile.instance;
    }
    return null;
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
  const FingerprintUnavailableException([super.message = '指纹服务不可用']);
}

/// 指纹生成失败异常
class FingerprintGenerationException extends FingerprintException {
  const FingerprintGenerationException(super.message, {super.cause});
}
