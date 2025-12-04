import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 基于流的音频源
/// 用于不支持直接 URL 访问的协议（如 SMB、WebDAV）
class NasStreamAudioSource extends StreamAudioSource {
  NasStreamAudioSource({
    required this.fileSystem,
    required this.path,
    required this.tag,
  });

  final NasFileSystem fileSystem;
  final String path;
  final Object? tag;

  // 缓存文件大小，避免重复获取
  int? _cachedSourceLength;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    try {
      final requestStart = start ?? 0;
      logger.d('NasStreamAudioSource: 请求音频流 path=$path, range=$requestStart-$end');

      // 获取文件大小（使用缓存避免重复请求）
      if (_cachedSourceLength == null) {
        final fileInfo = await fileSystem.getFileInfo(path);
        _cachedSourceLength = fileInfo.size;
        logger.d('NasStreamAudioSource: 文件大小 = $_cachedSourceLength bytes');
      }

      final sourceLength = _cachedSourceLength!;

      // 验证范围请求的有效性
      if (requestStart >= sourceLength) {
        logger.w('NasStreamAudioSource: 请求起始位置超出文件大小: $requestStart >= $sourceLength');
        // 返回空流
        return StreamAudioResponse(
          sourceLength: sourceLength,
          contentLength: 0,
          offset: requestStart,
          stream: Stream.empty(),
          contentType: _getContentType(path),
        );
      }

      // 确保 end 不超过文件大小
      final effectiveEnd = end != null && end <= sourceLength ? end : null;

      // 获取文件流
      final stream = await fileSystem.getFileStream(
        path,
        range: FileRange(
          start: requestStart,
          end: effectiveEnd,
        ),
      );

      // 计算内容长度
      final contentLength = effectiveEnd != null
          ? (effectiveEnd - requestStart)
          : (sourceLength - requestStart);

      logger.d('NasStreamAudioSource: 返回流 offset=$requestStart, contentLength=$contentLength, sourceLength=$sourceLength');

      // 包装流以添加错误处理
      final wrappedStream = stream.handleError((Object error, StackTrace stackTrace) {
        logger.e('NasStreamAudioSource: 流读取错误', error, stackTrace);
      });

      return StreamAudioResponse(
        sourceLength: sourceLength,
        contentLength: contentLength,
        offset: requestStart,
        stream: wrappedStream,
        contentType: _getContentType(path),
      );
    } catch (e, stackTrace) {
      logger.e('NasStreamAudioSource: 请求音频流失败', e, stackTrace);
      rethrow;
    }
  }

  /// 根据文件扩展名获取 MIME 类型
  String _getContentType(String path) {
    final ext = path.toLowerCase().split('.').last;
    return switch (ext) {
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' => 'audio/ogg',
      'opus' => 'audio/opus',
      'wma' => 'audio/x-ms-wma',
      'ape' => 'audio/ape',
      'alac' => 'audio/alac',
      _ => 'audio/mpeg', // 默认
    };
  }
}

