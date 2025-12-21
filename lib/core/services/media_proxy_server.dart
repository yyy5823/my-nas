import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 媒体代理服务器
///
/// 为不支持直接 URL 访问的协议（如 SMB）提供 HTTP 代理
/// 将 SMB 等协议的文件流转换为 HTTP 流供播放器使用
class MediaProxyServer {
  factory MediaProxyServer() => _instance ??= MediaProxyServer._();
  MediaProxyServer._();

  static MediaProxyServer? _instance;

  HttpServer? _server;
  int _port = 0;

  /// 当前代理的文件信息
  final Map<String, _ProxyFileInfo> _proxyFiles = {};

  /// 服务器是否正在运行
  bool get isRunning => _server != null;

  /// 获取代理服务器端口
  int get port => _port;

  /// 启动代理服务器
  Future<void> start() async {
    if (_server != null) {
      logger.d('MediaProxyServer: 服务器已在运行，端口 $_port');
      return;
    }

    try {
      // 绑定到本地随机端口
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      logger.i('MediaProxyServer: 启动成功，端口 $_port');

      // 处理请求
      _server!.listen(_handleRequest, onError: (Object error, StackTrace st) {
        AppError.handle(error, st, 'MediaProxyServer.listen');
      });
    } catch (e, st) {
      AppError.handle(e, st, 'MediaProxyServer.start');
      rethrow;
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (_server == null) return;

    try {
      await _server!.close(force: true);
      _server = null;
      _port = 0;
      _proxyFiles.clear();
      logger.i('MediaProxyServer: 已停止');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MediaProxyServer.stop');
    }
  }

  /// 注册一个文件用于代理
  ///
  /// 返回可通过 HTTP 访问的代理 URL
  Future<String> registerFile({
    required String sourceId,
    required String filePath,
    required int fileSize,
  }) async {
    // 确保服务器已启动
    if (!isRunning) {
      await start();
    }

    // 生成唯一标识
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    _proxyFiles[id] = _ProxyFileInfo(
      sourceId: sourceId,
      filePath: filePath,
      fileSize: fileSize,
    );

    final proxyUrl = 'http://127.0.0.1:$_port/media/$id';
    logger.d('MediaProxyServer: 注册文件 $filePath => $proxyUrl');

    return proxyUrl;
  }

  /// 取消注册文件
  void unregisterFile(String id) {
    _proxyFiles.remove(id);
    logger.d('MediaProxyServer: 取消注册文件 $id');
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    logger.d('MediaProxyServer: 收到请求 ${request.method} $path');

    // 解析路径: /media/{id}
    if (!path.startsWith('/media/')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final id = path.substring('/media/'.length);
    final fileInfo = _proxyFiles[id];

    if (fileInfo == null) {
      logger.w('MediaProxyServer: 文件未注册 $id');
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      await _streamFile(request, fileInfo);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MediaProxyServer._handleRequest', {
        'path': fileInfo.filePath,
        'sourceId': fileInfo.sourceId,
      });
      try {
        // 只有在还没发送响应头时才能设置状态码
        request.response.statusCode = HttpStatus.internalServerError;
      // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // 响应头可能已经发送
      }
      try {
        await request.response.close();
      // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // 响应可能已经关闭
      }
    }
  }

  /// 流式传输文件
  Future<void> _streamFile(HttpRequest request, _ProxyFileInfo fileInfo) async {
    // 获取文件系统，如果连接不健康则尝试重连
    var conn = SourceManagerService().getConnection(fileInfo.sourceId);

    if (conn == null || conn.status != SourceStatus.connected) {
      logger.w('MediaProxyServer: 源未连接，尝试重连 ${fileInfo.sourceId}');
      // 尝试重连
      final reconnected = await SourceManagerService().ensureConnectionHealthy(fileInfo.sourceId);
      if (reconnected) {
        conn = SourceManagerService().getConnection(fileInfo.sourceId);
        logger.i('MediaProxyServer: 重连成功 ${fileInfo.sourceId}');
      }
    } else {
      // 检查连接健康状态
      final isHealthy = await conn.adapter.checkConnectionHealth();
      if (!isHealthy) {
        logger.w('MediaProxyServer: 连接不健康，尝试重连 ${fileInfo.sourceId}');
        final reconnected = await SourceManagerService().ensureConnectionHealthy(fileInfo.sourceId);
        if (reconnected) {
          conn = SourceManagerService().getConnection(fileInfo.sourceId);
          logger.i('MediaProxyServer: 重连成功 ${fileInfo.sourceId}');
        }
      }
    }

    // 再次检查连接状态
    if (conn == null || conn.status != SourceStatus.connected) {
      logger.e('MediaProxyServer: 源连接失败 ${fileInfo.sourceId}');
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final fileSystem = conn.adapter.fileSystem;
    final fileSize = fileInfo.fileSize;

    // 解析 Range 头
    FileRange? range;
    var contentLength = fileSize;
    var statusCode = HttpStatus.ok;

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      range = _parseRangeHeader(rangeHeader, fileSize);
      if (range != null) {
        contentLength = (range.end ?? fileSize) - range.start;
        statusCode = HttpStatus.partialContent;
        logger.d('MediaProxyServer: Range 请求 ${range.start}-${range.end ?? fileSize}');
      }
    }

    // 设置响应头
    request.response.statusCode = statusCode;
    request.response.headers.set(HttpHeaders.contentTypeHeader, _getMimeType(fileInfo.filePath));
    request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    if (range != null) {
      final end = range.end ?? fileSize;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${end - 1}/$fileSize',
      );
    }

    // 对于 HEAD 请求只返回头信息
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    // 获取文件流并传输
    try {
      final stream = await fileSystem.getFileStream(fileInfo.filePath, range: range);
      await request.response.addStream(stream);
      await request.response.close();
    } on Exception catch (e, st) {
      // 上报流传输错误（可能是连接断开、读取失败等）
      AppError.handle(e, st, 'MediaProxyServer.streamTransfer', {
        'path': fileInfo.filePath,
        'sourceId': fileInfo.sourceId,
        'rangeStart': range?.start,
        'rangeEnd': range?.end,
      });
      try {
        await request.response.close();
      // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // 响应可能已经关闭
      }
    }
  }

  /// 解析 Range 头
  FileRange? _parseRangeHeader(String rangeHeader, int fileSize) {
    // 格式: bytes=start-end 或 bytes=start-
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    if (match == null) return null;

    final start = int.parse(match.group(1)!);
    final endStr = match.group(2);
    final end = endStr != null && endStr.isNotEmpty ? int.parse(endStr) + 1 : null;

    return FileRange(start: start, end: end);
  }

  /// 根据文件扩展名获取 MIME 类型
  String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (ext) {
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'avi' => 'video/x-msvideo',
      'mov' => 'video/quicktime',
      'wmv' => 'video/x-ms-wmv',
      'flv' => 'video/x-flv',
      'webm' => 'video/webm',
      'ts' => 'video/mp2t',
      'm4v' => 'video/x-m4v',
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'wma' => 'audio/x-ms-wma',
      _ => 'application/octet-stream',
    };
  }
}

/// 代理文件信息
class _ProxyFileInfo {
  const _ProxyFileInfo({
    required this.sourceId,
    required this.filePath,
    required this.fileSize,
  });

  final String sourceId;
  final String filePath;
  final int fileSize;
}
