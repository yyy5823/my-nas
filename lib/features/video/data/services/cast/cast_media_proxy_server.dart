import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

/// 投屏媒体代理服务器
/// 为投屏设备提供HTTP访问NAS文件的能力
class CastMediaProxyServer {
  CastMediaProxyServer({
    this.port = 8899,
  });

  /// 服务器端口
  final int port;

  /// HTTP 服务器实例
  HttpServer? _server;

  /// 是否正在运行
  bool get isRunning => _server != null;

  /// 注册的媒体流
  final Map<String, _StreamRegistration> _streams = {};

  /// 本机 IP 地址
  String? _localIp;

  /// 获取本机 IP
  Future<String?> getLocalIp() async {
    if (_localIp != null) return _localIp;

    try {
      final info = NetworkInfo();
      _localIp = await info.getWifiIP();
      return _localIp;
    } catch (e, st) {
      AppError.handle(e, st, 'getLocalIp');
      return null;
    }
  }

  /// 启动服务器
  Future<void> start() async {
    if (isRunning) {
      logger.i('投屏代理服务器已在运行');
      return;
    }

    final router = Router();

    // 媒体流路由
    router.get('/stream/<token>', _handleStreamRequest);

    // 字幕路由
    router.get('/subtitle/<token>', _handleSubtitleRequest);

    // 健康检查
    router.get('/health', (shelf.Request request) {
      return shelf.Response.ok('OK');
    });

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      logger.i('投屏代理服务器启动成功: http://0.0.0.0:$port');
    } catch (e, st) {
      AppError.handle(e, st, 'startCastProxyServer');
      rethrow;
    }
  }

  /// 确保服务器运行
  Future<void> ensureRunning() async {
    if (!isRunning) {
      await start();
    }
  }

  /// 停止服务器
  Future<void> stop() async {
    if (!isRunning) return;

    await _server?.close(force: true);
    _server = null;
    _streams.clear();
    logger.i('投屏代理服务器已停止');
  }

  /// 注册媒体流
  /// 返回访问 token
  String registerStream({
    required String path,
    required NasFileSystem fileSystem,
    String? mimeType,
    int? fileSize,
    String? subtitlePath,
  }) {
    final token = const Uuid().v4();

    _streams[token] = _StreamRegistration(
      path: path,
      fileSystem: fileSystem,
      mimeType: mimeType ?? _getMimeType(path),
      fileSize: fileSize,
      subtitlePath: subtitlePath,
      createdAt: DateTime.now(),
    );

    logger.i('注册媒体流: token=$token, path=$path');
    return token;
  }

  /// 注销媒体流
  void unregisterStream(String token) {
    _streams.remove(token);
    logger.i('注销媒体流: token=$token');
  }

  /// 获取媒体流 URL
  Future<String?> getStreamUrl(String token) async {
    final localIp = await getLocalIp();
    if (localIp == null) return null;
    return 'http://$localIp:$port/stream/$token';
  }

  /// 获取字幕 URL
  Future<String?> getSubtitleUrl(String token) async {
    final registration = _streams[token];
    if (registration?.subtitlePath == null) return null;

    final localIp = await getLocalIp();
    if (localIp == null) return null;
    return 'http://$localIp:$port/subtitle/$token';
  }

  /// 处理媒体流请求
  Future<shelf.Response> _handleStreamRequest(shelf.Request request) async {
    final token = request.params['token'];
    if (token == null) {
      return shelf.Response.notFound('Token required');
    }

    final registration = _streams[token];
    if (registration == null) {
      return shelf.Response.notFound('Stream not found');
    }

    try {
      // 解析 Range 请求头
      final rangeHeader = request.headers['range'];
      FileRange? range;

      if (rangeHeader != null) {
        range = _parseRangeHeader(rangeHeader, registration.fileSize);
      }

      // 获取文件流
      final stream = await registration.fileSystem.getFileStream(
        registration.path,
        range: range,
      );

      // 构建响应头
      final headers = <String, String>{
        'Content-Type': registration.mimeType,
        'Accept-Ranges': 'bytes',
        'Access-Control-Allow-Origin': '*',
      };

      // 处理 Range 响应
      if (range != null && registration.fileSize != null) {
        final start = range.start;
        final end = range.end ?? registration.fileSize! - 1;
        final length = end - start + 1;

        headers['Content-Range'] = 'bytes $start-$end/${registration.fileSize}';
        headers['Content-Length'] = length.toString();

        return shelf.Response(
          206, // Partial Content
          body: stream,
          headers: headers,
        );
      }

      // 完整响应
      if (registration.fileSize != null) {
        headers['Content-Length'] = registration.fileSize.toString();
      }

      return shelf.Response.ok(
        stream,
        headers: headers,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'handleStreamRequest', {'token': token});
      return shelf.Response.internalServerError(body: 'Error streaming file: $e');
    }
  }

  /// 处理字幕请求
  Future<shelf.Response> _handleSubtitleRequest(shelf.Request request) async {
    final token = request.params['token'];
    if (token == null) {
      return shelf.Response.notFound('Token required');
    }

    final registration = _streams[token];
    if (registration == null || registration.subtitlePath == null) {
      return shelf.Response.notFound('Subtitle not found');
    }

    try {
      final stream = await registration.fileSystem.getFileStream(registration.subtitlePath!);

      final mimeType = _getMimeType(registration.subtitlePath!);

      return shelf.Response.ok(
        stream,
        headers: {
          'Content-Type': mimeType,
          'Access-Control-Allow-Origin': '*',
        },
      );
    } catch (e, st) {
      AppError.handle(e, st, 'handleSubtitleRequest', {'token': token});
      return shelf.Response.internalServerError(body: 'Error loading subtitle: $e');
    }
  }

  /// 解析 Range 请求头
  FileRange? _parseRangeHeader(String rangeHeader, int? totalSize) {
    // 格式: bytes=start-end 或 bytes=start-
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    if (match == null) return null;

    final start = int.parse(match.group(1)!);
    final endStr = match.group(2);
    final end = endStr != null && endStr.isNotEmpty ? int.parse(endStr) : null;

    return FileRange(start: start, end: end);
  }

  /// 根据文件扩展名获取 MIME 类型
  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      // 视频
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'avi' => 'video/x-msvideo',
      'mov' => 'video/quicktime',
      'wmv' => 'video/x-ms-wmv',
      'flv' => 'video/x-flv',
      'webm' => 'video/webm',
      'ts' => 'video/mp2t',
      'm2ts' => 'video/mp2t',
      // 字幕
      'srt' => 'text/plain; charset=utf-8',
      'vtt' => 'text/vtt',
      'ass' => 'text/plain; charset=utf-8',
      'ssa' => 'text/plain; charset=utf-8',
      // 默认
      _ => 'application/octet-stream',
    };
  }

  /// 清理过期的流注册
  void cleanupExpiredStreams({Duration maxAge = const Duration(hours: 2)}) {
    final now = DateTime.now();
    final expiredTokens = <String>[];

    for (final entry in _streams.entries) {
      if (now.difference(entry.value.createdAt) > maxAge) {
        expiredTokens.add(entry.key);
      }
    }

    for (final token in expiredTokens) {
      _streams.remove(token);
    }

    if (expiredTokens.isNotEmpty) {
      logger.i('清理过期媒体流: ${expiredTokens.length} 个');
    }
  }
}

/// 流注册信息
class _StreamRegistration {
  const _StreamRegistration({
    required this.path,
    required this.fileSystem,
    required this.mimeType,
    required this.createdAt,
    this.fileSize,
    this.subtitlePath,
  });

  final String path;
  final NasFileSystem fileSystem;
  final String mimeType;
  final int? fileSize;
  final String? subtitlePath;
  final DateTime createdAt;
}
