import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_connection_pool.dart';
import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';

/// SMB 文件系统实现
///
/// 使用 smb_connect 库实现文件操作
/// 支持连接池，长操作（视频流）使用独立连接
class SmbFileSystem implements NasFileSystem {
  SmbFileSystem({
    required this.client,
    this.connectionPool,
  });

  /// 主连接（用于快速操作）
  final SmbConnect client;

  /// 连接池（用于并发操作）
  final SmbConnectionPool? connectionPool;

  /// 缓存的共享列表
  List<SmbFile>? _cachedShares;

  /// 检查是否是连接断开错误
  bool _isConnectionError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('network name is no longer available') ||
        msg.contains('connection closed') ||
        msg.contains('socket closed') ||
        msg.contains('streamsink is closed') ||
        msg.contains('connection reset') ||
        msg.contains('broken pipe');
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('SmbFileSystem: listDirectory => $path');

    // 根目录显示共享列表
    if (path == '/' || path.isEmpty) {
      return listShares();
    }

    // 尝试使用主连接
    try {
      return await _listDirectoryWithClient(client, path);
    } on Exception catch (e) {
      // 如果是连接错误且有连接池，尝试用新连接重试
      if (_isConnectionError(e) && connectionPool != null) {
        logger.w('SmbFileSystem: 主连接断开，使用连接池重试');
        return connectionPool!.withConnection(
          (poolClient) => _listDirectoryWithClient(poolClient, path),
          type: SmbConnectionType.general,
        );
      }
      rethrow;
    }
  }

  /// 使用指定连接列出目录
  Future<List<FileItem>> _listDirectoryWithClient(
    SmbConnect smbClient,
    String path,
  ) async {
    try {
      final folder = await smbClient.file(path);
      final files = await smbClient.listFiles(folder);
      return files.map(_toFileItem).toList();
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SmbFileSystem.listDirectory');
      rethrow;
    }
  }

  /// 列出共享文件夹
  Future<List<FileItem>> listShares() async {
    logger.d('SmbFileSystem: 获取共享列表');

    // 使用缓存
    if (_cachedShares != null && _cachedShares!.isNotEmpty) {
      return _cachedShares!.map(_toFileItem).toList();
    }

    final shares = await client.listShares();
    _cachedShares = shares;

    logger.i('SmbFileSystem: 获取到 ${shares.length} 个共享');

    return shares.map(_toFileItem).toList();
  }

  /// 清除共享缓存
  void clearSharesCache() {
    _cachedShares = null;
  }

  FileItem _toFileItem(SmbFile file) {
    final name = file.name;
    final isDir = file.isDirectory(); // isDirectory 是方法

    return FileItem(
      name: name,
      path: file.path,
      isDirectory: isDir,
      size: file.size,
      // lastModified 和 createTime 是 int (Unix 时间戳毫秒)
      modifiedTime: file.lastModified > 0
          ? DateTime.fromMillisecondsSinceEpoch(file.lastModified)
          : null,
      createdTime: file.createTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(file.createTime)
          : null,
      extension: isDir ? null : _getExtension(name),
      isHidden: name.startsWith('.') || file.isHidden(),
    );
  }

  String? _getExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return null;
    return fileName.substring(dotIndex + 1);
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    // 尝试使用主连接
    try {
      final file = await client.file(path);
      return _toFileItem(file);
    } on Exception catch (e) {
      // 如果是连接错误且有连接池，尝试用新连接重试
      if (_isConnectionError(e) && connectionPool != null) {
        logger.w('SmbFileSystem: getFileInfo 主连接断开，使用连接池重试');
        return connectionPool!.withConnection(
          (poolClient) async {
            final file = await poolClient.file(path);
            return _toFileItem(file);
          },
          type: SmbConnectionType.general,
        );
      }
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    // 视频流使用独立连接，避免与其他操作冲突
    // 如果有连接池，创建专用连接；否则使用主连接
    SmbConnect streamClient;
    void Function()? releaseCallback;

    if (connectionPool != null) {
      final dedicated = await connectionPool!.createDedicatedConnection();
      streamClient = dedicated.client;
      releaseCallback = dedicated.releaseCallback;
    } else {
      streamClient = client;
    }

    /// 清理专用连接
    Future<void> cleanup() async {
      if (releaseCallback != null) {
        try {
          await streamClient.close();
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {}
        releaseCallback();
      }
    }

    try {
      final file = await streamClient.file(path);
      final fileSize = file.size;

      if (range != null) {
        // 使用 RandomAccessFile 实现范围读取
        final raf = await streamClient.open(file);

        try {
          await raf.setPosition(range.start);
          final length = range.end != null ? range.end! - range.start : fileSize - range.start;

          // 分块读取
          final controller = StreamController<List<int>>();
          const chunkSize = 64 * 1024; // 64KB chunks
          var remaining = length;

          unawaited(() async {
            try {
              while (remaining > 0) {
                final toRead = remaining > chunkSize ? chunkSize : remaining;
                final chunk = await raf.read(toRead);
                controller.add(chunk);
                remaining -= chunk.length;
                if (chunk.isEmpty) break;
              }
              await controller.close();
            } on Exception catch (e) {
              controller.addError(e);
              await controller.close();
            } finally {
              await raf.close();
              await cleanup();
            }
          }());

          return controller.stream;
        } on Exception {
          await raf.close();
          rethrow;
        }
      } else {
        // 完整文件流 - 包装以便在完成时关闭连接
        final rawStream = await streamClient.openRead(file);

        if (releaseCallback != null) {
          // 包装流，在完成时关闭专用连接
          final controller = StreamController<List<int>>();
          rawStream.listen(
            controller.add,
            onError: controller.addError,
            onDone: () async {
              await controller.close();
              await cleanup();
            },
            cancelOnError: true,
          );
          return controller.stream;
        }

        return rawStream;
      }
    } on Exception {
      await cleanup();
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) =>
      throw UnimplementedError('SMB 不支持通过 URL 获取数据流');

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      // SMB 不支持直接 URL 访问，需要通过流来访问
      // 返回一个特殊的 smb:// URL 格式，应用层需要处理
      'smb://smb-local$path';

  @override
  Future<void> createDirectory(String path) async {
    await client.createFolder(path);
  }

  @override
  Future<void> delete(String path) async {
    final file = await client.file(path);
    await client.delete(file);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final file = await client.file(oldPath);
    await client.rename(file, newPath);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    // SMB 原生不支持服务端复制，需要下载后上传
    throw UnimplementedError('SMB 暂不支持服务端复制，请使用下载后上传');
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await rename(sourcePath, destPath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('本地文件不存在', localPath);
    }

    final name = fileName ?? p.basename(localPath);
    final targetPath = remotePath.endsWith('/') ? '$remotePath$name' : '$remotePath/$name';

    // 创建远程文件
    await client.createFile(targetPath);
    final remoteFile = await client.file(targetPath);

    // 获取写入流
    final writer = await client.openWrite(remoteFile);

    try {
      final total = await file.length();
      var sent = 0;

      await for (final chunk in file.openRead()) {
        writer.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent, total);
      }

      await writer.flush();
      await writer.close();
    } on Exception {
      await writer.close();
      rethrow;
    }
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    // SMB 不支持服务端搜索，需要客户端遍历实现
    throw UnimplementedError('SMB 暂不支持搜索功能');
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async => null;
}
