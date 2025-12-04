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
      logger.i('NasStreamAudioSource: ===== 请求音频流 =====');
      logger.i('NasStreamAudioSource: path=$path');
      logger.i('NasStreamAudioSource: range=$requestStart-$end');

      // 获取文件大小（使用缓存避免重复请求）
      if (_cachedSourceLength == null) {
        logger.d('NasStreamAudioSource: 获取文件信息...');
        final fileInfo = await fileSystem.getFileInfo(path);
        _cachedSourceLength = fileInfo.size;
        logger.i('NasStreamAudioSource: 文件大小 = $_cachedSourceLength bytes');
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

      // 确保 end 不超过文件的最后一个字节索引
      // 文件大小为 N 字节，最后一个字节的索引是 N-1
      final effectiveEnd = end != null && end < sourceLength ? end : null;

      logger.d('NasStreamAudioSource: 获取文件流 range=$requestStart-$effectiveEnd...');

      // 获取文件流
      // 注意：HTTP Range 是闭区间 [start, end]，所以 bytes=0-2 返回 3 字节
      final stream = await fileSystem.getFileStream(
        path,
        range: FileRange(
          start: requestStart,
          end: effectiveEnd,
        ),
      );

      // 计算内容长度
      // HTTP Range 是闭区间，所以 contentLength = end - start + 1
      final contentLength = effectiveEnd != null
          ? (effectiveEnd - requestStart + 1)
          : (sourceLength - requestStart);

      logger.i('NasStreamAudioSource: 返回 StreamAudioResponse');
      logger.i('NasStreamAudioSource: offset=$requestStart, contentLength=$contentLength, sourceLength=$sourceLength');
      logger.i('NasStreamAudioSource: contentType=${_getContentType(path)}');

      // 包装流以添加错误处理和日志
      int bytesReceived = 0;
      final wrappedStream = stream.map((chunk) {
        bytesReceived += chunk.length;
        if (bytesReceived % (1024 * 1024) < chunk.length) {
          // 每 1MB 打印一次日志
          logger.d('NasStreamAudioSource: 已接收 ${(bytesReceived / 1024 / 1024).toStringAsFixed(1)} MB');
        }
        return chunk;
      }).handleError((Object error, StackTrace stackTrace) {
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

