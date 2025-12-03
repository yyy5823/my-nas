import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 基于流的音频源
/// 用于不支持直接 URL 访问的协议（如 SMB）
class NasStreamAudioSource extends StreamAudioSource {
  NasStreamAudioSource({
    required this.fileSystem,
    required this.path,
    required this.tag,
  });

  final NasFileSystem fileSystem;
  final String path;
  final Object? tag;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    try {
      logger.d('NasStreamAudioSource: 请求音频流 path=$path, range=$start-$end');

      // 获取文件信息以确定总长度
      final fileInfo = await fileSystem.getFileInfo(path);
      final sourceLength = fileInfo.size;

      logger.d('NasStreamAudioSource: 文件大小 = $sourceLength bytes');

      // 获取文件流
      final stream = await fileSystem.getFileStream(
        path,
        range: start != null || end != null
            ? FileRange(
                start: start ?? 0,
                end: end,
              )
            : null,
      );

      // 计算内容长度
      final contentLength = end != null
          ? (end - (start ?? 0))
          : (sourceLength - (start ?? 0));

      logger.d('NasStreamAudioSource: 返回流 contentLength=$contentLength, sourceLength=$sourceLength');

      return StreamAudioResponse(
        sourceLength: sourceLength,
        contentLength: contentLength,
        offset: start ?? 0,
        stream: stream,
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
      'm4a' || 'aac' => 'audio/aac',
      'ogg' => 'audio/ogg',
      'opus' => 'audio/opus',
      'wma' => 'audio/x-ms-wma',
      _ => 'audio/mpeg', // 默认
    };
  }
}

